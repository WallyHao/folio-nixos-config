"""Unprivileged native NetworkManager client. Requests arrive only on stdin."""

import json
import os
import pwd
import re
import sys
import time
import uuid

import gi

gi.require_version("NM", "1.0")
from gi.repository import NM, Gio, GLib


class Unavailable(Exception):
    pass


def wait_until(predicate, timeout=25):
    deadline = time.monotonic() + timeout
    context = GLib.MainContext.default()
    while time.monotonic() < deadline:
        while context.pending():
            context.iteration(False)
        if predicate():
            return
        time.sleep(0.05)
    raise Unavailable("Network operation timed out")


def asynchronous(start, finish, scan_diagnostic=False, timeout=25):
    result = []
    cancel = Gio.Cancellable()

    def done(source, response, *unused):
        try:
            result.append((True, finish(response)))
        except GLib.Error as error:
            # Native diagnostics must never accidentally echo credential fields.
            result.append(
                (
                    False,
                    error.message
                    if scan_diagnostic
                    else f"{error.domain}:{error.code}",
                )
            )

    start(cancel, done)
    try:
        wait_until(lambda: bool(result), timeout)
    finally:
        cancel.cancel()
    if not result[0][0]:
        raise Unavailable("NetworkManager rejected the operation: " + result[0][1])
    return result[0][1]


def ssid_bytes(setting):
    value = setting.get_ssid()
    return bytes(value.get_data()) if value else b""


def security(ap):
    flags = int(ap.get_wpa_flags()) | int(ap.get_rsn_flags())
    values = getattr(NM, "80211ApSecurityFlags")
    if flags & int(values.KEY_MGMT_802_1X):
        return "Enterprise"
    if flags & int(values.KEY_MGMT_SAE):
        return "WPA3"
    if flags & int(values.KEY_MGMT_PSK):
        return "WPA Personal"
    return "Unsupported" if int(ap.get_flags()) & 1 else "Open"


class Wifi:
    def __init__(self):
        self.client = NM.Client.new(None)
        if not self.client.get_nm_running():
            raise Unavailable("NetworkManager is unavailable")

    def adapters(self):
        return [d for d in self.client.get_devices() if isinstance(d, NM.DeviceWifi)]

    def device(self, interface):
        if not isinstance(interface, str) or not re.fullmatch(
            r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,14}", interface
        ):
            raise ValueError("Select a Wi-Fi adapter")
        device = self.client.get_device_by_iface(interface)
        if not isinstance(device, NM.DeviceWifi):
            raise Unavailable("The selected Wi-Fi adapter is no longer available")
        return device

    def snapshot(self):
        adapters = []
        for device in self.adapters():
            profiles = []
            for connection in device.get_available_connections():
                wireless = connection.get_setting_wireless()
                if wireless:
                    profiles.append(
                        {
                            "uuid": connection.get_uuid(),
                            "ssid": ssid_bytes(wireless).decode("utf-8", "replace"),
                        }
                    )
            active = device.get_active_access_point()
            ip = device.get_ip4_config()
            networks = []
            for ap in device.get_access_points():
                name = ssid_bytes(ap).decode("utf-8", "replace")
                networks.append(
                    {
                        "path": ap.get_path(),
                        "ssid": name,
                        "signal": ap.get_strength(),
                        "security": security(ap),
                        "active": bool(active and active.get_path() == ap.get_path()),
                        "profiles": [p["uuid"] for p in profiles if p["ssid"] == name],
                    }
                )
            adapters.append(
                {
                    "interface": device.get_iface(),
                    "state": device.get_state().value_nick,
                    "addresses": [a.get_address() for a in ip.get_addresses()]
                    if ip
                    else [],
                    "networks": sorted(
                        networks, key=lambda ap: (-ap["signal"], ap["path"])
                    ),
                    "profiles": profiles,
                }
            )
        return {
            "enabled": self.client.wireless_get_enabled(),
            "hardwareEnabled": self.client.wireless_hardware_get_enabled(),
            "adapters": adapters,
        }

    def execute(self, request):
        action = request.get("action", "status")
        if action == "status":
            return self.snapshot()
        if action == "radio":
            enabled = request.get("enabled")
            if not isinstance(enabled, bool):
                raise ValueError("Radio state must be a boolean")
            asynchronous(
                lambda c, cb: self.client.dbus_set_property(
                    "/org/freedesktop/NetworkManager",
                    "org.freedesktop.NetworkManager",
                    "WirelessEnabled",
                    GLib.Variant("b", enabled),
                    10000,
                    c,
                    cb,
                ),
                self.client.dbus_set_property_finish,
            )
            wait_until(lambda: self.client.wireless_get_enabled() == enabled, 5)
            return self.snapshot()
        device = self.device(request.get("interface"))
        if action == "scan":
            previous = device.get_last_scan()
            asynchronous(
                lambda c, cb: device.request_scan_async(c, cb),
                device.request_scan_finish,
                scan_diagnostic=True,
            )
            wait_until(lambda: device.get_last_scan() != previous, 25)
        elif action == "disconnect":
            asynchronous(
                lambda c, cb: device.disconnect_async(c, cb), device.disconnect_finish
            )
            wait_until(lambda: device.get_state() == NM.DeviceState.DISCONNECTED, 5)
        elif action == "forget":
            connection = self.client.get_connection_by_uuid(request.get("uuid", ""))
            available = {p.get_uuid() for p in device.get_available_connections()}
            if (
                connection is None
                or connection.get_uuid() not in available
                or not connection.get_setting_wireless()
            ):
                raise Unavailable("The selected saved wireless profile is unavailable")
            asynchronous(
                lambda c, cb: connection.delete_async(c, cb), connection.delete_finish
            )
        elif action == "connect":
            self.connect(device, request)
        else:
            raise ValueError("Unknown wireless operation")
        return self.snapshot()

    def connect(self, device, request):
        profile = request.get("uuid")
        password = request.pop("password", "")
        if not isinstance(password, str):
            raise TypeError("Invalid network password")
        ap = next(
            (
                a
                for a in device.get_access_points()
                if a.get_path() == request.get("ap")
            ),
            None,
        )
        if profile:
            connection = self.client.get_connection_by_uuid(profile)
            if connection is None or profile not in {
                p.get_uuid() for p in device.get_available_connections()
            }:
                raise Unavailable("Saved wireless profile is unavailable")
            if ap and ssid_bytes(connection.get_setting_wireless()) != ssid_bytes(ap):
                raise ValueError("Saved profile does not match the selected network")
            if password:
                secure = connection.get_setting_wireless_security()
                if secure is None or secure.props.key_mgmt not in ("wpa-psk", "sae"):
                    raise Unavailable(
                        "Saved profile does not support personal WPA credentials"
                    )
                secure.props.psk = password
                asynchronous(
                    lambda c, cb: connection.commit_changes_async(True, c, cb),
                    connection.commit_changes_finish,
                )
            active = asynchronous(
                lambda c, cb: self.client.activate_connection_async(
                    connection, device, ap.get_path() if ap else None, c, cb
                ),
                self.client.activate_connection_finish,
            )
        else:
            hidden = request.get("hidden", False)
            if type(hidden) is not bool:
                raise ValueError("Hidden network state must be a boolean")
            if hidden:
                name = request.get("ssid", "")
                if (
                    not isinstance(name, str)
                    or not 1 <= len(name.encode("utf-8")) <= 32
                ):
                    raise ValueError("SSID must contain 1 through 32 UTF-8 bytes")
                network_ssid = name.encode("utf-8")
                kind = request.get("security")
            elif ap:
                network_ssid = ssid_bytes(ap)
                kind = security(ap)
            else:
                raise Unavailable(
                    "The selected access point disappeared; refresh the list"
                )
            if kind not in ("Open", "WPA Personal", "WPA3"):
                raise Unavailable("Only open and personal WPA networks are supported")
            connection = NM.SimpleConnection.new()
            identity = NM.SettingConnection.new()
            identity.props.id = network_ssid.decode("utf-8", "replace")
            identity.props.uuid = str(uuid.uuid4())
            identity.props.type = "802-11-wireless"
            identity.add_permission("user", pwd.getpwuid(os.getuid()).pw_name, None)
            connection.add_setting(identity)
            wireless = NM.SettingWireless.new()
            wireless.props.ssid = GLib.Bytes.new(network_ssid)
            wireless.props.mode = "infrastructure"
            wireless.props.hidden = hidden
            connection.add_setting(wireless)
            if kind != "Open":
                if not password:
                    raise ValueError("A network password is required")
                if kind == "WPA Personal" and not (
                    8 <= len(password.encode("utf-8")) <= 63
                    or re.fullmatch(r"[0-9a-fA-F]{64}", password)
                ):
                    raise ValueError(
                        "WPA password must be 8–63 bytes or 64 hexadecimal digits"
                    )
                secure = NM.SettingWirelessSecurity.new()
                secure.props.key_mgmt = "sae" if kind == "WPA3" else "wpa-psk"
                secure.props.psk = password
                # NM saves the credential with the owner-restricted connection;
                # no secret is passed in argv, temporary files or Folio data.
                connection.add_setting(secure)
                del password
            active = asynchronous(
                lambda c, cb: self.client.add_and_activate_connection_async(
                    connection, device, ap.get_path() if ap else None, c, cb
                ),
                self.client.add_and_activate_connection_finish,
            )

        def finished():
            return active.get_state() in (
                NM.ActiveConnectionState.ACTIVATED,
                NM.ActiveConnectionState.DEACTIVATED,
            )

        try:
            wait_until(finished, 30)
        except Unavailable:
            # An expired UI request must not leave NM retrying a connection in
            # the background. Preserve the saved profile for an explicit retry.
            if active.get_state() != NM.ActiveConnectionState.DEACTIVATED:
                asynchronous(
                    lambda c, cb: self.client.deactivate_connection_async(
                        active, c, cb
                    ),
                    self.client.deactivate_connection_finish,
                    timeout=5,
                )
            raise
        if active.get_state() != NM.ActiveConnectionState.ACTIVATED:
            raise Unavailable(
                "Connection failed: " + device.get_state_reason().value_nick
            )


def main():
    try:
        if os.geteuid() == 0:
            raise Unavailable("Wi-Fi controls must run as the desktop user")
        request = json.loads(sys.stdin.buffer.read(65537))
        if not isinstance(request, dict):
            raise TypeError("Expected a request object")
        data = Wifi().execute(request)
        reply = {"status": "success", "data": data, "error": None}
        code = 0
    except (ValueError, TypeError, KeyError) as error:
        reply = {
            "status": "invalid",
            "data": None,
            "error": str(error)
            if isinstance(error, ValueError)
            and not isinstance(error, json.JSONDecodeError)
            else "Invalid wireless request",
        }
        code = 2
    except Exception as error:  # noqa: BLE001 -- never print credential-bearing locals.
        reply = {
            "status": "unavailable",
            "data": None,
            "error": str(error)
            if isinstance(error, Unavailable)
            else "NetworkManager is unavailable or denied this operation",
        }
        code = 3
    json.dump(reply, sys.stdout, ensure_ascii=True)
    sys.stdout.write("\n")
    return code


if __name__ == "__main__":
    sys.exit(main())
