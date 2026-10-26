"""Coordinate reviewed immutable system/user plans using the scoped backends."""

import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import subprocess
import sys
import tempfile
import time
import uuid

from records import digest, now, process_identity, save


class Failure(Exception):
    def __init__(self, message, status="failure"):
        super().__init__(message)
        self.status = status


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise Failure(message, "invalid")


def plain(value):
    # Comments and file names must never inject terminal control sequences.
    return "".join(c if c.isprintable() else " " for c in str(value))


class Workflow:
    def __init__(self):
        self.json = os.environ.get("FOLIO_JSON") == "true"
        self.no_wait = os.environ.get("FOLIO_NO_WAIT") == "true"
        state = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
        self.root = state / "folio/deployments/workflows"
        self.deploy = os.environ["FOLIO_DEPLOY_ADAPTER"]
        self.maintenance = os.environ["FOLIO_MAINTENANCE_ADAPTER"]
        self.forwarded = None
        self.current_job = None

    def paint(self, text, tone, stream=None):
        stream = stream if stream is not None else sys.stdout
        if (
            self.json
            or not stream.isatty()
            or "NO_COLOR" in os.environ
            or os.environ.get("TERM") == "dumb"
        ):
            return text
        colors = {
            "heading": "1;36",
            "success": "1;32",
            "warning": "33",
            "error": "31",
            "muted": "2",
            "command": "1;36",
        }
        return f"\033[{colors[tone]}m{text}\033[0m"

    def say(self, text, tone=None):
        if tone:
            text = self.paint(text, tone)
        print(text, file=sys.stderr if self.json else sys.stdout, flush=True)

    def next_command(self, operation, identifier):
        self.say("\nNext command:", "heading")
        self.say(f"folio {operation} {identifier}", "command")
        self.say("")

    def scoped(
        self,
        scope,
        command,
        arguments=(),
        *,
        privileged=False,
        no_wait=False,
        tolerate_failure=False,
    ):
        env = os.environ.copy()
        env.update(
            FOLIO_SCOPE=scope,
            FOLIO_JSON="true",
            FOLIO_COMMAND=command,
            FOLIO_NO_WAIT="true" if no_wait else "false",
        )
        executable = self.maintenance if command == "rollback" else self.deploy
        if command == "config":
            executable = os.environ["FOLIO_CONFIG_ADAPTER"]
        invocation = [executable, *arguments]
        if privileged and scope == "system" and os.geteuid() != 0:
            invocation = [
                "sudo",
                "env",
                "FOLIO_SCOPE=system",
                "FOLIO_JSON=true",
                f"FOLIO_COMMAND={command}",
                "FOLIO_NO_WAIT=false",
                *invocation,
            ]
        result = subprocess.run(invocation, env=env, stdout=subprocess.PIPE, text=True)
        try:
            envelope = json.loads(result.stdout)
        except (ValueError, TypeError):
            raise Failure(f"{scope} {command} did not return a valid response") from None
        if (result.returncode or envelope.get("status") != "success") and not tolerate_failure:
            raise Failure(
                f"{scope}: {envelope.get('error') or command + ' failed'}",
                envelope.get("status", "failure"),
            )
        return envelope

    def histories(self, partial=False):
        result = {}
        for scope in ("system", "user"):
            deadline = time.monotonic() + 15
            while True:
                try:
                    result[scope] = self.scoped(scope, "history")["data"]
                    break
                except Failure as error:
                    if partial:
                        result[scope] = {
                            "plans": [],
                            "revisions": [],
                            "unavailable": True,
                            "error": str(error),
                        }
                        break
                    if error.status != "unavailable" or time.monotonic() >= deadline:
                        raise
                    time.sleep(0.5)
        return result

    def ask(self, message):
        if self.json or not sys.stdin.isatty():
            raise Failure(
                "Interactive confirmation requires a terminal; pass --yes to confirm non-interactively.",
                "invalid",
            )
        return input(message).strip().lower() in ("y", "yes")

    def load(self, identifier):
        if re.fullmatch("maintenance-[a-z][a-z0-9-]{0,63}", identifier):
            return None
        if not re.fullmatch("[a-f0-9]{64}", identifier):
            raise Failure("Invalid plan ID", "invalid")
        path = self.root / "plans" / f"{identifier}.json"
        if not path.is_file():
            return None
        value = json.loads(path.read_text())
        if digest(value) != identifier:
            raise Failure("Plan digest mismatch", "conflict")
        return value

    def capture(self, source, directory):
        try:
            source = Path(source).resolve(strict=True)
        except OSError:
            raise Failure("Source directory is unavailable", "invalid") from None
        if not all((source / name).exists() for name in ("flake.nix", "flake.lock", "modules")):
            raise Failure("Source must contain the root Flake/lock and modules", "invalid")
        destination = Path(directory) / "source"
        destination.mkdir()
        entries = ["flake.nix", "flake.lock", "modules"]
        entries += [
            name
            for name in ("assets", "folio-target.json", "ruff.toml")
            if (source / name).exists()
        ]
        archive = Path(directory) / "source.tar"
        excludes = [
            ".git",
            ".aws",
            ".codex",
            ".agents",
            ".ssh",
            ".env*",
            "result",
            "result-*",
            "*.log",
            "*.raw",
            "*.qcow2",
            "__pycache__",
            "*.pyc",
        ]
        subprocess.run(
            [
                "tar",
                "-C",
                str(source),
                *[f"--exclude={p}" for p in excludes],
                "-cf",
                str(archive),
                *entries,
            ],
            check=True,
        )
        subprocess.run(
            ["tar", "--no-same-owner", "-xf", str(archive), "-C", str(destination)], check=True
        )
        for entry in destination.rglob("*"):
            if entry.is_symlink() and not entry.resolve(strict=True).is_relative_to(destination):
                raise Failure("Source contains an escaping symlink", "invalid")
        result = subprocess.run(
            ["nix", "store", "add-path", "--name", "folio-review-source", str(destination)],
            check=True,
            stdout=subprocess.PIPE,
            text=True,
        )
        frozen = result.stdout.strip()
        subprocess.run(
            [
                "nix-store",
                "--realise",
                frozen,
                "--add-root",
                str(Path(directory) / "source-root"),
                "--indirect",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        return frozen

    def show_review(self, scope, review):
        self.say(f"\n{scope.capitalize()} scope:", "heading")
        if review["firstDeployment"]:
            self.say("  First deployment; no applied baseline.")
        if review.get("drift"):
            self.say(
                "  Managed files or the running system differ from the selected profile; resolve this before activation.",
                "warning",
            )
        if not review["changed"]:
            self.say("  No activation required.", "muted")
            return
        for module in review["configurationModules"]:
            self.say(f"  Configuration: {plain(module)}")
        for field in review["configurationFields"]:
            self.say(f"  Environment setting: {plain(field)}")
        for item in review.get("preferenceChanges", []):
            self.say(f"  {plain(item['field'])}: {plain(item['before'])} -> {plain(item['after'])}")
        for item in review.get("impacts", []):
            self.say(f"  {plain(item['module'])}: {plain(item['message'])}", "warning")
        if review.get("disabledModules"):
            self.say(
                "  Disabled modules: "
                + ", ".join(review["disabledModules"])
                + ". Personal application data is retained.",
                "warning",
            )
        if review.get("kernelChanged"):
            self.say("  Kernel changed. Reboot after deployment to load it.", "warning")
        changes = review["sourceChanges"]
        for item in changes[:30]:
            ownership = "shared dependency" if item["shared"] else f"{item['module']} module"
            tone = {"added": "success", "removed": "error", "modified": "warning"}.get(
                item["kind"], "muted"
            )
            self.say(f"  {plain(item['path'])} ({plain(ownership)}; {plain(item['kind'])})", tone)
        if len(changes) > 30:
            self.say(f"  ... {len(changes) - 30} more changed files (included in the plan).")
        self.say("  Generated environment differs from the applied version.")

    def plan(self, arguments):
        parser = Parser(prog="folio plan")
        parser.add_argument("--source", default=os.getcwd())
        parser.add_argument("--timeout-seconds", type=int, default=1800)
        parser.add_argument("--yes", action="store_true")
        parser.add_argument("--comment")
        args = parser.parse_args(arguments)
        if not 1 <= args.timeout_seconds <= 86400:
            raise Failure("Timeout must be 1..86400 seconds", "invalid")
        if args.comment is not None and len(args.comment) > 4096:
            raise Failure("Comment must be at most 4096 characters", "invalid")
        if args.yes and args.comment is None:
            raise Failure("--yes requires --comment TEXT", "invalid")
        if not args.yes and (self.json or not sys.stdin.isatty()):
            raise Failure("Use folio plan --yes --comment TEXT in non-interactive mode", "invalid")
        drafts = {}
        with tempfile.TemporaryDirectory(prefix="folio-review-") as directory:
            frozen = self.capture(args.source, directory)
            try:
                self.say(f"Source: {plain(Path(args.source).resolve())}", "heading")
                self.say("Comparing with each scope's last applied environment...", "muted")
                descriptor = None
                for scope in ("system", "user"):
                    options = [
                        "--source",
                        frozen,
                        "--mode",
                        "preview",
                        "--timeout-seconds",
                        str(args.timeout_seconds),
                    ]
                    if scope == "user" and descriptor is not None:
                        options += ["--descriptor-json", json.dumps(descriptor)]
                    result = self.scoped(scope, "plan", options)["data"]
                    drafts[scope] = result
                    review = result["plan"]["review"]
                    if scope == "system":
                        descriptor = review.get("targetDescriptor")
                    self.show_review(scope, review)
                if not any(item["plan"]["review"]["changed"] for item in drafts.values()):
                    self.say("\nNo unapplied changes. No plan created.", "success")
                    return {"planId": None, "changed": False}
                if not args.yes and not self.ask("\nCreate this deployment plan? [y/N] "):
                    return {"planId": None, "cancelled": True}
                comment = args.comment if args.comment is not None else input("Comment: ").strip()
                if len(comment) > 4096:
                    raise Failure("Comment must be at most 4096 characters", "invalid")
                components = {}
                try:
                    for scope, draft in drafts.items():
                        accepted = self.scoped(
                            scope,
                            "plan",
                            [
                                "--source",
                                frozen,
                                "--mode",
                                "confirm",
                                "--draft-id",
                                draft["planId"],
                                "--comment",
                                comment,
                            ],
                        )["data"]
                        plan = accepted["plan"]
                        prior = plan.get("priorDeployment") or {}
                        components[scope] = {
                            "planId": accepted["planId"],
                            "plan": plan,
                            "changed": plan["review"]["changed"],
                            "restoreId": accepted["planId"]
                            if plan["review"]["changed"]
                            else prior.get("revisionId", prior.get("planId")),
                        }
                except BaseException:
                    if components:
                        self.say(
                            "No combined plan was created. Already confirmed scoped plans were retained:"
                        )
                        for scope, component in components.items():
                            self.say(f"  {scope}: {component['planId']}")
                    raise
                record = {
                    "format": 1,
                    "kind": "deployment-plan",
                    "createdAt": now(),
                    "comment": comment,
                    "source": frozen,
                    "components": components,
                }
                identifier = digest(record)
                root = self.root / "roots" / f"source-{identifier}"
                root.parent.mkdir(parents=True, exist_ok=True)
                subprocess.run(
                    ["nix-store", "--realise", frozen, "--add-root", str(root), "--indirect"],
                    check=True,
                    stdout=subprocess.DEVNULL,
                )
                save(self.root / "plans" / f"{identifier}.json", record)
                self.say(f"\nCreated plan: {identifier}", "success")
                self.say(f"Comment: {plain(comment)}", "muted")
                self.next_command("build", identifier)
                return {"planId": identifier, "plan": record}
            finally:
                for scope, draft in drafts.items():
                    try:
                        self.scoped(
                            scope,
                            "plan",
                            ["--source", frozen, "--mode", "cancel", "--draft-id", draft["planId"]],
                        )
                    except Failure:
                        # A confirmed draft has already been consumed. Any other
                        # interrupted draft remains rooted for explicit recovery.
                        pass

    def executions(self, identifier, partial=False):
        folder = self.root / "executions" / identifier
        records = []
        for path in folder.glob("*.json"):
            event = json.loads(path.read_text())
            owner = event.get("coordinator")
            if event["phase"] == "running" and owner and process_identity(owner["pid"]) != owner:
                event["phase"] = "interrupted"
            if event["phase"] in ("submitted", "interrupted"):
                for step in event["steps"]:
                    if step.get("phase") != "submitted" or not step.get("taskId"):
                        continue
                    try:
                        task = self.scoped(step["scope"], "status", [step["taskId"]])["data"][
                            "task"
                        ]
                    except Failure:
                        continue
                    if task["phase"] in ("succeeded", "failed", "interrupted"):
                        step["phase"] = task["phase"]
                        step["result"] = task
                phases = [step["phase"] for step in event["steps"]]
                if any(phase in ("failed", "interrupted") for phase in phases):
                    event["phase"] = "failed"
                elif set(s["scope"] for s in event["steps"]) == set(
                    event.get("requiredScopes", [])
                ) and all(phase in ("succeeded", "already-current") for phase in phases):
                    event["phase"] = "succeeded"
                    if event["operation"] == "apply":
                        plan = self.load(identifier)
                        observed = self.histories(partial=partial)
                        if any(value.get("unavailable") for value in observed.values()):
                            event["phase"] = "submitted"
                        elif not all(
                            self.matches(c, observed[s]) for s, c in plan["components"].items()
                        ):
                            event["phase"] = "failed"
                            event["error"] = "The complete target no longer matches the plan"
                save(path, event)
            records.append(event)
        return sorted(records, key=lambda entry: entry["createdAt"])

    def history(self, arguments):
        if arguments:
            raise Failure("Usage: folio history", "invalid")
        observed = self.histories(partial=True)
        records = []
        for path in (self.root / "plans").glob("*.json"):
            plan = self.load(path.stem)
            executions = self.executions(path.stem, partial=True)
            index = {
                scope: {item["planId"]: item for item in data["plans"]}
                for scope, data in observed.items()
            }
            states = [
                index[scope].get(component["planId"], {}).get("status", "unavailable")
                for scope, component in plan["components"].items()
                if component["changed"]
            ]
            if executions:
                last = executions[-1]
                status = f"{last['operation']}:{last['phase']}"
            else:
                status = (
                    "built"
                    if states and all(s in ("built", "applied") for s in states)
                    else "planned"
                )
            record = {
                "planId": path.stem,
                "comment": plan["comment"],
                "createdAt": plan["createdAt"],
                "scopes": [s for s, c in plan["components"].items() if c["changed"]],
                "status": status,
                "executions": executions,
            }
            records.append(record)
        records.sort(key=lambda entry: entry["createdAt"], reverse=True)
        for record in records:
            self.say(
                f"{record['planId']}  {record['status']}  {','.join(record['scopes'])}\n  {plain(record['comment'])}"
            )
        if not records:
            self.say(
                "No reviewed deployment plans. Scoped legacy history is available with --user/--system history."
            )
        return {
            "plans": records,
            "scopedHistory": observed,
            "workflows": [self.job(path.stem) for path in (self.root / "jobs").glob("w-*.json")],
        }

    @contextlib.contextmanager
    def lock(self):
        self.root.mkdir(parents=True, exist_ok=True)
        with (self.root / "operation.lock").open("a") as stream:
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise Failure("Another deployment workflow is running", "conflict") from None
            yield

    @staticmethod
    def matches(component, observed):
        return (
            observed["selectedProfile"] == component["plan"]["review"]["targetArtifact"]
            and observed["desiredDigest"] == component["plan"]["configurationDigest"]
            and observed["effectsMatch"]
            and observed["configurationSaved"]
            and not observed["recoveryRequired"]
        )

    def wait_task(self, scope, identifier, timeout):
        deadline = time.monotonic() + timeout + 70
        while time.monotonic() < deadline:
            try:
                task = self.scoped(scope, "status", [identifier])["data"]["task"]
            except Failure as error:
                if error.status != "unavailable":
                    raise
                time.sleep(0.5)
                continue
            if task["phase"] == "succeeded":
                return task
            if task["phase"] in ("failed", "interrupted"):
                raise Failure(
                    f"{scope}: {task.get('error') or 'Deployment task failed'}",
                    task.get("resultStatus") or "failure",
                )
            time.sleep(0.5)
        raise Failure(
            f"{scope}: stopped waiting; task {identifier} remains recorded", "unavailable"
        )

    def job_path(self, identifier):
        if not re.fullmatch(r"w-[a-f0-9]{32}", identifier):
            raise Failure("Invalid workflow ID", "invalid")
        return self.root / "jobs" / f"{identifier}.json"

    def job(self, identifier):
        path = self.job_path(identifier)
        if not path.exists():
            raise Failure("Unknown workflow", "invalid")
        record = json.loads(path.read_text())
        if (
            record["phase"] == "running"
            and process_identity(record["coordinator"]["pid"]) != record["coordinator"]
        ):
            record.update(
                phase="interrupted", error="Workflow stopped. Run folio resume " + identifier
            )
        if record["phase"] in {"queued", "interrupted", "failed"}:
            record["nextCommand"] = "folio resume " + identifier
        return record

    def launch_job(self, identifier):
        executable = os.environ.get("FOLIO_WORKFLOW_EXECUTABLE")
        if not executable:
            raise Failure("Durable workflow worker is unavailable", "unavailable")
        record = self.job(identifier)
        plan = self.load(record["planId"])
        timeout = (
            sum(
                component["plan"].get("timeoutSeconds", 1800) + 90
                for component in plan["components"].values()
            )
            + 60
        )
        # A failed unit can still be exiting when an explicit retry arrives.
        # Independent dispatch names avoid that collision; the job lock remains
        # the authoritative guard against duplicate coordinators.
        unit = "folio-workflow-" + identifier + "-" + uuid.uuid4().hex[:8]
        command = [
            "systemd-run",
            "--user",
            "--collect",
            "--quiet",
            "--service-type=exec",
            "--unit=" + unit,
            "--property=TimeoutStopSec=15",
            "--property=UMask=0077",
            "--property=RuntimeMaxSec=" + str(timeout * 2),
        ]
        for name in (
            "HOME",
            "USER",
            "XDG_RUNTIME_DIR",
            "XDG_STATE_HOME",
            "XDG_DATA_HOME",
            "XDG_CONFIG_HOME",
            "XDG_CACHE_HOME",
        ):
            if name in os.environ:
                command += ["--setenv=" + name + "=" + os.environ[name]]
        try:
            result = subprocess.run(
                [*command, executable, "--worker", identifier],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=15,
            )
        except subprocess.TimeoutExpired:
            raise Failure(
                "Service dispatch timed out. Inspect folio status " + identifier, "unavailable"
            ) from None
        if result.returncode:
            # A repeated identical request may already have a live unit.
            active = subprocess.run(
                ["systemctl", "--user", "is-active", "--quiet", unit + ".service"]
            )
            if active.returncode:
                raise Failure(
                    "Workflow is saved but could not start. Run folio resume " + identifier,
                    "unavailable",
                )

    def wait_job(self, identifier):
        self.say("Workflow: " + identifier, "heading")
        self.say("View progress: folio status " + identifier, "muted")
        while True:
            record = self.job(identifier)
            if record["phase"] == "succeeded":
                self.say(
                    record["operation"].capitalize() + " succeeded: " + record["planId"], "success"
                )
                if record["operation"] == "build":
                    self.next_command("apply", record["planId"])
                return record
            if record["phase"] in {"failed", "interrupted"}:
                self.forwarded = {
                    "status": record.get("resultStatus") or "failure",
                    "data": record,
                    "error": record.get("error"),
                    "taskId": identifier,
                }
                return record
            time.sleep(0.25)

    def work(self, identifier):
        path = self.job_path(identifier)
        with path.with_suffix(".lock").open("a") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return self.job(identifier)
            record = self.job(identifier)
            if record["phase"] == "succeeded":
                return record
            record.update(
                phase="running",
                coordinator=process_identity(os.getpid()),
                updatedAt=now(),
                error=None,
            )
            save(path, record)
            self.no_wait = False
            self.current_job = identifier
            try:
                if record.get("attempt", 0):
                    self.settle_previous_attempt(record)
                record["attempt"] = record.get("attempt", 0) + 1
                save(path, record)
                # An explicit retry gets fresh scoped IDs only after every task
                # from the previous attempt has reached a known terminal state.
                # Reusing a failed scoped request would return that failure forever.
                request = (
                    "r-"
                    + hashlib.sha256(f"{identifier}:{record['attempt']}".encode()).hexdigest()[:48]
                )
                record["result"] = self.execute(
                    record["operation"], [record["planId"], "--request-id", request]
                )
                record.update(phase="succeeded", resultStatus="success")
            except BaseException as error:
                record.update(
                    phase="interrupted"
                    if isinstance(error, (KeyboardInterrupt, SystemExit))
                    else "failed",
                    error=str(error) or "Workflow interrupted",
                    resultStatus=getattr(error, "status", "failure"),
                )
            record["updatedAt"] = now()
            save(path, record)
            return record

    def settle_previous_attempt(self, record):
        plan = self.load(record["planId"])
        for path in (self.root / "executions" / record["planId"]).glob("*.json"):
            event = json.loads(path.read_text())
            if event.get("workflowId") != record["id"]:
                continue
            for step in event["steps"]:
                if not step.get("taskId") and step.get("requestId"):
                    # The old coordinator may have exited after acceptance but
                    # before saving the receipt. Re-submit the exact old ID to
                    # recover that receipt before considering another attempt.
                    component = plan["components"][step["scope"]]
                    receipt = self.scoped(
                        step["scope"],
                        record["operation"],
                        [component["planId"], "--request-id", step["requestId"]],
                        no_wait=True,
                    )
                    step.update(taskId=receipt["taskId"], phase="submitted")
                    save(path, event)
                if not step.get("taskId"):
                    continue
                scope = step["scope"]
                task = self.scoped(scope, "status", [step["taskId"]])["data"]["task"]
                if task["phase"] not in {"succeeded", "failed", "interrupted"}:
                    try:
                        self.wait_task(
                            scope,
                            step["taskId"],
                            plan["components"][scope]["plan"].get("timeoutSeconds", 1800),
                        )
                    except Failure as error:
                        if error.status == "unavailable":
                            raise
                    task = self.scoped(scope, "status", [step["taskId"]])["data"]["task"]
                if task.get("recoveryRequired"):
                    raise Failure(
                        f"{scope} task {step['taskId']} requires effect recovery before resume; inspect folio --{scope} status",
                        "conflict",
                    )

    def resume(self, arguments):
        if len(arguments) != 1:
            raise Failure("Usage: folio resume WORKFLOW_ID", "invalid")
        identifier = arguments[0]
        record = self.job(identifier)
        if record["phase"] == "succeeded":
            return record
        if record["phase"] != "running":
            path = self.job_path(identifier)
            with path.with_suffix(".lock").open("a") as lock:
                deadline = time.monotonic() + 3
                while True:
                    try:
                        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        break
                    except BlockingIOError:
                        if time.monotonic() >= deadline:
                            raise Failure(
                                "Workflow is still active; inspect folio status " + identifier,
                                "conflict",
                            ) from None
                        time.sleep(0.05)
                record = self.job(identifier)
                if record["phase"] == "succeeded":
                    return record
                record.update(phase="queued", error=None, resultStatus=None, updatedAt=now())
                save(path, record)
            self.launch_job(identifier)
        if self.no_wait:
            record = self.job(identifier)
            self.forwarded = {
                "status": "success",
                "data": record,
                "error": None,
                "taskId": identifier,
            }
            return record
        return self.wait_job(identifier)

    def operate(self, operation, arguments):
        if operation not in {"build", "apply"} or not os.environ.get("FOLIO_WORKFLOW_EXECUTABLE"):
            return self.execute(operation, arguments)
        parser = Parser(prog="folio " + operation)
        parser.add_argument("plan_id")
        parser.add_argument("--request-id")
        args = parser.parse_args(arguments)
        if self.load(args.plan_id) is None:
            return self.execute(operation, arguments)
        request = args.request_id or "r-" + uuid.uuid4().hex
        if not re.fullmatch("[a-z][a-z0-9-]{0,63}", request):
            raise Failure("Invalid request ID", "invalid")
        identifier = "w-" + hashlib.sha256(request.encode()).hexdigest()[:32]
        path = self.job_path(identifier)
        with self.lock():
            if path.exists():
                record = self.job(identifier)
                if record["operation"] != operation or record["planId"] != args.plan_id:
                    raise Failure("Request ID is bound to a different workflow", "conflict")
            else:
                record = {
                    "format": 1,
                    "id": identifier,
                    "operation": operation,
                    "planId": args.plan_id,
                    "arguments": [args.plan_id, "--request-id", request],
                    "phase": "queued",
                    "createdAt": now(),
                    "updatedAt": now(),
                    "error": None,
                }
                save(path, record)
        if record["phase"] == "queued":
            self.launch_job(identifier)
        if self.no_wait:
            record = self.job(identifier)
            self.forwarded = {
                "status": "success",
                "data": record,
                "error": None,
                "taskId": identifier,
            }
            return record
        return self.wait_job(identifier)

    def status(self, arguments):
        if len(arguments) == 1 and arguments[0].startswith("w-"):
            record = self.job(arguments[0])
            events = []
            for path in (self.root / "executions" / record["planId"]).glob("*.json"):
                event = json.loads(path.read_text())
                if event.get("workflowId") == record["id"]:
                    events.append(event)
            if events:
                record["progress"] = max(events, key=lambda e: e["createdAt"])["steps"]
                for step in record["progress"]:
                    if step.get("taskId"):
                        try:
                            task = self.scoped(step["scope"], "status", [step["taskId"]])["data"][
                                "task"
                            ]
                            step["observedPhase"] = task["phase"]
                        except Failure:
                            step["observedPhase"] = "unavailable"
            # Reading status never dispatches or resumes work.
            if not self.json:
                self.say(json.dumps(record, ensure_ascii=False, indent=2))
            return record
        if arguments:
            self.forwarded = self.scoped("user", "status", arguments, tolerate_failure=True)
            return self.forwarded["data"]
        scopes = {}
        for scope in ("system", "user"):
            try:
                scopes[scope] = self.scoped(scope, "status")["data"]
            except Failure as error:
                scopes[scope] = {"health": "unavailable", "error": str(error)}
        result = {**scopes["user"], "scopes": scopes}
        if scopes["user"].get("error"):
            self.forwarded = {
                "status": "unavailable",
                "data": result,
                "error": scopes["user"]["error"],
                "taskId": None,
            }
        if not self.json:
            self.say(json.dumps(result, ensure_ascii=False, indent=2))
        return result

    def doctor(self, arguments):
        if arguments:
            raise Failure("Usage: folio doctor", "invalid")
        findings = []
        for scope in ("system", "user"):
            flag = "--" + scope
            try:
                observed = self.scoped(scope, "status")["data"]
            except Failure:
                findings.append(
                    {
                        "scope": scope,
                        "code": "backend-unavailable",
                        "message": "Manager is unavailable or access is denied.",
                        "nextCommand": (
                            "systemctl status" if scope == "system" else "systemctl --user status"
                        )
                        + " folio-manager.service",
                    }
                )
                continue
            pending_maintenance = any(
                record.get("phase") not in {"complete", "restored", "aborted"}
                for record in observed.get("maintenance", {}).values()
            )
            if pending_maintenance:
                findings.append(
                    {
                        "scope": scope,
                        "code": "maintenance-required",
                        "message": "Offline maintenance is incomplete; inspect its recorded phase before restoring.",
                        "nextCommand": "folio " + flag + " status",
                    }
                )
            if observed.get("recovery"):
                findings.append(
                    {
                        "scope": scope,
                        "code": "recovery-required",
                        "message": "Deployment effects require explicit recovery. Inspect retained tasks before rollback.",
                        "nextCommand": "folio " + flag + " status",
                    }
                )
            if not observed.get("configurationSaved", True):
                findings.append(
                    {
                        "scope": scope,
                        "code": "configuration-unsaved",
                        "message": "Configuration persistence requires recovery.",
                        "nextCommand": (
                            "journalctl -u" if scope == "system" else "journalctl --user -u"
                        )
                        + " folio-manager.service -n 50",
                    }
                )
            if (
                observed.get("health") in {"degraded", "unavailable", "unknown"}
                and not observed.get("recovery")
                and not pending_maintenance
            ):
                findings.append(
                    {
                        "scope": scope,
                        "code": "deployment-pending",
                        "message": "Desired configuration and observed deployment are not verified as current.",
                        "nextCommand": "folio plan",
                    }
                )
            if os.environ.get("FOLIO_CONFIG_ADAPTER"):
                try:
                    document = self.scoped(scope, "config", ["show"])["data"]["configuration"]
                    catalogue = json.loads(Path(os.environ["FOLIO_CATALOGUE"]).read_text())
                    checks = runpy.run_path(os.environ["FOLIO_REQUIREMENTS_COMMAND"])["findings"]
                    for message in checks(document, catalogue):
                        findings.append(
                            {
                                "scope": scope,
                                "code": "module-prerequisite-missing",
                                "message": message,
                                "nextCommand": "folio " + flag + " modules list",
                            }
                        )
                    if scope == "user":
                        descriptor_path = Path("/run/folio/public/system-descriptor.json")
                        if descriptor_path.is_file():
                            descriptor = json.loads(descriptor_path.read_text())
                            for module in document["folio-environment:environment"]["modules"]:
                                if not module.get("enabled"):
                                    continue
                                required = (
                                    catalogue.get(module["name"], {})
                                    .get("requirements", {})
                                    .get("user", {})
                                    .get("capabilities", [])
                                )
                                for capability in required:
                                    if not descriptor.get("capabilities", {}).get(capability):
                                        findings.append(
                                            {
                                                "scope": scope,
                                                "code": "system-capability-missing",
                                                "message": module["name"]
                                                + " requires system capability "
                                                + capability,
                                                "nextCommand": "folio --system modules list",
                                            }
                                        )
                except (Failure, OSError, ValueError, KeyError):
                    findings.append(
                        {
                            "scope": scope,
                            "code": "configuration-unavailable",
                            "message": "Configuration or installed model metadata could not be read.",
                            "nextCommand": "folio " + flag + " config show",
                        }
                    )
        state = self.root.parent.parent
        application_tasks = []
        for path in (state / "applications/tasks").glob("*.json"):
            try:
                task = json.loads(path.read_text())
            except (OSError, ValueError):
                continue
            application_tasks.append(task)
        latest_application = max(
            application_tasks, key=lambda t: t.get("createdAt", ""), default=None
        )
        for task in application_tasks:
            if task.get("recoveryRequired") or (
                task == latest_application and task.get("phase") in {"failed", "interrupted"}
            ):
                findings.append(
                    {
                        "scope": "applications",
                        "code": "application-task-needs-attention",
                        "message": "An application task failed or needs recovery; inspect its recorded effects.",
                        "nextCommand": "folio apps status " + task["id"],
                    }
                )
        jobs = [self.job(path.stem) for path in (self.root / "jobs").glob("w-*.json")]
        latest_jobs = {}
        for job in sorted(jobs, key=lambda j: j["createdAt"]):
            latest_jobs[job["operation"]] = job
        for job in latest_jobs.values():
            if job["phase"] in {"failed", "interrupted", "queued"}:
                findings.append(
                    {
                        "scope": "workflow",
                        "code": "workflow-" + job["phase"],
                        "message": job.get("error") or "Workflow is queued.",
                        "nextCommand": "folio status " + job["id"],
                    }
                )
        for finding in findings:
            self.say(
                f"{finding['scope']}: {finding['message']}\n  {finding['nextCommand']}", "warning"
            )
        if not findings:
            self.say(
                "Both configuration scopes are current; no deployment recovery is pending.",
                "success",
            )
        return {"health": "degraded" if findings else "healthy", "findings": findings}

    def execute(self, operation, arguments):
        parser = Parser(prog=f"folio {operation}")
        parser.add_argument("plan_id")
        parser.add_argument("--yes", action="store_true")
        parser.add_argument("--rebuild", action="store_true")
        parser.add_argument("--request-id")
        args = parser.parse_args(arguments)
        plan = self.load(args.plan_id)
        if plan is None:
            # Existing scoped plan IDs remain supported.
            options = [args.plan_id]
            if args.rebuild:
                options += ["--rebuild"]
            if args.request_id:
                options += ["--request-id", args.request_id]
            if args.yes:
                options += ["--yes"]
            self.forwarded = self.scoped(
                "user", operation, options, no_wait=self.no_wait, tolerate_failure=True
            )
            return self.forwarded["data"]
        if args.rebuild:
            raise Failure(
                "Reviewed plans restore exact artifacts. Use --user/--system rollback RETAINED_ID --rebuild for scoped compatibility recovery.",
                "invalid",
            )
        if operation == "rollback" and self.no_wait:
            raise Failure("Rollback requires waiting for verified restoration", "invalid")
        self.say(f"Plan: {args.plan_id}", "heading")
        self.say(f"Comment: {plain(plan['comment'])}", "muted")
        with self.lock():
            histories = self.histories()
            components = plan["components"]
            if operation == "rollback":
                if not any(
                    e["operation"] == "apply" and e["phase"] == "succeeded"
                    for e in self.executions(args.plan_id)
                ):
                    raise Failure(
                        "Plan has not been successfully applied; use folio apply PLAN_ID", "invalid"
                    )
                for scope, component in components.items():
                    if not component.get("restoreId"):
                        raise Failure(f"Plan has no retained {scope} baseline", "unavailable")
                    current = histories[scope].get("current") or {}
                    target = component["plan"]["review"]["targetArtifact"]
                    retained = next(
                        (
                            r
                            for r in histories[scope]["revisions"]
                            if r["revisionId"] == component["restoreId"]
                        ),
                        None,
                    )
                    if not retained or retained["artifact"] != target:
                        raise Failure(
                            f"Retained {scope} revision is unavailable or differs from the plan",
                            "unavailable",
                        )
                    self.say(
                        f"{scope.capitalize()}: {histories[scope]['selectedProfile'] or 'unavailable'} -> {target}"
                    )
                    self.say(
                        f"  Configuration: {histories[scope]['desiredDigest']} -> {component['plan']['configurationDigest']}"
                    )
                    if histories[scope]["desiredDigest"] != current.get("configurationDigest"):
                        self.say("  Unapplied configuration will also be restored.")
                    review_command = os.environ.get("FOLIO_REVIEW_COMMAND")
                    target_source = component["plan"]["source"]
                    if review_command and (Path(target_source) / "folio-input.json").is_file():
                        reviewed = subprocess.run(
                            [
                                sys.executable,
                                review_command,
                                target_source,
                                current.get("source") or "",
                                target,
                                histories[scope]["selectedProfile"],
                            ],
                            check=True,
                            stdout=subprocess.PIPE,
                            text=True,
                        )
                        self.show_review(scope, json.loads(reviewed.stdout))
                if not args.yes and not self.ask("Restore this plan? [y/N] "):
                    return {"planId": args.plan_id, "cancelled": True}
            active = (
                [s for s, c in components.items() if c["changed"]]
                if operation != "rollback"
                else list(components)
            )
            if operation == "apply":
                for scope, component in components.items():
                    observed = histories[scope]
                    if (
                        observed["desiredDigest"] != component["plan"]["configurationDigest"]
                        or (
                            observed["selectedProfile"]
                            not in (
                                component["plan"]["beforeProfile"],
                                component["plan"]["review"]["targetArtifact"],
                            )
                        )
                        or not observed["configurationSaved"]
                        or observed["recoveryRequired"]
                        or (observed["selectedProfile"] and not observed["effectsMatch"])
                    ):
                        raise Failure(
                            f"{scope} inputs changed since review; create a new plan", "conflict"
                        )
                    if not component["changed"] and not self.matches(component, histories[scope]):
                        raise Failure(
                            f"Unchanged {scope} baseline drifted; create a new plan", "conflict"
                        )
                for scope in active:
                    candidate = next(
                        (
                            p
                            for p in histories[scope]["plans"]
                            if p["planId"] == components[scope]["planId"]
                        ),
                        None,
                    )
                    if not candidate or candidate["status"] not in ("built", "applied"):
                        raise Failure(
                            f"{scope} plan is not built; run folio build PLAN_ID first",
                            "unavailable",
                        )
            request = args.request_id or "r-" + uuid.uuid4().hex
            if not re.fullmatch("[a-z][a-z0-9-]{0,63}", request):
                raise Failure("Invalid request ID", "invalid")
            event = {
                "format": 1,
                "planId": args.plan_id,
                "operation": operation,
                "workflowId": self.current_job,
                "createdAt": now(),
                "phase": "running",
                "comment": plan["comment"],
                "steps": [],
                "coordinator": process_identity(os.getpid()),
                "requiredScopes": active,
            }
            event_path = self.root / "executions" / args.plan_id / f"{uuid.uuid4().hex}.json"
            save(event_path, event)
            try:
                for scope in ("system", "user"):
                    if scope not in active:
                        continue
                    component = components[scope]
                    current = histories[scope].get("current") or {}
                    target = component["plan"]["review"]["targetArtifact"]
                    retained = any(
                        r["revisionId"] == component["restoreId"]
                        for r in histories[scope]["revisions"]
                    )
                    if (
                        operation in ("apply", "rollback")
                        and retained
                        and self.matches(component, histories[scope])
                    ):
                        event["steps"].append({"scope": scope, "phase": "already-current"})
                        save(event_path, event)
                        continue
                    self.say(f"{operation.capitalize()} {scope}: {component['planId']}", "heading")
                    options = (
                        [component["restoreId"]]
                        if operation == "rollback"
                        else [component["planId"]]
                    )
                    if operation == "rollback":
                        options += ["--yes"] + (["--rebuild"] if args.rebuild else [])
                    else:
                        scoped_request = (
                            "r-"
                            + hashlib.sha256(f"{request}:{scope}:{operation}".encode()).hexdigest()[
                                :48
                            ]
                        )
                        options += ["--request-id", scoped_request]
                    event["steps"].append(
                        {
                            "scope": scope,
                            "phase": "running",
                            "requestId": scoped_request if operation != "rollback" else None,
                        }
                    )
                    save(event_path, event)
                    queued = operation != "rollback"
                    result = self.scoped(
                        scope,
                        operation,
                        options,
                        privileged=operation == "rollback",
                        no_wait=queued,
                    )
                    event["steps"][-1] = {
                        "scope": scope,
                        "phase": "submitted" if queued else "succeeded",
                        "requestId": scoped_request if queued else None,
                        "taskId": result.get("taskId"),
                        "result": result["data"],
                    }
                    save(event_path, event)
                    if queued and not self.no_wait:
                        try:
                            task = self.wait_task(
                                scope,
                                result["taskId"],
                                component["plan"].get("timeoutSeconds", 1800),
                            )
                        except Failure as error:
                            event["steps"][-1]["phase"] = (
                                "submitted" if error.status == "unavailable" else "failed"
                            )
                            event["steps"][-1]["error"] = str(error)
                            save(event_path, event)
                            raise
                        event["steps"][-1].update(phase="succeeded", result=task)
                        save(event_path, event)
                if operation in ("apply", "rollback") and not self.no_wait:
                    observed = self.histories()
                    for scope, component in components.items():
                        current = observed[scope].get("current") or {}
                        if not self.matches(component, observed[scope]):
                            raise Failure(
                                f"{scope} no longer matches the plan; inspect history before retrying",
                                "conflict",
                            )
                        if not any(
                            r["revisionId"] == component["restoreId"]
                            for r in observed[scope]["revisions"]
                        ):
                            raise Failure(
                                f"{scope} target has no retained rollback revision", "conflict"
                            )
                event["phase"] = "submitted" if self.no_wait else "succeeded"
                save(event_path, event)
            except BaseException as error:
                pending = (
                    isinstance(error, Failure)
                    and error.status == "unavailable"
                    and any(step["phase"] == "submitted" for step in event["steps"])
                )
                event["phase"] = (
                    "interrupted"
                    if pending or isinstance(error, (KeyboardInterrupt, SystemExit))
                    else "failed"
                )
                event["error"] = str(error)
                save(event_path, event)
                raise
            self.say(
                f"\n{operation.capitalize()} {event['phase']}: {args.plan_id}",
                "success" if event["phase"] == "succeeded" else "warning",
            )
            if operation == "build" and event["phase"] == "succeeded":
                self.next_command("apply", args.plan_id)
            return event


def main():
    os.umask(0o077)
    workflow = Workflow()
    try:
        command, *arguments = sys.argv[1:]
        if command == "plan":
            result = workflow.plan(arguments)
        elif command in {"history", "doctor", "status", "resume"}:
            result = getattr(workflow, command)(arguments)
        elif command == "--worker":
            result = workflow.work(arguments[0])
            if result["phase"] in {"failed", "interrupted"}:
                workflow.forwarded = {
                    "status": result.get("resultStatus") or "failure",
                    "data": result,
                    "error": result.get("error"),
                    "taskId": result["id"],
                }
        else:
            result = workflow.operate(command, arguments)
        if workflow.json:
            print(
                json.dumps(
                    workflow.forwarded
                    or {"status": "success", "data": result, "error": None, "taskId": None}
                )
            )
        elif workflow.forwarded:
            if workflow.forwarded["status"] == "success":
                print(json.dumps(result, indent=2))
            else:
                print(
                    workflow.paint(plain(workflow.forwarded["error"]), "error", sys.stderr),
                    file=sys.stderr,
                )
        status = workflow.forwarded["status"] if workflow.forwarded else "success"
        return {"success": 0, "invalid": 2, "unavailable": 3, "conflict": 4}.get(status, 1)
    except (
        Failure,
        OSError,
        ValueError,
        subprocess.CalledProcessError,
        KeyboardInterrupt,
        EOFError,
    ) as error:
        status = getattr(error, "status", "failure")
        if workflow.json:
            print(
                json.dumps(
                    {
                        "status": status,
                        "data": None,
                        "error": str(error) or "Operation interrupted",
                        "taskId": None,
                    }
                )
            )
        else:
            print(
                workflow.paint(plain(str(error) or "Operation interrupted"), "error", sys.stderr),
                file=sys.stderr,
            )
        return {"invalid": 2, "unavailable": 3, "conflict": 4}.get(status, 1)


if __name__ == "__main__":
    raise SystemExit(main())
