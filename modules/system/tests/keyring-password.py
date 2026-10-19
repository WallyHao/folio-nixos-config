"""Run with helper, daemon and secret-tool paths; use a private bus and keyring."""
import os
import pty
import select
import signal
import subprocess
import sys
import tempfile
import time

if sys.argv[1] != "--isolated":
    with tempfile.TemporaryDirectory(prefix="folio-keyring-test-") as root:
        env = os.environ.copy()
        env.update(HOME=root, XDG_DATA_HOME=root + "/data",
                   XDG_CONFIG_HOME=root + "/config", XDG_RUNTIME_DIR=root + "/runtime")
        for name in ("GNOME_KEYRING_CONTROL", "GNOME_KEYRING_PID",
                     "DBUS_SESSION_BUS_ADDRESS", "DBUS_STARTER_ADDRESS", "DBUS_STARTER_BUS_TYPE"):
            env.pop(name, None)
        os.mkdir(env["XDG_RUNTIME_DIR"], 0o700)
        # The bus itself must inherit the private HOME before it starts so that
        # any D-Bus-activated daemon also uses disposable keyring storage.
        completed = subprocess.run(["dbus-run-session", "--", sys.executable,
                                    __file__, "--isolated", *sys.argv[1:]], env=env)
        sys.exit(completed.returncode)

helper, daemon, secret_tool = sys.argv[2:]


def change(values, succeeds):
    pid, master = pty.fork()
    if pid == 0:
        os.execl(helper, helper)
    output = b""
    prompts = [b"Previous keyring password: ",
               b"Current folio login password (new keyring password): ",
               b"Repeat new keyring password: "]
    index = 0
    deadline = time.monotonic() + 15
    try:
        while time.monotonic() < deadline:
            if select.select([master], [], [], 0.1)[0]:
                try:
                    chunk = os.read(master, 4096)
                except OSError:
                    break
                if not chunk:
                    break
                output += chunk
                if index < len(prompts) and prompts[index] in output:
                    os.write(master, values[index].encode() + b"\n")
                    index += 1
        else:
            raise AssertionError("Password helper timed out")
        _, status = os.waitpid(pid, 0)
        assert os.waitstatus_to_exitcode(status) == (0 if succeeds else 1)
        assert index == 3
        assert all(value.encode() not in output for value in values if value)
    except BaseException:
        try:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
        except ProcessLookupError:
            pass
        raise
    finally:
        os.close(master)


def isolated_test():
    process = subprocess.Popen([daemon, "--foreground", "--unlock", "--components=secrets"],
                               stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL)
    try:
        process.stdin.write(b"fixture-old-password")
        process.stdin.close()
        for _ in range(100):
            check = subprocess.run([helper, "--check"], capture_output=True, timeout=5)
            if check.returncode == 0:
                break
            time.sleep(0.1)
        else:
            raise AssertionError("Isolated keyring did not start")
        subprocess.run([secret_tool, "store", "--label=Folio test", "folio-test", "fixture"],
                       input=b"fixture-credential", check=True, timeout=10)
        change(["fixture-wrong-password", "fixture-new-password", "fixture-new-password"], False)
        change(["fixture-old-password", "fixture-new-password", "fixture-mismatch"], False)
        change(["fixture-old-password", "", ""], False)
        change(["fixture-old-password", "fixture-new-password", "fixture-new-password"], True)
        change(["fixture-new-password", "fixture-restored-password", "fixture-restored-password"], True)
        stored = subprocess.check_output([secret_tool, "lookup", "folio-test", "fixture"], timeout=10)
        assert stored.strip() == b"fixture-credential"
        print("PASS: wrong/empty/mismatched passwords rejected; password change and credential preservation verified; terminal input not echoed")
    finally:
        process.terminate()
        process.wait(timeout=10)


isolated_test()
