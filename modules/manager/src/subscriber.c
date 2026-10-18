#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <jansson.h>
#include <libyang/libyang.h>
#include <limits.h>
#include <pwd.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sysrepo.h>
#include <unistd.h>

static volatile sig_atomic_t stopping;
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
            if (json_is_null(child)) json_object_del(value, key);
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
    const char *runtime = getenv("XDG_RUNTIME_DIR");
    if (!runtime || snprintf(directory, sizeof(directory), "%s/folio/callback-XXXXXX", runtime) >= (int)sizeof(directory) ||
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
        execl(TIMEOUT_PROGRAM, "timeout", "--kill-after=2", "25", program, (char *)NULL);
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
    const char *client = sr_session_get_user(session);
    if (!owner || !client || strcmp(owner->pw_name, client)) {
        sr_session_set_error_message(session, "RPC session identity does not own this user repository");
        return SR_ERR_UNAUTHORIZED;
    }
    char *request = NULL;
    json_t *result = NULL;
    if (lyd_print_mem(&request, input, LYD_JSON, LYD_PRINT_SHRINK) != LY_SUCCESS ||
            execute(operation->program, request, &result)) {
        free(request);
        json_decref(result);
        if (lyd_new_term(output, NULL, "status", "failure", LYD_NEW_VAL_OUTPUT, NULL) != LY_SUCCESS ||
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
    if (argc != 3 || strcmp(argv[1], "user")) {
        fprintf(stderr, "Usage: folio-manager-subscriber user BOOTSTRAP_DIRECTORY\n");
        return 2;
    }
    umask(0077);
    const char *home = getenv("HOME"), *state = getenv("XDG_STATE_HOME"), *runtime = getenv("XDG_RUNTIME_DIR");
    char repository[PATH_MAX], shared[PATH_MAX], prefix[64], fallback[PATH_MAX];
    if (!home || !runtime || runtime[0] != '/') return 2;
    if (!state || !state[0]) {
        if (snprintf(fallback, sizeof(fallback), "%s/.local/state", home) >= (int)sizeof(fallback)) return 2;
        state = fallback;
    }
    if (state[0] != '/' || snprintf(repository, sizeof(repository), "%s/folio/sysrepo", state) >= (int)sizeof(repository) ||
            snprintf(shared, sizeof(shared), "%s/folio/sysrepo", runtime) >= (int)sizeof(shared)) return 2;
    snprintf(prefix, sizeof(prefix), "folio_user_%lu", (unsigned long)getuid());
    if (setenv("SYSREPO_REPOSITORY_PATH", repository, 1) || setenv("SYSREPO_SHM_DIR", shared, 1) ||
            setenv("SYSREPO_SHM_PREFIX", prefix, 1) || setenv("FOLIO_BOOTSTRAP", argv[2], 1)) return 1;
    unsetenv("SYSREPO_PLUGINS_PATH");
    json_t *recovery = NULL;
    if (execute(RECOVERY_OPERATION, "{}", &recovery) ||
            strcmp(json_string_value(json_object_get(recovery, "status")) ?: "", "success")) {
        json_decref(recovery);
        fprintf(stderr, "Configuration recovery failed; subscribers were not started\n");
        return 1;
    }
    json_decref(recovery);
    sr_conn_ctx_t *connection = NULL;
    sr_session_ctx_t *session = NULL;
    sr_subscription_ctx_t *subscription = NULL;
    int code = sr_connect(SR_CONN_DEFAULT, &connection);
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
        fprintf(stderr, "Folio manager user subscriptions ready\n");
        while (!stopping) sleep(1);
    } else {
        fprintf(stderr, "Unable to subscribe: %s\n", sr_strerror(code));
    }
    sr_unsubscribe(subscription);
    sr_session_stop(session);
    sr_disconnect(connection);
    return code == SR_ERR_OK ? 0 : 1;
}
