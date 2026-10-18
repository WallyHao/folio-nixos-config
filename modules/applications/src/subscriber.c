#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <jansson.h>
#include <libyang/libyang.h>
#include <limits.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <sysrepo.h>
#include <unistd.h>

static volatile sig_atomic_t stopping;
static void stop(int number) { (void)number; stopping = 1; }
static const char *field(const struct lyd_node *input, const char *name)
{
    const struct lyd_node *node;
    LY_LIST_FOR(lyd_child(input), node)
        if (!strcmp(node->schema->name, name)) return lyd_get_value(node);
    return NULL;
}
static int unavailable(struct lyd_node *output)
{
    if (lyd_new_term(output, NULL, "status", "unavailable", LYD_NEW_VAL_OUTPUT, NULL) != LY_SUCCESS ||
        lyd_new_term(output, NULL, "error", "Application operation is unavailable; inspect the retained job and service journal",
            LYD_NEW_VAL_OUTPUT, NULL) != LY_SUCCESS) return SR_ERR_CALLBACK_FAILED;
    return SR_ERR_OK;
}
static int execute(sr_session_ctx_t *session, uint32_t sub_id, const char *xpath,
        const struct lyd_node *input, sr_event_t event, uint32_t request_id,
        struct lyd_node *output, void *private_data)
{
    (void)session; (void)sub_id; (void)xpath; (void)request_id; (void)private_data;
    if (event == SR_EV_ABORT) return SR_ERR_OK;
    if (!field(input, "action")) return SR_ERR_INVAL_ARG;
    json_t *request = json_object();
    const struct lyd_node *node;
    LY_LIST_FOR(lyd_child(input), node) {
        const char *name = node->schema->name, *value = lyd_get_value(node);
        json_object_set_new(request, name,
            (!strcmp(name, "adopt-files") || !strcmp(name, "offline")) ?
            json_boolean(!strcmp(value, "true")) : json_string(value));
    }
    FILE *request_file = tmpfile(), *result = tmpfile();
    if (!request_file || !result) {
        if (request_file) fclose(request_file);
        if (result) fclose(result);
        json_decref(request); return unavailable(output);
    }
    json_dumpf(request, request_file, JSON_COMPACT); json_decref(request);
    fflush(request_file); rewind(request_file);
    pid_t pid = fork();
    if (!pid) {
        if (dup2(fileno(result), STDOUT_FILENO) < 0 ||
            dup2(fileno(request_file), STDIN_FILENO) < 0) _exit(126);
        execl(TIMEOUT, "timeout", "--kill-after=2", "40", TOOL, "execute", (char *)NULL);
        _exit(126);
    }
    fclose(request_file);
    int status = 0;
    if (pid < 0) { fclose(result); return unavailable(output); }
    while (waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) { fclose(result); return unavailable(output); }
    }
    long length = ftell(result);
    if (!WIFEXITED(status) || length < 2 || length > 1024 * 1024) {
        fclose(result); return unavailable(output);
    }
    rewind(result);
    json_error_t error;
    json_t *record = json_loadf(result, JSON_REJECT_DUPLICATES, &error);
    fclose(result);
    const char *reply_status = record ? json_string_value(json_object_get(record, "status")) : NULL;
    char *json = record ? json_dumps(record, JSON_COMPACT) : NULL;
    int code = SR_ERR_OK;
    if (!reply_status || !json) code = unavailable(output);
    else if (lyd_new_term(output, NULL, "status", reply_status, LYD_NEW_VAL_OUTPUT, NULL) != LY_SUCCESS ||
        lyd_new_term(output, NULL, "result-json", json, LYD_NEW_VAL_OUTPUT, NULL) != LY_SUCCESS) code = SR_ERR_CALLBACK_FAILED;
    free(json); json_decref(record);
    return code;
}
static int state_value(struct lyd_node **parent, const struct ly_ctx *context,
        const char *name, const char *leaf, const char *value)
{
    char path[1024]; struct lyd_node *node = NULL;
    if (snprintf(path, sizeof(path), "/folio-environment:environment/modules[name='applications']/folio-applications:applications/app[name='%s']/state/%s", name, leaf) >= (int)sizeof(path)) return -1;
    if (lyd_new_path(*parent, context, path, value, LYD_NEW_PATH_UPDATE, &node) != LY_SUCCESS) return -1;
    if (!*parent && node) {
        while (lyd_parent(node)) node = lyd_parent(node);
        *parent = lyd_first_sibling(node);
    }
    return 0;
}
static int operational(sr_session_ctx_t *session, uint32_t sub_id, const char *module_name,
        const char *path, const char *request_xpath, uint32_t request_id,
        struct lyd_node **parent, void *private_data)
{
    (void)sub_id; (void)module_name; (void)path; (void)request_xpath; (void)request_id; (void)private_data;
    FILE *file = tmpfile();
    if (!file) return SR_ERR_CALLBACK_FAILED;
    pid_t child = fork();
    if (!child) {
        if (dup2(fileno(file), STDOUT_FILENO) < 0) _exit(126);
        execl(TIMEOUT, "timeout", "--kill-after=2", "20", TOOL, "observed", (char *)NULL);
        _exit(126);
    }
    int status = 0;
    if (child < 0) { fclose(file); return SR_ERR_CALLBACK_FAILED; }
    while (waitpid(child, &status, 0) < 0) if (errno != EINTR) { fclose(file); return SR_ERR_CALLBACK_FAILED; }
    rewind(file); json_error_t error;
    json_t *reply = json_loadf(file, JSON_REJECT_DUPLICATES, &error); fclose(file);
    json_t *apps = reply ? json_object_get(json_object_get(reply, "data"), "applications") : NULL;
    if (!WIFEXITED(status) || WEXITSTATUS(status) || !json_is_array(apps)) { json_decref(reply); return SR_ERR_CALLBACK_FAILED; }
    sr_conn_ctx_t *connection = sr_session_get_connection(session);
    const struct ly_ctx *context = sr_acquire_context(connection);
    if (!context) { json_decref(reply); return SR_ERR_CALLBACK_FAILED; }
    int code = SR_ERR_OK;
    size_t index; json_t *app;
    json_array_foreach(apps, index, app) {
        const char *name = json_string_value(json_object_get(app, "name"));
        if (!name || (strcmp(name, "zen") && strcmp(name, "obs"))) { code = SR_ERR_CALLBACK_FAILED; break; }
        json_t *actual = json_object_get(app, "actual");
        const char *commit = json_string_value(json_object_get(actual, "commit"));
        const char *configuration = json_string_value(json_object_get(app, "configurationState"));
        if (state_value(parent, context, name, "installed", json_is_true(json_object_get(app, "installed")) ? "true" : "false") ||
            state_value(parent, context, name, "owned", json_is_true(json_object_get(app, "owned")) ? "true" : "false") ||
            (commit && state_value(parent, context, name, "actual-commit", commit)) ||
            (configuration && state_value(parent, context, name, "configuration-state", configuration))) { code = SR_ERR_CALLBACK_FAILED; break; }
    }
    sr_release_context(connection); json_decref(reply);
    return code;
}
int main(void)
{
    const char *runtime = getenv("XDG_RUNTIME_DIR"), *state = getenv("XDG_STATE_HOME"), *home = getenv("HOME");
    char repository[PATH_MAX], shm[PATH_MAX], prefix[64];
    if (!geteuid() || !runtime || runtime[0] != '/' || !home || home[0] != '/') return 1;
    if (snprintf(repository, sizeof(repository), "%s%s/folio/sysrepo", state ? state : home,
            state ? "" : "/.local/state") >= (int)sizeof(repository) ||
        snprintf(shm, sizeof(shm), "%s/folio/sysrepo", runtime) >= (int)sizeof(shm)) return 1;
    snprintf(prefix, sizeof(prefix), "folio_user_%u", (unsigned)geteuid());
    char lock_path[PATH_MAX];
    if (snprintf(lock_path, sizeof(lock_path), "%s%s/folio/repository.lock", state ? state : home,
            state ? "" : "/.local/state") >= (int)sizeof(lock_path)) return 1;
    int repository_lock = open(lock_path, O_RDWR | O_NOFOLLOW | O_CLOEXEC);
    if (repository_lock < 0 || flock(repository_lock, LOCK_SH | LOCK_NB)) {
        fprintf(stderr, "Repository is unavailable or under offline maintenance\n"); return 3;
    }
    setenv("SYSREPO_REPOSITORY_PATH", repository, 1);
    setenv("SYSREPO_SHM_DIR", shm, 1); setenv("SYSREPO_SHM_PREFIX", prefix, 1);
    unsetenv("SYSREPO_PLUGINS_PATH");
    sr_conn_ctx_t *connection = NULL;
    sr_session_ctx_t *session = NULL;
    sr_subscription_ctx_t *subscription = NULL;
    int code = sr_connect(0, &connection);
    if (!code) code = sr_session_start(connection, SR_DS_RUNNING, &session);
    if (!code) code = sr_rpc_subscribe_tree(session, "/folio-applications:execute", execute, NULL, 0, 0, &subscription);
    if (!code) code = sr_oper_get_subscribe(session, "folio-environment",
        "/folio-environment:environment/modules/folio-applications:applications/app/state",
        operational, NULL, SR_SUBSCR_OPER_MERGE, &subscription);
    if (!code) {
        signal(SIGINT, stop); signal(SIGTERM, stop);
        fprintf(stderr, "Folio applications subscriptions ready\n");
        while (!stopping) sleep(1);
    } else fprintf(stderr, "Unable to subscribe to Application operations: %s\n", sr_strerror(code));
    sr_unsubscribe(subscription); sr_session_stop(session); sr_disconnect(connection);
    return code ? 1 : 0;
}
