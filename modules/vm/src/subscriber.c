#define _GNU_SOURCE
#include <errno.h>
#include <jansson.h>
#include <libyang/libyang.h>
#include <limits.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
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
        lyd_new_term(output, NULL, "error", "VM operation is unavailable; inspect the retained job and service journal",
            LYD_NEW_VAL_OUTPUT, NULL) != LY_SUCCESS) return SR_ERR_CALLBACK_FAILED;
    return SR_ERR_OK;
}
static int execute(sr_session_ctx_t *session, uint32_t sub_id, const char *xpath,
        const struct lyd_node *input, sr_event_t event, uint32_t request_id,
        struct lyd_node *output, void *private_data)
{
    (void)session; (void)sub_id; (void)xpath; (void)request_id; (void)private_data;
    if (event == SR_EV_ABORT) return SR_ERR_OK;
    const char *action = field(input, "action"), *id = field(input, "job-id");
    if (!action || !id) return SR_ERR_INVAL_ARG;
    FILE *result = tmpfile();
    if (!result) return unavailable(output);
    pid_t pid = fork();
    if (!pid) {
        if (dup2(fileno(result), STDOUT_FILENO) < 0) _exit(126);
        if (!strcmp(action, "build")) {
            const char *source = field(input, "source");
            if (!source) _exit(2);
            execl(TIMEOUT, "timeout", "--kill-after=2", "40", TOOL, action, id, source, (char *)NULL);
        } else if (!strcmp(action, "start")) {
            execl(TIMEOUT, "timeout", "--kill-after=2", "40", TOOL, action, id,
                field(input, "memory"), field(input, "cores"), (char *)NULL);
        } else execl(TIMEOUT, "timeout", "--kill-after=2", "40", TOOL, action, id, (char *)NULL);
        _exit(126);
    }
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
int main(void)
{
    const char *runtime = getenv("XDG_RUNTIME_DIR"), *state = getenv("XDG_STATE_HOME"), *home = getenv("HOME");
    char repository[PATH_MAX], shm[PATH_MAX], prefix[64];
    if (!geteuid() || !runtime || runtime[0] != '/' || !home || home[0] != '/') return 1;
    if (snprintf(repository, sizeof(repository), "%s%s/folio/sysrepo", state ? state : home,
            state ? "" : "/.local/state") >= (int)sizeof(repository) ||
        snprintf(shm, sizeof(shm), "%s/folio/sysrepo", runtime) >= (int)sizeof(shm)) return 1;
    snprintf(prefix, sizeof(prefix), "folio_user_%u", (unsigned)geteuid());
    setenv("SYSREPO_REPOSITORY_PATH", repository, 1);
    setenv("SYSREPO_SHM_DIR", shm, 1); setenv("SYSREPO_SHM_PREFIX", prefix, 1);
    unsetenv("SYSREPO_PLUGINS_PATH");
    sr_conn_ctx_t *connection = NULL;
    sr_session_ctx_t *session = NULL;
    sr_subscription_ctx_t *subscription = NULL;
    int code = sr_connect(0, &connection);
    if (!code) code = sr_session_start(connection, SR_DS_RUNNING, &session);
    if (!code) code = sr_rpc_subscribe_tree(session, "/folio-vm:execute", execute, NULL, 0, 0, &subscription);
    if (!code) {
        signal(SIGINT, stop); signal(SIGTERM, stop);
        fprintf(stderr, "Folio VM subscriptions ready\n");
        while (!stopping) sleep(1);
    } else fprintf(stderr, "Unable to subscribe to VM operations: %s\n", sr_strerror(code));
    sr_unsubscribe(subscription); sr_session_stop(session); sr_disconnect(connection);
    return code ? 1 : 0;
}
