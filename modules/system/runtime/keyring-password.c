#define _DEFAULT_SOURCE
#include <gio/gio.h>
#include <stdio.h>
#include <string.h>
#include <sys/resource.h>
#include <unistd.h>

#define SERVICE "org.gnome.keyring"
#define ROOT "/org/freedesktop/secrets"
#define INTERNAL "org.gnome.keyring.InternalUnsupportedGuiltRiddenInterface"

static void erase(char *value) {
    if (value) {
        volatile char *p = value;
        size_t length = strlen(value);
        while (length--) *p++ = 0;
    }
}

static char *password(const char *prompt) {
    char *input = getpass(prompt);
    if (!input) return NULL;
    char *copy = g_strdup(input);
    erase(input);
    return copy;
}

static GVariant *secret(const char *session, const char *value) {
    return g_variant_new("(o@ay@ays)", session,
        g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE, NULL, 0, 1),
        g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE, value, strlen(value), 1),
        "text/plain; charset=utf8");
}

int main(int argc, char **argv) {
    int result = 1;
    char *old = NULL, *next = NULL, *confirmation = NULL;
    GError *error = NULL;
    GDBusConnection *bus = NULL;
    GVariant *reply = NULL;
    char *collection = NULL, *session = NULL;
    struct rlimit no_core = {0, 0};
    gboolean check = argc == 2 && strcmp(argv[1], "--check") == 0;
    if (argc != 1 && !check) {
        fputs("Usage: folio-keyring-password [--check]\n", stderr);
        return 2;
    }
    if (setrlimit(RLIMIT_CORE, &no_core) != 0) {
        fputs("Cannot disable core dumps; refusing to read passwords.\n", stderr);
        return 1;
    }
    bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
    if (!bus) goto done;
    reply = g_dbus_connection_call_sync(bus, SERVICE, ROOT,
        "org.freedesktop.Secret.Service", "ReadAlias", g_variant_new("(s)", "login"),
        G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, 30000, NULL, &error);
    if (!reply) goto done;
    g_variant_get(reply, "(o)", &collection);
    g_clear_pointer(&reply, g_variant_unref);
    if (strcmp(collection, "/") == 0) {
        fputs("The login keyring does not exist; refusing to create a replacement.\n", stderr);
        goto done;
    }
    if (check) {
        puts("Existing login keyring is available.");
        result = 0;
        goto done;
    }
    if (!isatty(STDIN_FILENO) || !isatty(STDERR_FILENO)) {
        fputs("Use an interactive terminal; password arguments and pipes are not supported.\n", stderr);
        goto done;
    }
    reply = g_dbus_connection_call_sync(bus, SERVICE, ROOT,
        "org.freedesktop.Secret.Service", "OpenSession",
        g_variant_new("(sv)", "plain", g_variant_new_string("")),
        G_VARIANT_TYPE("(vo)"), G_DBUS_CALL_FLAGS_NONE, 30000, NULL, &error);
    if (!reply) goto done;
    GVariant *session_path = g_variant_get_child_value(reply, 1);
    session = g_variant_dup_string(session_path, NULL);
    g_variant_unref(session_path);
    g_clear_pointer(&reply, g_variant_unref);
    old = password("Previous keyring password: ");
    next = password("Current folio login password (new keyring password): ");
    confirmation = password("Repeat new keyring password: ");
    if (!old || !next || !confirmation || !*next || strcmp(next, confirmation) != 0) {
        fputs("Passwords are missing, empty or do not match; nothing changed.\n", stderr);
        goto done;
    }
    reply = g_dbus_connection_call_sync(bus, SERVICE, ROOT, INTERNAL,
        "ChangeWithMasterPassword",
        g_variant_new("(o@(oayays)@(oayays))", collection,
            secret(session, old), secret(session, next)),
        G_VARIANT_TYPE_UNIT, G_DBUS_CALL_FLAGS_NONE, 30000, NULL, &error);
    if (!reply) goto done;
    puts("Login keyring password changed successfully. Existing credentials were retained.");
    result = 0;
done:
    if (error) {
        /* Do not print server messages that could contain application data. */
        fputs("Keyring request failed. Check the previous password and running GNOME Keyring service.\n", stderr);
        g_error_free(error);
    }
    erase(old); erase(next); erase(confirmation);
    g_free(old); g_free(next); g_free(confirmation);
    g_clear_pointer(&reply, g_variant_unref);
    if (bus && session) {
        GVariant *closed = g_dbus_connection_call_sync(bus, SERVICE, session,
            "org.freedesktop.Secret.Session", "Close", NULL, NULL,
            G_DBUS_CALL_FLAGS_NONE, 3000, NULL, NULL);
        if (closed) g_variant_unref(closed);
    }
    g_free(session); g_free(collection);
    g_clear_object(&bus);
    return result;
}
