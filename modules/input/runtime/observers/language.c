/* Adapted from Sylphy's event-driven Fcitx observer at
 * 9cba023d90c4485b33a91e2d12724b6920580580. */
#define _GNU_SOURCE
#include <gio/gio.h>
#include <glib-unix.h>
#include <jansson.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/prctl.h>
#include <unistd.h>

static GDBusConnection *bus;
static char *item, *last;
static guint item_signal;
static const char *watcher = "org.kde.StatusNotifierWatcher";
static const char *item_interface = "org.kde.StatusNotifierItem";
static void emit(const char *language)
{
    if (!g_strcmp0(last, language)) return;
    g_free(last); last = g_strdup(language);
    const char *style = !strcmp(language, "中") ? "chinese" : !strcmp(language, "EN") ? "english" : "unavailable";
    json_t *record = json_pack("{s:s,s:s,s:s}", "text", !strcmp(style, "unavailable") ? "?" : language,
        "class", style, "tooltip", !strcmp(style, "chinese") ? "Chinese input" : !strcmp(style, "english") ? "English input" : "Input language unavailable");
    json_dumpf(record, stdout, JSON_COMPACT); putchar('\n'); fflush(stdout); json_decref(record);
}
static GVariant *call(const char *name, const char *path, const char *interface, const char *method, GVariant *arguments)
{
    return g_dbus_connection_call_sync(bus, name, path, interface, method, arguments, NULL,
        G_DBUS_CALL_FLAGS_NO_AUTO_START, 1000, NULL, NULL);
}
static char *property(const char *name, const char *key)
{
    GVariant *reply = call(name, "/StatusNotifierItem", "org.freedesktop.DBus.Properties", "Get",
        g_variant_new("(ss)", item_interface, key));
    if (!reply) return g_strdup("");
    GVariant *value;
    g_variant_get(reply, "(v)", &value);
    char *text = g_strdup(g_variant_is_of_type(value, G_VARIANT_TYPE_STRING) ? g_variant_get_string(value, NULL) : "");
    g_variant_unref(value); g_variant_unref(reply);
    return text;
}
static void refresh(void)
{
    if (item) {
        g_autofree char *icon = property(item, "IconName");
        if (strstr(icon, "rime_latin") || strstr(icon, "input-keyboard")) { emit("EN"); return; }
        if (!strcmp(icon, "fcitx-rime") || !strcmp(icon, "fcitx_rime")) { emit("中"); return; }
    }
    GVariant *reply = call("org.fcitx.Fcitx5", "/controller", "org.fcitx.Fcitx.Controller1", "CurrentInputMethod", NULL);
    if (!reply) { emit("unavailable"); return; }
    const char *method; g_variant_get(reply, "(&s)", &method);
    emit(!strcmp(method, "keyboard-us") ? "EN" : "unavailable");
    g_variant_unref(reply);
}
static void changed(GDBusConnection *connection, const gchar *sender, const gchar *path,
        const gchar *interface, const gchar *signal, GVariant *arguments, gpointer data)
{
    (void)connection; (void)sender; (void)path; (void)interface; (void)signal; (void)arguments; (void)data;
    refresh();
}
static gboolean register_item(gpointer data)
{
    char *name = data;
    g_autofree char *id = property(name, "Id");
    if (!strcmp(id, "Fcitx")) {
        if (item_signal) g_dbus_connection_signal_unsubscribe(bus, item_signal);
        g_free(item); item = g_strdup(name);
        item_signal = g_dbus_connection_signal_subscribe(bus, name, item_interface, "NewIcon",
            "/StatusNotifierItem", NULL, G_DBUS_SIGNAL_FLAGS_NONE, changed, NULL, NULL);
        refresh();
    }
    g_free(name); return G_SOURCE_REMOVE;
}
static void method_call(GDBusConnection *connection, const gchar *sender, const gchar *path,
        const gchar *interface, const gchar *method, GVariant *args, GDBusMethodInvocation *invocation, gpointer data)
{
    (void)connection; (void)path; (void)interface; (void)data;
    if (!strcmp(method, "RegisterStatusNotifierItem")) {
        const char *name; g_variant_get(args, "(&s)", &name);
        /* Reply before querying the registering process to avoid a D-Bus deadlock. */
        g_idle_add(register_item, g_strdup(*name == '/' ? sender : name));
    }
    g_dbus_method_invocation_return_value(invocation, NULL);
}
static GVariant *get_property(GDBusConnection *connection, const gchar *sender, const gchar *path,
        const gchar *interface, const gchar *key, GError **error, gpointer data)
{
    (void)connection; (void)sender; (void)path; (void)interface; (void)error; (void)data;
    if (!strcmp(key, "ProtocolVersion")) return g_variant_new_int32(0);
    if (!strcmp(key, "IsStatusNotifierHostRegistered")) return g_variant_new_boolean(TRUE);
    return g_variant_new_strv(NULL, 0);
}
static void registered(GDBusConnection *connection, const gchar *sender, const gchar *path,
        const gchar *interface, const gchar *signal, GVariant *args, gpointer data)
{
    (void)connection; (void)sender; (void)path; (void)interface; (void)signal; (void)data;
    const char *name; g_variant_get(args, "(&s)", &name);
    g_idle_add(register_item, g_strdup(name));
}
static void owner_changed(GDBusConnection *connection, const gchar *sender, const gchar *path,
        const gchar *interface, const gchar *signal, GVariant *args, gpointer data)
{
    (void)connection; (void)sender; (void)path; (void)interface; (void)signal; (void)data;
    const char *name, *old_owner, *new_owner;
    g_variant_get(args, "(&s&s&s)", &name, &old_owner, &new_owner);
    if (!g_strcmp0(item, name) && !*new_owner) { g_clear_pointer(&item, g_free); refresh(); }
    if (!strcmp(name, "org.fcitx.Fcitx5")) refresh();
}
static gboolean quit(gpointer data) { g_main_loop_quit(data); return G_SOURCE_REMOVE; }
int main(void)
{
    pid_t parent = getppid();
    if (prctl(PR_SET_PDEATHSIG, SIGTERM)) return 3;
    if (getppid() != parent) return 0;
    bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, NULL);
    if (!bus) { emit("unavailable"); return 3; }
    const char *xml = "<node><interface name='org.kde.StatusNotifierWatcher'>"
        "<method name='RegisterStatusNotifierItem'><arg type='s' direction='in'/></method>"
        "<method name='RegisterStatusNotifierHost'><arg type='s' direction='in'/></method>"
        "<property name='RegisteredStatusNotifierItems' type='as' access='read'/>"
        "<property name='IsStatusNotifierHostRegistered' type='b' access='read'/>"
        "<property name='ProtocolVersion' type='i' access='read'/>"
        "<signal name='StatusNotifierItemRegistered'><arg type='s'/></signal>"
        "<signal name='StatusNotifierItemUnregistered'><arg type='s'/></signal>"
        "<signal name='StatusNotifierHostRegistered'/></interface></node>";
    GDBusNodeInfo *info = g_dbus_node_info_new_for_xml(xml, NULL);
    const GDBusInterfaceVTable table = {.method_call = method_call, .get_property = get_property};
    g_dbus_connection_register_object(bus, "/StatusNotifierWatcher", info->interfaces[0], &table, NULL, NULL, NULL);
    g_bus_own_name_on_connection(bus, watcher, G_BUS_NAME_OWNER_FLAGS_NONE, NULL, NULL, NULL, NULL);
    g_dbus_connection_signal_subscribe(bus, watcher, watcher, "StatusNotifierItemRegistered",
        "/StatusNotifierWatcher", NULL, G_DBUS_SIGNAL_FLAGS_NONE, registered, NULL, NULL);
    g_dbus_connection_signal_subscribe(bus, "org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged",
        "/org/freedesktop/DBus", NULL, G_DBUS_SIGNAL_FLAGS_NONE, owner_changed, NULL, NULL);
    GMainLoop *loop = g_main_loop_new(NULL, FALSE);
    g_unix_signal_add(SIGTERM, quit, loop);
    refresh(); g_main_loop_run(loop);
    g_main_loop_unref(loop); g_dbus_node_info_unref(info); g_object_unref(bus);
    g_free(item); g_free(last); return 0;
}
