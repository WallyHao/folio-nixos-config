#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <jansson.h>
#include <libyang/libyang.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <sysrepo.h>
#include <unistd.h>

static volatile sig_atomic_t stopping;
static void stop(int signal_number) { (void)signal_number; stopping = 1; }

static int child_status(pid_t pid)
{
    int status;
    if (pid < 0) return -1;
    while (waitpid(pid, &status, 0) < 0) if (errno != EINTR) return -1;
    return WIFEXITED(status) && !WEXITSTATUS(status) ? 0 : -1;
}

static int write_record(const char *path, const char *action, const char *id, const char *phase)
{
    int descriptors[2];
    if (pipe(descriptors)) return -1;
    pid_t pid = fork();
    if (!pid) {
        close(descriptors[1]);
        if (dup2(descriptors[0], STDIN_FILENO) < 0) _exit(126);
        close(descriptors[0]);
        execl(TIMEOUT, "timeout", "--kill-after=1", "5", ATOMIC_WRITE, path, (char *)NULL);
        _exit(126);
    }
    close(descriptors[0]);
    char record[512];
    int length = snprintf(record, sizeof(record), "{\"action\":\"%s\",\"id\":\"%s\",\"phase\":\"%s\"}\n", action, id, phase);
    ssize_t written;
    do { written = write(descriptors[1], record, (size_t)length); } while (written < 0 && errno == EINTR);
    close(descriptors[1]);
    return child_status(pid) || written != length ? -1 : 0;
}

static int reply(struct lyd_node *output, const char *status, const char *id, const char *error)
{
    if (lyd_new_term(output, NULL, "status", status, LYD_NEW_VAL_OUTPUT, NULL) != LY_SUCCESS) return SR_ERR_CALLBACK_FAILED;
    if (id && lyd_new_term(output, NULL, "request-id", id, LYD_NEW_VAL_OUTPUT, NULL) != LY_SUCCESS) return SR_ERR_CALLBACK_FAILED;
    if (error && lyd_new_term(output, NULL, "error", error, LYD_NEW_VAL_OUTPUT, NULL) != LY_SUCCESS) return SR_ERR_CALLBACK_FAILED;
    if (!strcmp(status, "success") && lyd_new_term(output, NULL, "phase", "accepted", LYD_NEW_VAL_OUTPUT, NULL) != LY_SUCCESS) return SR_ERR_CALLBACK_FAILED;
    return SR_ERR_OK;
}

static int power(sr_session_ctx_t *session, uint32_t sub_id, const char *xpath,
        const struct lyd_node *input, sr_event_t event, uint32_t request_id,
        struct lyd_node *output, void *private_data)
{
    (void)session; (void)sub_id; (void)xpath; (void)request_id;
    if (event == SR_EV_ABORT) return SR_ERR_OK;
    const char *action = private_data;
    const char *id = lyd_get_value(lyd_child(input));
    if (!id || !id[0] || strlen(id) > 64 || strspn(id, "abcdefghijklmnopqrstuvwxyz0123456789-") != strlen(id))
        return reply(output, "invalid", NULL, "Invalid request ID");
    int lock = open("/var/lib/folio/system/power.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (lock < 0 || flock(lock, LOCK_EX | LOCK_NB)) {
        if (lock >= 0) close(lock);
        return reply(output, "conflict", id, "Power request state is busy");
    }
    char path[256], unit[128];
    snprintf(path, sizeof(path), "/var/lib/folio/system/%s.json", id);
    snprintf(unit, sizeof(unit), "folio-power-%s", id);
    int result;
    if (!access(path, F_OK)) {
        json_error_t error;
        json_t *record = json_load_file(path, JSON_REJECT_DUPLICATES, &error);
        const char *old_action = record ? json_string_value(json_object_get(record, "action")) : NULL;
        const char *old_id = record ? json_string_value(json_object_get(record, "id")) : NULL;
        const char *phase = record ? json_string_value(json_object_get(record, "phase")) : NULL;
        if (!old_action || !phase || !old_id || strcmp(old_id, id)) result = reply(output, "failure", id, "Invalid power journal; offline recovery is required");
        else if (strcmp(old_action, action)) result = reply(output, "conflict", id, "Request ID is bound to a different power action");
        else if (strcmp(phase, "accepted")) result = reply(output, "unavailable", id, "Prior submission is indeterminate; observe the guest before retrying");
        else result = reply(output, "success", id, NULL);
        json_decref(record);
    } else if (write_record(path, action, id, "prepared")) {
        result = reply(output, "failure", id, "Could not persist power request");
    } else {
        pid_t pid = fork();
        if (!pid) {
            execl(TIMEOUT, "timeout", "--kill-after=1", "5", SYSTEMD_RUN, "--system", "--quiet", "--collect",
                "--unit", unit, "--on-active=5", SYSTEMCTL, "--no-wall", action, (char *)NULL);
            _exit(126);
        }
        if (child_status(pid) || write_record(path, action, id, "accepted"))
            result = reply(output, "failure", id, "Power scheduling needs observation; submission may already be accepted");
        else result = reply(output, "success", id, NULL);
    }
    close(lock);
    return result;
}

int main(void)
{
    if (geteuid()) { fprintf(stderr, "The system power subscriber requires root provisioning\n"); return 1; }
    int repository_lock = open("/var/lib/folio/repository.lock", O_RDWR | O_NOFOLLOW | O_CLOEXEC);
    if (repository_lock < 0 || flock(repository_lock, LOCK_SH | LOCK_NB)) {
        fprintf(stderr, "Repository is unavailable or under offline maintenance\n"); return 3;
    }
    setenv("SYSREPO_REPOSITORY_PATH", "/var/lib/folio/sysrepo", 1);
    setenv("SYSREPO_SHM_DIR", "/run/folio/sysrepo", 1);
    setenv("SYSREPO_SHM_PREFIX", "folio_system", 1);
    unsetenv("SYSREPO_PLUGINS_PATH");
    signal(SIGPIPE, SIG_IGN);
    sr_conn_ctx_t *connection = NULL;
    sr_session_ctx_t *session = NULL;
    sr_subscription_ctx_t *subscription = NULL;
    int code = sr_connect(0, &connection);
    char *owner = NULL, *group = NULL;
    mode_t permissions = 0;
    if (!code) code = sr_get_module_ds_access(connection, "folio-system", SR_DS_STARTUP, &owner, &group, &permissions);
    if (!code && (!owner || strcmp(owner,"root") || !group || strcmp(group,"folio-operators") || permissions != 0660)) code = SR_ERR_UNAUTHORIZED;
    free(owner); free(group);
    if (!code) code = sr_session_start(connection, SR_DS_RUNNING, &session);
    if (!code) code = sr_rpc_subscribe_tree(session, "/folio-system:reboot", power, "reboot", 0, 0, &subscription);
    if (!code) code = sr_rpc_subscribe_tree(session, "/folio-system:poweroff", power, "poweroff", 0, 0, &subscription);
    if (!code) {
        signal(SIGINT, stop); signal(SIGTERM, stop);
        fprintf(stderr, "Folio system power subscriptions ready\n");
        while (!stopping) sleep(1);
    } else fprintf(stderr, "Unable to subscribe to power requests: %s\n", sr_strerror(code));
    sr_unsubscribe(subscription); sr_session_stop(session); sr_disconnect(connection);
    return code ? 1 : 0;
}
