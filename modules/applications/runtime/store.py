"""Interactive user Flatpak catalogue and serialized, observable transactions."""

import json
import os
from pathlib import Path
import re
import stat
import tempfile
import subprocess

IDENTITY = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,254}\Z")
REF = re.compile(r"app/[A-Za-z0-9_.-]+/[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+\Z")


def repair_icon_theme():
    # Nix's read-only index.theme can be copied verbatim into user Flatpak exports.
    base = Path(
        os.environ.get(
            "FLATPAK_USER_DIR",
            Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "flatpak",
        )
    )
    path = base / "exports/share/icons/hicolor/index.theme"
    try:
        info = path.lstat()
    except FileNotFoundError:
        return
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & stat.S_IWUSR:
        return
    # Replace the private export, keeping any hardlinked immutable source intact.
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as file:
        temporary = Path(file.name)
        try:
            file.write(path.read_bytes())
            file.flush()
            os.fchmod(file.fileno(), stat.S_IMODE(info.st_mode) | stat.S_IWUSR)
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)


class StoreError(Exception):
    pass


class Store:
    def __init__(self, executable, client, directory=None):
        self.executable = executable
        self.client = client
        self.directory = Path(
            directory
            or Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
            / "folio/applications"
        )

    def request(self, *args):
        try:
            reply = subprocess.run(
                [self.client, "--json", *args], capture_output=True, text=True, timeout=65
            )
            envelope = json.loads(reply.stdout)
        except (OSError, ValueError, subprocess.TimeoutExpired):
            raise StoreError(
                "Applications backend unavailable. Run systemctl --user status folio-applications.service."
            ) from None
        if reply.returncode or envelope.get("status") != "success":
            raise StoreError(envelope.get("error") or "Applications backend rejected the request")
        return envelope

    def managed(self):
        config = self.request("config", "show")["data"]["configuration"][
            "folio-environment:environment"
        ]
        modules = [m for m in config["modules"] if m["name"] == "applications"]
        if not modules:
            return {}
        settings = modules[0].get("folio-applications:applications", {})
        return {app["ref"]: app for app in settings.get("app", [])}

    @staticmethod
    def display_task(task):
        if not task:
            return None
        request = task.get("request", {})
        phase = task["phase"]
        return {
            "id": task["id"],
            "action": request.get("action", "install"),
            "fields": {"id": request.get("application", "")},
            "phase": phase if phase in {"succeeded", "failed", "interrupted"} else "running",
            "detail": phase,
            "log": task.get("error") or phase,
            "error": task.get("error"),
            "recoveryRequired": task.get("recoveryRequired", False),
        }

    @property
    def task(self):
        tasks = []
        for path in (self.directory / "tasks").glob("*.json"):
            try:
                tasks.append(json.loads(path.read_text()))
            except (OSError, ValueError):
                continue
        return (
            self.display_task(max(tasks, key=lambda t: t.get("createdAt", ""))) if tasks else None
        )

    def command(self, *args, timeout=180):
        try:
            result = subprocess.run(
                [self.executable, *args],
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                timeout=timeout,
                env={**os.environ, "LC_ALL": "C", "TERM": "dumb"},
            )
        except subprocess.TimeoutExpired:
            raise StoreError("Flatpak timed out. Check your connection and try again.") from None
        if result.returncode:
            raise StoreError((result.stderr or result.stdout or "Flatpak operation failed")[-4000:])
        return result.stdout

    def installed(self):
        rows = []
        managed = self.managed()
        for scope in ("user", "system"):
            output = self.command(
                "list", "--" + scope, "--app", "--columns=ref,name,version,origin"
            )
            for line in output.splitlines():
                cells = line.split("\t")
                if len(cells) != 4:
                    continue
                ref, name, version, remote = cells
                if not ref.startswith("app/"):
                    ref = "app/" + ref
                owned = False
                if scope == "user" and ref in managed:
                    try:
                        owned = (
                            json.loads(
                                (
                                    self.directory / "owned" / (managed[ref]["name"] + ".json")
                                ).read_text()
                            ).get("ref")
                            == ref
                        )
                    except (OSError, ValueError):
                        pass
                rows.append(
                    dict(
                        ref=ref,
                        id=ref.split("/")[1],
                        name=name,
                        version=version,
                        remote=remote,
                        scope=scope,
                        managed=owned,
                        configured=ref in managed,
                        owner=(
                            managed[ref]["name"] if scope == "user" and ref in managed else None
                        ),
                        removable=owned,
                    )
                )
        return rows

    def status(self):
        remotes = self.command("remotes", "--user", "--columns=name").splitlines()
        return dict(applications=self.installed(), remotes=remotes, task=self.task)

    def search(self, query):
        if not isinstance(query, str) or not 1 <= len(query.strip()) <= 200 or "\0" in query:
            raise ValueError("Enter 1–200 characters")
        output = self.command(
            "search",
            "--user",
            "--columns=application,name,description,version,branch,remotes",
            "--",
            query.strip(),
        )
        rows = []
        for line in output.splitlines():
            cells = line.split("\t")
            if len(cells) != 6 or not IDENTITY.fullmatch(cells[0]):
                continue
            identity, name, description, version, branch, remotes = cells
            for remote in remotes.split(","):
                if remote.strip() != "flathub" or len(identity) > 128 or len(branch) > 64:
                    continue
                rows.append(
                    dict(
                        id=identity,
                        name=name,
                        description=description,
                        version=version,
                        branch=branch,
                        remote=remote.strip(),
                    )
                )
        # AppStream search also returns runtime extensions; only offer app refs.
        available = {}
        for remote in {app["remote"] for app in rows}:
            if IDENTITY.fullmatch(remote):
                output = self.command(
                    "remote-ls",
                    "--user",
                    "--app",
                    "--cached",
                    "--columns=application,branch",
                    remote,
                )
                available[remote] = {tuple(line.split("\t")) for line in output.splitlines()}
        rows = [
            app for app in rows if (app["id"], app["branch"]) in available.get(app["remote"], set())
        ]
        rows.sort(
            key=lambda app: (
                app["name"].casefold() != query.strip().casefold(),
                app["id"].casefold() != query.strip().casefold(),
                app["name"].casefold(),
            )
        )
        return {"applications": rows[:200]}

    def start(self, action, fields):
        if action in {"setup", "refresh"} and not fields:
            args = ["init" if action == "setup" else "refresh"]
        elif (
            action in {"install", "adopt"}
            and set(fields) == {"id", "remote", "branch"}
            and all(isinstance(v, str) and IDENTITY.fullmatch(v) for v in fields.values())
        ):
            if fields["remote"] != "flathub":
                raise ValueError("Only Flathub applications can be managed")
            identity = fields["id"]
            name = {"app.zen_browser.zen": "zen", "com.obsproject.Studio": "obs"}.get(
                identity, identity
            )
            args = [action, name, "--ref", "app/" + identity + "/x86_64/" + fields["branch"]]
        elif (
            action == "remove"
            and set(fields) == {"ref"}
            and isinstance(fields["ref"], str)
            and REF.fullmatch(fields["ref"])
        ):
            app = next(
                (a for a in self.installed() if a["ref"] == fields["ref"] and a["removable"]), None
            )
            if app is None:
                raise ValueError("Adopt this user application before managing it with Folio")
            args = ["remove", app["owner"]]
        elif (
            action == "resume"
            and set(fields) == {"id"}
            and isinstance(fields["id"], str)
            and re.fullmatch(r"a-[a-f0-9]{32}", fields["id"])
        ):
            args = ["resume", fields["id"]]
        else:
            raise ValueError("Unsupported Flatpak operation or fields")
        repair_icon_theme()
        envelope = self.request("--no-wait", "apps", *args)
        return self.display_task(envelope["data"])
