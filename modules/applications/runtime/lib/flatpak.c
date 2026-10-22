#include <flatpak.h>
#include <jansson.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

struct context {
    FlatpakInstallation *installation;
    const char *ref, *commit;
    json_t *expected, *operations;
    int mismatch;
};
static char *installed_commit(FlatpakInstallation *installation, const char *name)
{
    g_autoptr(GError) error = NULL;
    g_autoptr(FlatpakRef) ref = flatpak_ref_parse(name, &error);
    if (!ref) return NULL;
    g_autoptr(FlatpakInstalledRef) installed = flatpak_installation_get_installed_ref(installation,
        flatpak_ref_get_kind(ref), flatpak_ref_get_name(ref), flatpak_ref_get_arch(ref),
        flatpak_ref_get_branch(ref), NULL, &error);
    return installed ? g_strdup(flatpak_ref_get_commit(FLATPAK_REF(installed))) : NULL;
}
static int planned(json_t *array, const char *ref, const char *commit)
{
    size_t index; json_t *entry;
    json_array_foreach(array, index, entry) {
        const char *name = json_string_value(json_object_get(entry, "ref"));
        const char *value = json_string_value(json_object_get(entry, "commit"));
        if (name && value && !strcmp(name, ref) && !strcmp(value, commit)) return 1;
    }
    return 0;
}
static gboolean ready(FlatpakTransaction *transaction, gpointer data)
{
    struct context *context = data;
    GList *operations = flatpak_transaction_get_operations(transaction);
    context->operations = json_array();
    for (GList *item = operations; item; item = item->next) {
        FlatpakTransactionOperation *operation = item->data;
        const char *ref = flatpak_transaction_operation_get_ref(operation);
        const char *commit = flatpak_transaction_operation_get_commit(operation);
        const char *remote = flatpak_transaction_operation_get_remote(operation);
        if (flatpak_transaction_operation_get_is_skipped(operation)) continue;
        if (!ref || !commit || !remote || strcmp(remote, "flathub") ||
                flatpak_transaction_operation_get_operation_type(operation) == FLATPAK_TRANSACTION_OPERATION_UNINSTALL ||
                (!strncmp(ref, "app/", 4) && strcmp(ref, context->ref)) ||
                (!strcmp(ref, context->ref) && strcmp(commit, context->commit))) goto mismatch;
        json_t *entry = json_pack("{s:s,s:s,s:s}", "ref", ref, "commit", commit, "remote", remote);
        json_t *subpaths = json_array();
        const char * const *paths = flatpak_transaction_operation_get_subpaths(operation);
        for (unsigned i = 0; paths && paths[i]; ++i) json_array_append_new(subpaths, json_string(paths[i]));
        json_object_set_new(entry, "subpaths", subpaths);
        json_array_append_new(context->operations, entry);
        if (context->expected) {
            if (!planned(context->expected, ref, commit)) goto mismatch;
            size_t index; json_t *expected;
            json_array_foreach(context->expected, index, expected) {
                if (!strcmp(json_string_value(json_object_get(expected, "ref")) ?: "", ref) &&
                        !json_equal(json_object_get(expected, "subpaths"), subpaths)) goto mismatch;
            }
        }
    }
    if (context->expected) {
        size_t index; json_t *entry;
        json_array_foreach(context->expected, index, entry) {
            const char *ref = json_string_value(json_object_get(entry, "ref"));
            const char *commit = json_string_value(json_object_get(entry, "commit"));
            if (!ref || !commit) goto mismatch;
            if (!planned(context->operations, ref, commit)) {
                g_autofree char *actual = installed_commit(context->installation, ref);
                if (!actual || strcmp(actual, commit)) goto mismatch;
            }
        }
    }
    return TRUE;
mismatch:
    context->mismatch = 1;
    return FALSE;
}
static int choose_remote(FlatpakTransaction *transaction, const char *ref, const char *runtime,
        const char * const *remotes, gpointer data)
{
    (void)transaction; (void)ref; (void)runtime; (void)data;
    for (int index = 0; remotes && remotes[index]; ++index)
        if (!strcmp(remotes[index], "flathub")) return index;
    return -1;
}
static gboolean add_remote(FlatpakTransaction *transaction, FlatpakTransactionRemoteReason reason,
        const char *from, const char *name, const char *url, gpointer data)
{
    (void)transaction; (void)reason; (void)from; (void)name; (void)url; (void)data;
    return FALSE;
}
int main(int argc, char **argv)
{
    if (geteuid() != 0 && argc == 2 && !strcmp(argv[1], "verify-remote")) {
        g_autoptr(GError) error = NULL;
        g_autoptr(FlatpakInstallation) installation = flatpak_installation_new_user(NULL, &error);
        if (!installation) return 3;
        g_autoptr(FlatpakRemote) remote = flatpak_installation_get_remote_by_name(installation, "flathub", NULL, &error);
        if (!remote) return 3;
        g_autofree char *url = flatpak_remote_get_url(remote);
        return !flatpak_remote_get_gpg_verify(remote) || flatpak_remote_get_disabled(remote) || !url ||
            (strcmp(url, "https://dl.flathub.org/repo/") && strcmp(url, "https://flathub.org/repo/")) ? 4 : 0;
    }
    if (geteuid() == 0 || (argc != 5 && argc != 6)) return 2;
    int deploy = !strcmp(argv[1], "deploy");
    if ((!deploy && strcmp(argv[1], "prepare")) || (deploy && argc != 6) || (!deploy && argc != 5) ||
            strlen(argv[3]) != 64 || strspn(argv[3], "0123456789abcdef") != 64 ||
            (strcmp(argv[4], "offline") && strcmp(argv[4], "online"))) return 2;
    g_autoptr(GError) error = NULL;
    g_autoptr(FlatpakRef) requested = flatpak_ref_parse(argv[2], &error);
    if (!requested || flatpak_ref_get_kind(requested) != FLATPAK_REF_KIND_APP ||
            strcmp(flatpak_ref_get_arch(requested), "x86_64")) return 2;
    g_autoptr(FlatpakInstallation) installation = flatpak_installation_new_user(NULL, &error);
    g_autoptr(FlatpakTransaction) transaction = NULL;
    g_autoptr(FlatpakRemote) remote = NULL;
    g_autoptr(FlatpakRef) ref = NULL;
    g_autofree char *current = NULL;
    g_autofree char *url = NULL;
    struct context context = {.installation = installation, .ref = argv[2], .commit = argv[3]};
    int code = 1;
    if (!installation) goto done;
    remote = flatpak_installation_get_remote_by_name(installation, "flathub", NULL, &error);
    if (!remote) goto done;
    url = flatpak_remote_get_url(remote);
    if (!flatpak_remote_get_gpg_verify(remote) || flatpak_remote_get_disabled(remote) || !url ||
            (strcmp(url, "https://dl.flathub.org/repo/") && strcmp(url, "https://flathub.org/repo/"))) { code = 4; goto done; }
    transaction = flatpak_transaction_new_for_installation(installation, NULL, &error);
    if (!transaction) goto done;
    flatpak_transaction_set_no_interaction(transaction, TRUE);
    flatpak_transaction_set_no_deploy(transaction, !deploy);
    flatpak_transaction_set_no_pull(transaction, deploy || !strcmp(argv[4], "offline"));
    flatpak_transaction_set_disable_prune(transaction, TRUE);
    flatpak_transaction_set_include_unused_uninstall_ops(transaction, FALSE);
    flatpak_transaction_set_auto_install_sdk(transaction, FALSE);
    flatpak_transaction_set_auto_install_debug(transaction, FALSE);
    if (deploy) {
        json_error_t json_error;
        json_t *plan = json_load_file(argv[5], JSON_REJECT_DUPLICATES, &json_error);
        context.expected = plan ? json_incref(json_object_get(plan, "operations")) : NULL;
        json_decref(plan);
        if (!json_is_array(context.expected)) { code = 2; goto done; }
        /* Related refs must be explicit during local-only deployment. Flatpak
         * intentionally omits automatic related-ref resolution with no-pull. */
        flatpak_transaction_set_disable_dependencies(transaction, TRUE);
        flatpak_transaction_set_disable_related(transaction, TRUE);
        size_t index; json_t *entry;
        json_array_foreach(context.expected, index, entry) {
            const char *name = json_string_value(json_object_get(entry, "ref"));
            const char *commit = json_string_value(json_object_get(entry, "commit"));
            if (!name || !commit || strlen(commit) != 64 || strspn(commit, "0123456789abcdef") != 64) { code = 2; goto done; }
            if (!strcmp(name, argv[2])) continue;
            if (strncmp(name, "runtime/", 8)) { code = 4; goto done; }
            json_t *paths = json_object_get(entry, "subpaths");
            if (!json_is_array(paths)) { code = 2; goto done; }
            const char **subpaths = g_new0(const char *, json_array_size(paths) + 1);
            size_t offset; json_t *value;
            json_array_foreach(paths, offset, value) {
                subpaths[offset] = json_string_value(value);
                if (!subpaths[offset]) { g_free(subpaths); code = 2; goto done; }
            }
            g_autofree char *installed = installed_commit(installation, name);
            gboolean added;
            if (installed) added = !strcmp(installed, commit) || flatpak_transaction_add_update(transaction, name, subpaths, commit, &error);
            else added = flatpak_transaction_add_install(transaction, "flathub", name, subpaths, &error);
            g_free(subpaths);
            if (!added) goto done;
        }
    }
    g_signal_connect(transaction, "ready", G_CALLBACK(ready), &context);
    g_signal_connect(transaction, "choose-remote-for-ref", G_CALLBACK(choose_remote), NULL);
    g_signal_connect(transaction, "add-new-remote", G_CALLBACK(add_remote), NULL);
    ref = flatpak_ref_parse(argv[2], &error);
    if (!ref) goto done;
    current = installed_commit(installation, argv[2]);
    gboolean added = current ? flatpak_transaction_add_update(transaction, argv[2], NULL, argv[3], &error) :
        flatpak_transaction_add_install(transaction, "flathub", argv[2], NULL, &error);
    if (!added || !flatpak_transaction_run(transaction, NULL, &error)) goto done;
    code = 0;
done:
    if (context.mismatch) code = 4;
    json_t *data = json_pack("{s:s,s:s}", "ref", argv[2], "commit", argv[3]);
    json_object_set(data, "operations", context.operations ?: json_null());
    json_t *reply = json_pack("{s:s,s:o}", "status", code ? (code == 4 ? "conflict" : "failure") : "success", "data", data);
    if (code) json_object_set_new(reply, "error", json_string(context.mismatch ?
        "Resolved refs, commits or locale subpaths differ from the prepared transaction" : error ? error->message : "Flatpak transaction precondition failed"));
    json_dumpf(reply, stdout, JSON_SORT_KEYS | JSON_COMPACT); putchar('\n');
    json_decref(reply); json_decref(context.expected); json_decref(context.operations);
    return code;
}
