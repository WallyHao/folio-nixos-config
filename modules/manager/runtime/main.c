#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <jansson.h>
#include <libyang/libyang.h>
#include <limits.h>
#include <pwd.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sysrepo.h>
#include <unistd.h>

static volatile sig_atomic_t stopping;
static int system_scope;
static void stop(int signal_number) { (void)signal_number; stopping = 1; }

/* An absent YANG value is omitted, rather than encoded as an untyped JSON null.
 * Keep the outer CLI envelope's null fields outside the modeled anydata tree. */
static void omit_absent_values(json_t *value)
{
    if (json_is_object(value)) {
        const char *key;
        void *next;
        json_t *child;
        json_object_foreach_safe(value, next, key, child) {
            if (json_is_null(child) || (json_is_array(child) && !json_array_size(child))) json_object_del(value, key);
            else omit_absent_values(child);
        }
    } else if (json_is_array(value)) {
        size_t index;
        json_t *child;
        json_array_foreach(value, index, child) omit_absent_values(child);
    }
}

struct operation {
    const char *xpath;
    const char *program;
};
static const struct operation operations[] = {
    {"/folio-environment:configuration-commit", CONFIGURATION_OPERATION},
    {"/folio-deployment:plan", PLAN_OPERATION},
    {"/folio-deployment:build", BUILD_OPERATION},
    {"/folio-deployment:apply", APPLY_OPERATION},
    {"/folio-deployment:status", STATUS_OPERATION},
};

static int execute(const char *program, const char *input, json_t **result)
{
    char directory[PATH_MAX], request[PATH_MAX], response[PATH_MAX];
    const char *runtime = getenv("FOLIO_RUNTIME_ROOT");
    if (!runtime || snprintf(directory, sizeof(directory), "%s/callback-XXXXXX", runtime) >= (int)sizeof(directory) ||
            !mkdtemp(directory)) return -1;
    if (snprintf(request, sizeof(request), "%s/request", directory) >= (int)sizeof(request) ||
            snprintf(response, sizeof(response), "%s/response", directory) >= (int)sizeof(response)) {
        rmdir(directory);
        return -1;
    }
    int in = open(request, O_RDWR | O_CREAT | O_EXCL, 0600);
    int out = open(response, O_RDWR | O_CREAT | O_EXCL, 0600);
    int result_code = -1;
    FILE *stream = NULL;
    if (in < 0 || out < 0) goto cleanup;
    size_t length = strlen(input), offset = 0;
    if (length > 16 * 1024 * 1024) goto cleanup;
    while (offset < length) {
        ssize_t count = write(in, input + offset, length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) goto cleanup;
        offset += (size_t)count;
    }
    if (lseek(in, 0, SEEK_SET) < 0) goto cleanup;
    pid_t pid = fork();
    if (pid == 0) {
        if (dup2(in, STDIN_FILENO) < 0 || dup2(out, STDOUT_FILENO) < 0) _exit(126);
        close(in);
        close(out);
        const char *budget = !strcmp(program, PLAN_OPERATION) ? "120" : "25";
        execl(TIMEOUT_PROGRAM, "timeout", "--kill-after=2", budget, program, (char *)NULL);
        _exit(126);
    }
    if (pid < 0) goto cleanup;
    int status;
    while (waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) goto cleanup;
    }
    if (!WIFEXITED(status) || WEXITSTATUS(status) || lseek(out, 0, SEEK_SET) < 0) goto cleanup;
    struct stat info;
    if (fstat(out, &info) || info.st_size > 1024 * 1024) goto cleanup;
    stream = fdopen(dup(out), "r");
    if (!stream) goto cleanup;
    json_error_t error;
    *result = json_loadf(stream, JSON_REJECT_DUPLICATES, &error);
    if (!json_is_object(*result)) goto cleanup;
    result_code = 0;
cleanup:
    if (stream) fclose(stream);
    if (in >= 0) close(in);
    if (out >= 0) close(out);
    unlink(request);
    unlink(response);
    rmdir(directory);
    return result_code;
}

static int callback(sr_session_ctx_t *session, uint32_t sub_id, const char *xpath,
        const struct lyd_node *input, sr_event_t event, uint32_t request_id,
        struct lyd_node *output, void *private_data)
{
    (void)sub_id; (void)xpath; (void)request_id;
    const struct operation *operation = private_data;
    if (event == SR_EV_ABORT) return SR_ERR_OK;
    struct passwd *owner = getpwuid(geteuid());
    /* This is the subscriber's implicit session identity, not a requester name.
     * sysrepo checks the sender's real session user against module permissions;
     * kernel directory/SHM permissions restrict which local users can dispatch. */
    const char *subscriber_user = sr_session_get_user(session);
    if (!owner || !subscriber_user || strcmp(owner->pw_name, subscriber_user)) {
        sr_session_set_error_message(session, "Callback session does not match the subscriber owner");
        return SR_ERR_UNAUTHORIZED;
    }
    char *request = NULL;
    json_t *result = NULL;
    if (lyd_print_mem(&request, input, LYD_JSON, LYD_PRINT_SHRINK) != LY_SUCCESS ||
            execute(operation->program, request, &result)) {
        free(request);
        json_decref(result);
        const char *status = !strcmp(operation->xpath, "/folio-deployment:status") ? "unavailable" : "failure";
        if (lyd_new_term(output, NULL, "status", status, LYD_NEW_VAL_OUTPUT, NULL) != LY_SUCCESS ||
                lyd_new_term(output, NULL, "error", "Manager operation failed, timed out, or returned invalid output",
                    LYD_NEW_VAL_OUTPUT, NULL) != LY_SUCCESS) return SR_ERR_CALLBACK_FAILED;
        return SR_ERR_OK;
    }
    free(request);
    const char *key;
    json_t *value;
    int code = SR_ERR_OK;
    json_object_foreach(result, key, value) {
        if (json_is_null(value)) continue;
        if (!strcmp(key, "data") && json_is_object(value)) {
            if (!strncmp(operation->xpath, "/folio-deployment:", strlen("/folio-deployment:"))) {
                char *exact = json_dumps(value, JSON_COMPACT);
                LY_ERR exact_error = exact ? lyd_new_term(output, NULL, "result-json", exact,
                    LYD_NEW_VAL_OUTPUT, NULL) : LY_EMEM;
                free(exact);
                if (exact_error != LY_SUCCESS) { code = SR_ERR_CALLBACK_FAILED; break; }
            }
            omit_absent_values(value);
            char *data = json_dumps(value, JSON_COMPACT);
            LY_ERR error = data ? lyd_new_any(output, NULL, key, data, LYD_ANYDATA_JSON,
                LYD_NEW_VAL_OUTPUT, NULL) : LY_EMEM;
            free(data);
            if (error != LY_SUCCESS) { code = SR_ERR_CALLBACK_FAILED; break; }
            continue;
        }
        if (!json_is_string(value) || lyd_new_term(output, NULL, key,
                json_string_value(value), LYD_NEW_VAL_OUTPUT, NULL) != LY_SUCCESS) {
            code = SR_ERR_CALLBACK_FAILED;
            break;
        }
    }
    json_decref(result);
    return code;
}

static int operational(sr_session_ctx_t *session, uint32_t sub_id, const char *module_name,
        const char *path, const char *request_xpath, uint32_t request_id,
        struct lyd_node **parent, void *private_data)
{
    (void)sub_id; (void)module_name; (void)path; (void)request_xpath; (void)request_id;
    const char *root = private_data;
    json_t *result = NULL, *selected = NULL;
    char *data = NULL;
    struct lyd_node *tree = NULL;
    int code = SR_ERR_CALLBACK_FAILED;
    if (execute(OBSERVED_OPERATION, "{}", &result)) goto cleanup;
    selected = json_object();
    if (!selected || json_object_set(selected, root, json_object_get(result, root))) goto cleanup;
    data = json_dumps(selected, JSON_COMPACT);
    if (!data) goto cleanup;
    sr_conn_ctx_t *connection = sr_session_get_connection(session);
    const struct ly_ctx *ctx = sr_acquire_context(connection);
    if (!ctx) goto cleanup;
    LY_ERR error = lyd_parse_data_mem(ctx, data, LYD_JSON, LYD_PARSE_STRICT | LYD_PARSE_ONLY, 0, &tree);
    if (error == LY_SUCCESS) {
        if (*parent) error = lyd_merge_siblings(parent, tree, LYD_MERGE_DESTRUCT);
        else *parent = tree;
        tree = NULL;
    }
    sr_release_context(connection);
    if (error == LY_SUCCESS) code = SR_ERR_OK;
cleanup:
    lyd_free_all(tree);
    json_decref(selected);
    json_decref(result);
    free(data);
    return code;
}

int main(int argc, char **argv)
{
    if (argc != 3 || (strcmp(argv[1], "user") && strcmp(argv[1], "system"))) {
        fprintf(stderr, "Usage: folio-manager-subscriber user|system BOOTSTRAP_DIRECTORY\n");
        return 2;
    }
    system_scope = !strcmp(argv[1], "system");
    if (system_scope && geteuid() != 0) {
        fprintf(stderr, "The system subscriber must be provisioned and run as root\n");
        return 1;
    }
    umask(0077);
    const char *home = getenv("HOME"), *state = getenv("XDG_STATE_HOME"), *runtime = getenv("XDG_RUNTIME_DIR");
    char repository[PATH_MAX], shared[PATH_MAX], prefix[64], fallback[PATH_MAX];
    if (system_scope) { state = "/var/lib"; runtime = "/run"; }
    if (!home || !runtime || runtime[0] != '/') return 2;
    if (!state || !state[0]) {
        if (snprintf(fallback, sizeof(fallback), "%s/.local/state", home) >= (int)sizeof(fallback)) return 2;
        state = fallback;
    }
    if (state[0] != '/' || snprintf(repository, sizeof(repository), "%s/folio/sysrepo", state) >= (int)sizeof(repository) ||
            snprintf(shared, sizeof(shared), "%s/folio/sysrepo", runtime) >= (int)sizeof(shared)) return 2;
    char lock_path[PATH_MAX];
    if (snprintf(lock_path, sizeof(lock_path), "%s/folio/repository.lock", state) >= (int)sizeof(lock_path)) return 2;
    int repository_lock = open(lock_path, O_RDWR | O_NOFOLLOW | O_CLOEXEC);
    if (repository_lock < 0 || flock(repository_lock, LOCK_SH | LOCK_NB)) {
        fprintf(stderr, "Repository is unavailable or under offline maintenance\n"); return 3;
    }
    if (system_scope) snprintf(prefix, sizeof(prefix), "folio_system");
    else snprintf(prefix, sizeof(prefix), "folio_user_%lu", (unsigned long)getuid());
    if (setenv("SYSREPO_REPOSITORY_PATH", repository, 1) || setenv("SYSREPO_SHM_DIR", shared, 1) ||
            setenv("SYSREPO_SHM_PREFIX", prefix, 1) || setenv("FOLIO_BOOTSTRAP", argv[2], 1) ||
            setenv("FOLIO_SCOPE", argv[1], 1)) return 1;
    char runtime_root[PATH_MAX];
    if (snprintf(runtime_root, sizeof(runtime_root), "%s/folio", runtime) >= (int)sizeof(runtime_root) ||
            setenv("FOLIO_RUNTIME_ROOT", runtime_root, 1)) return 1;
    unsetenv("SYSREPO_PLUGINS_PATH");
    sr_conn_ctx_t *connection = NULL;
    sr_session_ctx_t *session = NULL;
    sr_subscription_ctx_t *subscription = NULL;
    int code = sr_connect(SR_CONN_DEFAULT, &connection);
    if (code == SR_ERR_OK && system_scope) {
        struct group *operators = getgrnam("folio-operators");
        if (!operators) code = SR_ERR_UNAUTHORIZED;
        for (size_t i = 0; code == SR_ERR_OK && i < 2; ++i) {
            const char *module = i ? "folio-deployment" : "folio-environment";
            char *owner_name = NULL, *group_name = NULL;
            mode_t permissions = 0;
            code = sr_get_module_ds_access(connection, module, SR_DS_STARTUP, &owner_name, &group_name, &permissions);
            if (code == SR_ERR_OK && (!owner_name || strcmp(owner_name, "root") || !group_name ||
                    strcmp(group_name, "folio-operators") || permissions != 0660)) {
                fprintf(stderr, "Unsafe startup access for %s: owner=%s group=%s mode=%04o\n",
                    module, owner_name ?: "unknown", group_name ?: "unknown", (unsigned)permissions);
                code = SR_ERR_UNAUTHORIZED;
            }
            free(owner_name);
            free(group_name);
        }
    }
    json_t *recovery = NULL;
    if (code == SR_ERR_OK && (execute(RECOVERY_OPERATION, "{}", &recovery) ||
            strcmp(json_string_value(json_object_get(recovery, "status")) ?: "", "success"))) {
        fprintf(stderr, "Configuration recovery failed; subscribers were not started\n");
        code = SR_ERR_CALLBACK_FAILED;
    }
    json_decref(recovery);
    if (code == SR_ERR_OK) code = sr_session_start(connection, SR_DS_RUNNING, &session);
    for (size_t i = 0; code == SR_ERR_OK && i < sizeof(operations) / sizeof(operations[0]); ++i) {
        code = sr_rpc_subscribe_tree(session, operations[i].xpath, callback, (void *)&operations[i], 0, 0, &subscription);
    }
    if (code == SR_ERR_OK) code = sr_oper_get_subscribe(session, "folio-environment", "/folio-environment:environment",
        operational, "folio-environment:environment", 0, &subscription);
    if (code == SR_ERR_OK) code = sr_oper_get_subscribe(session, "folio-deployment", "/folio-deployment:deployment",
        operational, "folio-deployment:deployment", 0, &subscription);
    if (code == SR_ERR_OK) {
        signal(SIGTERM, stop);
        signal(SIGINT, stop);
        fprintf(stderr, "Folio manager %s subscriptions ready\n", argv[1]);
        while (!stopping) sleep(1);
    } else {
        fprintf(stderr, "Unable to subscribe: %s\n", sr_strerror(code));
    }
    sr_unsubscribe(subscription);
    sr_session_stop(session);
    sr_disconnect(connection);
    return code == SR_ERR_OK ? 0 : 1;
}
