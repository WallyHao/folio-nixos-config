{
  pkgs,
  drm ? true,
  cache ? null,
  plans ? null,
  testPython,
}:
''
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
      assert metadata["cursor"]=="GoogleDot-Folio" and metadata["cursor-size"]==42
      ${pkgs.lib.optionalString (!drm)
        ''user("DISPLAY=:1 xdotool search --name '^niri$' windowfocus --sync key --clearmodifiers Super_L+d; sleep 1; pgrep -u folio -x fuzzel; DISPLAY=:1 xdotool key Escape")''
      }
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
          helper = "${testPython}/bin/python3 /etc/folio-test/obs-capture.py "
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
''
