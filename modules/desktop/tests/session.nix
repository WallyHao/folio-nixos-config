{ pkgs, inputs, source, bootstrap, prepareInput, modules, runtime, cli,
  legacySource ? null, cache ? null, plans ? null, drm ? true }:
let
  legacy = if legacySource == null then null else import (legacySource + "/modules/manager/src/outputs.nix") {
    inputs = inputs // { self.outPath = legacySource; };
  };
  oldBootstrap = if legacy == null then bootstrap else legacy.packages.x86_64-linux.manager-bootstrap;
  descriptor = pkgs.runCommand "folio-desktop-test-descriptor" { nativeBuildInputs = [ pkgs.jq ]; } ''
    jq '.origin="system-generation" | .capabilities += {"system-repository":true}' ${bootstrap}/system-descriptor.json >$out
  '';
  prepared = name: base: configuration: modelBootstrap: pkgs.runCommand name {
    nativeBuildInputs = [ prepareInput ];
  } ''
    mkdir $out
    cp -R ${base}/. $out/
    chmod -R u+w $out
    folio-prepare-input ${configuration} ${modelBootstrap} ${descriptor} >$out/folio-input.json
  '';
  oldSeed = prepared "folio-desktop-old-user" (if legacy == null then source else legacySource) "${oldBootstrap}/user.json" oldBootstrap;
  schemaSeed = prepared "folio-desktop-schema-upgrade" source "${oldBootstrap}/user.json" bootstrap;
  userSeed = prepared "folio-desktop-user" source "${bootstrap}/user.json" bootstrap;
  generation = seed: (import (seed + "/modules/manager/src/outputs.nix") {
    inputs = inputs // { self.outPath = seed; };
  }).homeConfigurations.folio.activationPackage;
  oldGeneration = generation oldSeed;
  schemaGeneration = generation schemaSeed;
  userGeneration = generation userSeed;
  testPython = pkgs.python3.withPackages (p: [ p.websocket-client p.pillow ]);
  softwareQemu = pkgs.symlinkJoin {
    name = "folio-capture-software-qemu";
    paths = [ pkgs.qemu_kvm ];
    postBuild = ''
      rm "$out/bin/qemu-system-x86_64"
      ln -s ${pkgs.writeShellScript "folio-capture-qemu" ''
        export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
        export SDL_VIDEODRIVER=x11 __GLX_VENDOR_LIBRARY_NAME=mesa
        export LIBGL_DRIVERS_PATH=${pkgs.mesa}/lib/dri
        export __EGL_VENDOR_LIBRARY_FILENAMES=${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json
        export LD_LIBRARY_PATH=${pkgs.mesa}/lib
        unset WAYLAND_DISPLAY
        ${builtins.replaceStrings
          [ "@coreutils@" "@xvfb@" "@qemu@" ]
          [ "${pkgs.coreutils}" "${pkgs.xorg.xorgserver}/bin/Xvfb" "${pkgs.qemu_kvm}/bin/qemu-system-x86_64" ]
          (builtins.readFile ./qemu-software.sh)}
      ''} "$out/bin/qemu-system-x86_64"
    '';
  };
  exportSession = pkgs.writeShellApplication {
    name = "folio-test-export-niri-session";
    runtimeInputs = [ pkgs.systemd pkgs.dbus pkgs.coreutils ];
    text = ''
      systemctl --user import-environment WAYLAND_DISPLAY DISPLAY NIRI_SOCKET XDG_CURRENT_DESKTOP XDG_SESSION_TYPE
      dbus-update-activation-environment WAYLAND_DISPLAY DISPLAY NIRI_SOCKET XDG_CURRENT_DESKTOP XDG_SESSION_TYPE
      touch "$XDG_RUNTIME_DIR/folio-test-session-exported"
    '';
  };
in pkgs.testers.runNixOSTest {
  name = "folio-desktop-session";
  nodes.machine = { lib, ... }: {
    imports = modules;
    _module.args.folioBootstrap = bootstrap;
    # The guest's main Niri session runs on a dedicated virtual X server. This
    # exercises real Wayland clients/portals with software GL, without claiming
    # a direct DRM or physical GPU acceptance result.
    services.greetd.enable = lib.mkForce false;
    systemd.user.services.folio-manager.serviceConfig = {
      ExecStartPre = lib.mkForce "${pkgs.folio.repository}/bin/folio-repository user init ${oldBootstrap}/models/user ${oldBootstrap}/user.json";
      # Manager's unchanged global protocol can serve the old installed model
      # set before the explicit upgrade; no new module RPC is used at this point.
      ExecStart = lib.mkForce "${runtime}/bin/folio-manager-subscriber user ${oldBootstrap}";
    };
    systemd.user.services.folio-test-xserver = lib.mkIf (!drm) {
      description = "Disposable virtual display for the Niri integration gate";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.xorg.xorgserver}/bin/Xvfb :1 -screen 0 1280x800x24 -nolisten tcp -ac";
        Restart = "on-failure";
      };
    };
    systemd.services.folio-test-drm-session = lib.mkIf drm {
      description = "Disposable DRM session for actual portal capture";
      after = [ "systemd-user-sessions.service" "getty@tty1.service" ];
      conflicts = [ "getty@tty1.service" ];
      serviceConfig = {
        User = "folio";
        PAMName = "login";
        TTYPath = "/dev/tty1";
        StandardInput = "tty";
        StandardOutput = "journal";
        Environment = [ "XDG_RUNTIME_DIR=/run/user/1000" "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus" "XDG_SESSION_TYPE=wayland" "XDG_CURRENT_DESKTOP=niri" ];
        ExecStart = "${pkgs.niri}/bin/niri-session";
      };
    };
    systemd.user.services.niri.serviceConfig = lib.mkIf (!drm) {
      Environment = "LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath (with pkgs; [ libxcursor libxrandr libxi libx11 libxkbcommon libglvnd ])}";
      ExecStart = lib.mkForce [ "" "${pkgs.niri}/bin/niri --config /home/folio/.config/niri/config.test.kdl -- ${exportSession}/bin/folio-test-export-niri-session" ];
      ExecStartPost = "${pkgs.coreutils}/bin/timeout 20 ${pkgs.bash}/bin/bash -c 'until test -f /run/user/1000/folio-test-session-exported; do sleep 0.1; done'";
    };
    environment.systemPackages = [ pkgs.jq pkgs.xdotool pkgs.libnotify pkgs.wayland-utils
      pkgs.wl-clipboard pkgs.glib pkgs.pipewire pkgs.cliphist pkgs.mako pkgs.niri testPython ];
    virtualisation = {
      qemu.package = lib.mkIf drm (lib.mkForce softwareQemu);
      qemu.options = pkgs.lib.optionals drm [ "-vga none" "-device virtio-vga-gl" ];
      memorySize = 6144; cores = 4; diskSize = 24576;
      writableStoreUseTmpfs = false;
      additionalPaths = [ oldSeed schemaSeed userSeed oldGeneration schemaGeneration userGeneration
        inputs.nixpkgs inputs.home-manager pkgs.stdenvNoCC pkgs.shellcheck-minimal pkgs.lndir pkgs.perl ]
        ++ pkgs.lib.optional (cache != null) cache ++ pkgs.lib.optional (plans != null) plans;
    };
    nix.settings.substituters = lib.mkForce [ ];
  };
  testScript = ''
    import datetime
    import json
    import shlex
    import time
    from typing import Any, cast

    cli = "${cli}/bin/folio"
    session_env = {}

    def user(command, timeout=240):
        environment = {"HOME":"/home/folio", "USER":"folio", "XDG_STATE_HOME":"/home/folio/.local/state",
            "XDG_RUNTIME_DIR":"/run/user/1000", "DBUS_SESSION_BUS_ADDRESS":"unix:path=/run/user/1000/bus"}
        environment.update(session_env)
        prefix = "runuser -u folio -- env " + " ".join(shlex.quote(key+"="+value) for key,value in environment.items())
        return machine.succeed(prefix + " bash -c " + shlex.quote("set -euo pipefail; " + command), timeout=datetime.timedelta(seconds=timeout))

    def folio(arguments):
        return json.loads(user(cli + " --json " + arguments, 600))

    def save(configuration):
        user("printf %s " + shlex.quote(json.dumps(configuration)) + " >/home/folio/desired.json")
        result = folio("config import /home/folio/desired.json")
        assert result["status"]=="success", result

    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("folio-manager.service", user="folio")
    ${pkgs.lib.optionalString (!drm) ''machine.wait_for_file("/tmp/.X11-unix/X1")''}
    plan = folio("plan --source ${oldSeed}")["data"]["planId"]
    assert folio("build " + plan)["status"]=="success"
    assert folio("apply " + plan)["status"]=="success"

    ${pkgs.lib.optionalString (legacy != null) ''
    with subtest("new user models use the explicit paired schema upgrade path"):
        before = user("readlink -f /home/folio/.local/state/nix/profiles/home-manager").strip()
        user("${runtime}/bin/folio-manager-maintain user ${oldBootstrap} upgrade desktop-models ${schemaSeed}", 600)
        after = user("readlink -f /home/folio/.local/state/nix/profiles/home-manager").strip()
        assert after != before
        user("folio-repository user ctl --list | grep folio-desktop")
    ''}

    save(json.loads(user("jq .configuration ${userSeed}/folio-input.json")))
    plan = folio("plan --source ${userSeed}")["data"]["planId"]
    assert folio("build " + plan)["status"]=="success"
    assert folio("apply " + plan)["status"]=="success"
    machine.wait_for_unit("folio-devices.service", user="folio")

    with subtest("actual device observations and unavailable hardware"):
        observed = folio("devices status")
        assert observed["status"]=="success", observed
        assert observed["data"]["hardware"]["logicalCpus"]==4
        assert observed["data"]["physicalAcceptance"]=="unverified"
        assert not observed["data"]["brightness"]["available"]
        result = json.loads(user("code=0; " + cli + " --json devices brightness 50 || code=$?; test $code = 3"))
        assert result["status"]=="unavailable", result

    ${pkgs.lib.optionalString (cache != null && plans != null) ''
    with subtest("cached applications use the actual desktop prerequisites"):
        user("mkdir -p /home/folio/.local/share/flatpak /home/folio/.local/state/folio/applications/prepared; cp -R ${cache}/. /home/folio/.local/share/flatpak/; chmod -R u+w /home/folio/.local/share/flatpak; cp ${plans}/*.json /home/folio/.local/state/folio/applications/prepared/")
        assert folio("apps install all --offline")["status"]=="success"
    ''}

    with subtest("Niri Wayland session on a disposable virtual display"):
        if ${if drm then "True" else "False"}:
            machine.succeed("systemctl start folio-test-drm-session.service")
            machine.wait_for_unit("folio-test-drm-session.service")
        else:
            user("cat /home/folio/.config/niri/config.kdl >/home/folio/.config/niri/config.test.kdl; printf '\\ndebug { dbus-interfaces-in-non-session-instances; }\\n' >>/home/folio/.config/niri/config.test.kdl")
            user("DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 XDG_CURRENT_DESKTOP=niri XDG_SESSION_TYPE=wayland dbus-update-activation-environment --systemd DISPLAY LIBGL_ALWAYS_SOFTWARE XDG_CURRENT_DESKTOP XDG_SESSION_TYPE")
            user("systemctl --user start niri.service")
            machine.wait_for_unit("niri.service", user="folio")
        machine.wait_until_succeeds("runuser -u folio -- env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user show-environment | grep '^NIRI_SOCKET='", timeout=datetime.timedelta(seconds=40))
        for line in user("systemctl --user show-environment").splitlines():
            if line.startswith(("NIRI_SOCKET=", "WAYLAND_DISPLAY=", "DISPLAY=", "XDG_CURRENT_DESKTOP=", "XDG_SESSION_TYPE=")):
                key,value = line.split("=",1)
                session_env[key]=value
        outputs = json.loads(user("niri msg --json outputs"))
        assert outputs, outputs
        machine.wait_for_unit("waybar.service", user="folio")
        machine.wait_for_unit("fcitx5-daemon.service", user="folio")
        user("notify-send 'Folio desktop check' 'Notifications are running'; systemctl --user is-active mako.service; wayland-info >/home/folio/wayland-info.txt")
        user("niri msg action spawn -- foot --title='Folio session check'")
        machine.wait_until_succeeds("runuser -u folio -- pgrep -x foot", timeout=datetime.timedelta(seconds=20))
        user("notify-send 'Folio desktop check' 'Notifications are running'")
        user("wl-copy 'folio-clipboard-sentinel'; sleep 1; wl-paste --no-newline | grep folio-clipboard-sentinel; cliphist list | grep folio-clipboard-sentinel")
        user("niri msg action screenshot-screen --path /home/folio/desktop.png")
        machine.wait_for_file("/home/folio/desktop.png")
        machine.copy_from_machine("/home/folio/desktop.png")
        user("fc-match 'Maple Mono NF CN' | grep -i maple; test -f /home/folio/.local/share/fcitx5/themes/folio/panel.png")
        metadata = json.loads(user("cat /home/folio/.config/folio/appearance.json"))
        assert metadata["cursor"]=="GoogleDot-Folio" and metadata["cursor-size"]==28
        ${pkgs.lib.optionalString (!drm) ''user("DISPLAY=:1 xdotool search --name '^niri$' windowfocus --sync key --clearmodifiers Super_L+d; sleep 1; pgrep -u folio -x fuzzel; DISPLAY=:1 xdotool key Escape")''}
        if ${if drm then "True" else "False"}:
            machine.send_key("meta_l-d")
            machine.wait_until_succeeds("pgrep -u folio -x fuzzel")
            machine.send_key("esc")
            user("pkill -x fuzzel || true")
    if ${if drm then "True" else "False"}:
        with subtest("Rime commits actual Chinese text through a Wayland terminal"):
            user("niri msg action spawn -- foot --title='Folio input check' sh -c 'cat >/home/folio/rime-input.txt'")
            machine.wait_until_succeeds("runuser -u folio -- env XDG_RUNTIME_DIR=/run/user/1000 NIRI_SOCKET=" + session_env["NIRI_SOCKET"] + " niri msg --json windows | jq -e \'any(.[]; .title==\"Folio input check\")\'")
            user("niri msg action focus-window --id $(niri msg --json windows | jq -r \'first(.[]|select(.title==\"Folio input check\")).id\')")
            user("gdbus call --session --dest org.fcitx.Fcitx5 --object-path /controller --method org.fcitx.Fcitx.Controller1.SetCurrentIM rime; gdbus call --session --dest org.fcitx.Fcitx5 --object-path /controller --method org.fcitx.Fcitx.Controller1.Activate")
            # A prism can exist while other schemas are still being compiled.
            # This fresh profile records last_build_time after deployment ends.
            machine.wait_until_succeeds("grep -Eq 'last_build_time: [1-9][0-9]*' /home/folio/.local/share/fcitx5/rime/user.yaml", timeout=datetime.timedelta(seconds=90))
            user("gdbus call --session --dest org.fcitx.Fcitx5 --object-path /controller --method org.fcitx.Fcitx.Controller1.Activate")
            machine.send_chars("nihao", delay=datetime.timedelta(milliseconds=100))
            time.sleep(1)
            machine.send_key("spc")
            machine.send_key("ret")
            machine.send_key("ctrl-d")
            print(user("cat /home/folio/rime-input.txt"))
            machine.wait_until_succeeds("grep -q '你好' /home/folio/rime-input.txt", timeout=datetime.timedelta(seconds=20))
            machine.copy_from_machine("/home/folio/rime-input.txt")

    if ${if drm && cache != null && plans != null then "True" else "False"}:
        with subtest("OBS captures changing frames through the real portal and PipeWire"):
            # Only the disposable guest enables this loopback test interface.
            user("mkdir -p /home/folio/.var/app/com.obsproject.Studio/config/obs-studio/plugin_config/obs-websocket")
            websocket_config = {"server_enabled":True,"server_port":4455,"auth_required":False,"alerts_enabled":False,"first_load":False}
            user("printf %s " + shlex.quote(json.dumps(websocket_config)) + " >/home/folio/.var/app/com.obsproject.Studio/config/obs-studio/plugin_config/obs-websocket/config.json")
            helper = "${testPython}/bin/python3 ${./obs-capture.py} "
            user("systemd-run --user --collect --unit=folio-test-obs --setenv=FLATPAK_GL_DRIVERS=default flatpak run --user com.obsproject.Studio --disable-shutdown-check --disable-missing-files-check")
            def eventually(command):
                for attempt in range(30):
                    try:
                        return user(command, 20)
                    except Exception:
                        if attempt == 29:
                            raise
                        time.sleep(1)
            probe = json.loads(eventually(helper + "probe"))
            assert "pipewire-screen-capture-source" in probe["pipewireKinds"], probe
            # The websocket can become ready before the first-run modal maps.
            # Dismiss it before opening properties, or it consumes selector clicks.
            machine.wait_until_succeeds("runuser -u folio -- env XDG_RUNTIME_DIR=/run/user/1000 NIRI_SOCKET=" + session_env["NIRI_SOCKET"] + " niri msg --json windows | jq -e \'any(.[]; .title==\"Auto-Configuration Wizard\")\'", timeout=datetime.timedelta(seconds=20))
            windows = json.loads(user("niri msg --json windows"))
            wizard = next((window for window in windows if window["title"]=="Auto-Configuration Wizard"), None)
            if wizard:
                user("niri msg action focus-window --id " + str(wizard["id"]) + "; niri msg action close-window")
            user(helper + "create")
            user(helper + "properties")
            time.sleep(1)
            assert machine.qmp_client is not None
            # The driver annotation restricts QMP arguments to strings, while
            # input-send-event uses the protocol's nested JSON structures.
            qmp = cast(Any, machine.qmp_client)
            def click(x, y):
                qmp.send("input-send-event", {"events":[
                    {"type":"abs","data":{"axis":"x","value":int(x*32767/1280)}},
                    {"type":"abs","data":{"axis":"y","value":int(y*32767/800)}}]})
                time.sleep(0.3)
                for down in (True, False):
                    qmp.send("input-send-event", {"events":[{"type":"btn","data":{"down":down,"button":"left"}}]})
                    time.sleep(0.2)
            for attempt in range(6):
                windows = json.loads(user("niri msg --json windows"))
                selector = next((window for window in windows if window["title"]=="Share Screen"), None)
                if selector:
                    geometry = selector["layout"]
                    x,y = geometry["tile_pos_in_workspace_view"]
                    width,height = geometry["window_size"]
                    # A selected tile enables Share. An additional bounded attempt
                    # handles the chooser's initial selection state without bypassing it.
                    click(x+width/2, y+height*0.71)
                    click(x+width-55, y+25)
                else:
                    properties = next((window for window in windows if window["title"].startswith("Properties for")), None)
                    if properties:
                        x,y = properties["layout"]["tile_pos_in_workspace_view"]
                        click(x+90, y+298)
                time.sleep(1)
                frame = json.loads(user(helper + "snapshot /home/folio/obs-frame1.png", 20))
                if frame["colors"]>100:
                    break
            assert frame["colors"]>100, frame
            nodes = json.loads(user("timeout 5 pw-dump"))
            assert any(node.get("info", {}).get("props", {}).get("node.name")=="niri" and node["info"]["state"]=="running" for node in nodes), nodes
            user("notify-send 'Folio actual capture' 'Changed pixels from the live Wayland desktop'")
            time.sleep(1)
            changed = json.loads(user(helper + "snapshot /home/folio/obs-frame2.png", 20))
            assert changed["colors"]>100 and changed["sha256"]!=frame["sha256"], (frame,changed)
            machine.copy_from_machine("/home/folio/obs-frame2.png")
  '';
}
