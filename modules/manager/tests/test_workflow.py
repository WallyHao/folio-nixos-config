"""Exercise the real workflow entry point across isolated subprocess adapters."""

import json
import os
from pathlib import Path
import pty
import re
import select
import subprocess
import sys
import tempfile
import time
import unittest

workflow = Path(os.environ["WORKFLOW_COMMAND"])
adapter = Path(os.environ["WORKFLOW_ADAPTER"])


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="folio-workflow-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        (self.source / "modules").mkdir(parents=True)
        (self.source / "flake.nix").write_text("{}")
        (self.source / "flake.lock").write_text("{}")
        (self.source / "modules/sample.txt").write_text("reviewed bytes")
        binary = self.root / "bin"
        binary.mkdir()
        for name, code in {
            "adapter": f'import runpy; runpy.run_path({str(adapter)!r}, run_name="__main__")',
            "nix": 'import tempfile, shutil, sys, os; p=tempfile.mkdtemp(dir=os.environ["WORKFLOW_FIXTURE"]); shutil.copytree(sys.argv[-1], p+"/source"); print(p+"/source")',
            "nix-store": "pass",
            "sudo": "import os, sys; os.execvpe(sys.argv[1], sys.argv[1:], os.environ)",
        }.items():
            file = binary / name
            file.write_text(f"#!{sys.executable}\n" + code + "\n")
            file.chmod(0o700)
        self.env = os.environ | {
            "WORKFLOW_FIXTURE": str(self.root),
            "XDG_STATE_HOME": str(self.root / "state"),
            "FOLIO_DEPLOY_ADAPTER": str(binary / "adapter"),
            "FOLIO_MAINTENANCE_ADAPTER": str(binary / "adapter"),
            "FOLIO_JSON": "true",
            "FOLIO_NO_WAIT": "false",
            "PATH": str(binary) + ":" + os.environ["PATH"],
        }
        state = {"calls": []}
        for scope in ("system", "user"):
            current = {
                "revisionId": f"baseline-{scope}",
                "artifact": f"/nix/store/{scope}-0",
                "configurationDigest": f"{scope}-config-0",
                "version": 0,
            }
            state[scope] = {
                "version": 1,
                "drafts": {},
                "plans": {},
                "current": current,
                "revisions": {current["revisionId"]: current},
            }
        self.write(state)

    def read(self):
        return json.loads((self.root / "state.json").read_text())

    def write(self, state):
        (self.root / "state.json").write_text(json.dumps(state))

    def run_cli(self, *args, code=0, env=None):
        result = subprocess.run(
            [sys.executable, str(workflow), *args],
            env=env or self.env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, code, result.stderr + result.stdout)
        return json.loads(result.stdout)

    def plan(self, comment="Reviewed change"):
        return self.run_cli("plan", "--source", str(self.source), "--yes", "--comment", comment)[
            "data"
        ]["planId"]

    def terminal_output(self, *args, extra_env=None):
        master, slave = pty.openpty()
        process = subprocess.Popen(
            [sys.executable, str(workflow), *args],
            env=self.env | {"FOLIO_JSON": "false", "TERM": "xterm-256color"} | (extra_env or {}),
            stdin=subprocess.DEVNULL,
            stdout=slave,
            stderr=subprocess.PIPE,
        )
        os.close(slave)
        output = bytearray()
        try:
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                ready, _, _ = select.select([master], [], [], 0.1)
                if ready:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError:
                        break
                    if not chunk:
                        break
                    output.extend(chunk)
            self.assertEqual(process.wait(timeout=5), 0, process.stderr.read().decode())
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stderr.close()
            os.close(master)
        return output.decode().replace("\r\n", "\n")

    def test_terminal_colors_and_copyable_next_commands(self):
        env = self.env.copy()
        env.pop("NO_COLOR", None)
        self.env = env
        output = self.terminal_output(
            "plan", "--source", str(self.source), "--yes", "--comment", "Colors"
        )
        self.assertIn("\033[", output)
        text = re.sub(r"\x1b\[[0-9;]*m", "", output)
        identifier = re.search(r"Created plan: ([a-f0-9]{64})", text)[1]
        self.assertIn(f"\nNext command:\nfolio build {identifier}\n", text)
        output = self.terminal_output("build", identifier)
        self.assertIn("\033[", output)
        text = re.sub(r"\x1b\[[0-9;]*m", "", output)
        self.assertIn(f"\nNext command:\nfolio apply {identifier}\n", text)
        output = self.terminal_output("apply", identifier)
        self.assertIn("\033[1;32m", output)
        self.assertNotIn("Next command:", output)
        for extra in ({"NO_COLOR": "1"}, {"TERM": "dumb"}):
            output = self.terminal_output("build", identifier, extra_env=extra)
            self.assertNotIn("\033[", output)
            self.assertIn(f"\nfolio apply {identifier}\n", output)

    def test_redirected_and_json_output_stay_plain(self):
        identifier = self.plan()
        result = subprocess.run(
            [sys.executable, str(workflow), "build", identifier],
            env=self.env | {"FOLIO_JSON": "false"},
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("\033[", result.stdout + result.stderr)
        self.assertIn(f"\nfolio apply {identifier}\n", result.stdout)
        result = subprocess.run(
            [sys.executable, str(workflow), "build", identifier],
            env=self.env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(json.loads(result.stdout)["status"], "success")
        self.assertNotIn("\033[", result.stdout + result.stderr)
        result = subprocess.run(
            [sys.executable, str(workflow), "build", identifier],
            env=self.env | {"FOLIO_JSON": "false", "FOLIO_NO_WAIT": "true"},
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("folio apply", result.stdout)

    def test_snapshot_comment_and_complete_unchanged_scope(self):
        state = self.read()
        state["system"]["editSourceAfterPreview"] = True
        state["system"]["version"] = 0
        self.write(state)
        identifier = self.plan("Useful comment")
        manifest = json.loads(
            (
                self.root / "state/folio/deployments/workflows/plans" / f"{identifier}.json"
            ).read_text()
        )
        self.assertEqual(manifest["comment"], "Useful comment")
        self.assertEqual(set(manifest["components"]), {"system", "user"})
        self.assertFalse(manifest["components"]["system"]["changed"])
        self.assertEqual(manifest["components"]["system"]["restoreId"], "baseline-system")
        self.assertTrue(
            all(
                c["plan"]["sourceText"] == "reviewed bytes" for c in manifest["components"].values()
            )
        )
        self.assertTrue(all(not self.read()[s]["drafts"] for s in ("system", "user")))

    def test_no_change_does_not_create_plan(self):
        state = self.read()
        for scope in ("system", "user"):
            state[scope]["version"] = 0
        self.write(state)
        self.assertIsNone(self.plan())
        self.assertFalse((self.root / "state/folio/deployments/workflows/plans").exists())
        self.assertTrue(all(not self.read()[s]["drafts"] for s in ("system", "user")))

    def test_missing_scope_and_stale_review_fail_closed(self):
        state = self.read()
        state["system"]["unavailable"] = True
        self.write(state)
        self.run_cli("plan", "--source", str(self.source), "--yes", "--comment", "x", code=3)
        state["system"]["unavailable"] = False
        state["system"]["staleOnConfirm"] = True
        self.write(state)
        self.run_cli("plan", "--source", str(self.source), "--yes", "--comment", "x", code=4)
        self.assertFalse(self.read()["system"]["plans"])

    def test_build_gate_partial_failure_retry_and_rollback(self):
        first = self.plan("First version")
        self.run_cli("apply", first, code=3)
        self.assertFalse(any(call[1] == "apply" for call in self.read()["calls"]))
        self.run_cli("rollback", first, "--yes", code=2)
        self.run_cli("build", first)
        state = self.read()
        state["user"]["fail"] = "apply"
        self.write(state)
        self.run_cli("apply", first, code=1)
        history = self.run_cli("history")["data"]["plans"][0]
        self.assertEqual(history["status"], "apply:failed")
        state = self.read()
        state["user"].pop("fail")
        self.write(state)
        self.run_cli("apply", first)
        state = self.read()
        for scope in ("system", "user"):
            state[scope]["version"] = 2
        self.write(state)
        second = self.plan("Second version")
        self.run_cli("build", second)
        self.run_cli("apply", second)
        self.run_cli("rollback", first, "--yes")
        state = self.read()
        self.assertTrue(all(state[s]["current"]["version"] == 1 for s in ("system", "user")))
        history = self.run_cli("history")["data"]["plans"]
        self.assertEqual(len(history), 2)
        self.assertTrue(
            any(
                e["operation"] == "rollback" and e["phase"] == "succeeded"
                for p in history
                for e in p["executions"]
            )
        )

    def test_tampering_and_drift_are_rejected(self):
        state = self.read()
        state["system"]["version"] = 0
        self.write(state)
        identifier = self.plan()
        self.run_cli("build", identifier)
        state = self.read()
        state["system"]["version"] = 3
        self.write(state)
        self.run_cli("apply", identifier, code=4)
        self.assertFalse(any(call[1] == "apply" for call in self.read()["calls"]))
        file = self.root / "state/folio/deployments/workflows/plans" / f"{identifier}.json"
        manifest = json.loads(file.read_text())
        manifest["comment"] = "tampered"
        file.write_text(json.dumps(manifest))
        self.run_cli("build", identifier, code=4)

    def test_stale_user_blocks_system_activation(self):
        identifier = self.plan()
        self.run_cli("build", identifier)
        state = self.read()
        state["user"]["version"] = 2
        self.write(state)
        self.run_cli("apply", identifier, code=4)
        self.assertFalse(any(call[1] == "apply" for call in self.read()["calls"]))

    def test_noninteractive_requires_explicit_creation(self):
        self.run_cli("plan", "--source", str(self.source), code=2)
        self.run_cli("plan", "--source", str(self.source), "--yes", code=2)
        self.assertFalse(self.read()["calls"])

    def test_background_history_and_interrupted_coordinator(self):
        identifier = self.plan()
        result = self.run_cli("build", identifier, env=self.env | {"FOLIO_NO_WAIT": "true"})
        self.assertEqual(result["data"]["phase"], "submitted")
        self.assertTrue(all(step["taskId"] for step in result["data"]["steps"]))
        history = self.run_cli("history")["data"]["plans"][0]
        self.assertEqual(history["status"], "build:succeeded")
        event_path = next(
            (self.root / "state/folio/deployments/workflows/executions" / identifier).glob("*.json")
        )
        event = json.loads(event_path.read_text())
        event.update(phase="running", coordinator={"pid": 999999999, "start": "0", "boot": "old"})
        event["steps"] = event["steps"][:1]
        event_path.write_text(json.dumps(event))
        history = self.run_cli("history")["data"]["plans"][0]
        self.assertEqual(history["status"], "build:interrupted")

    def durable_environment(self):
        wrapper = self.root / "bin/workflow"
        wrapper.write_text(
            f"#!{sys.executable}\nimport os, sys; os.execv(sys.executable, [sys.executable, {str(workflow)!r}, *sys.argv[1:]])\n"
        )
        wrapper.chmod(0o700)
        runner = self.root / "bin/systemd-run"
        runner.write_text(
            f"#!{sys.executable}\n"
            + """
import os, subprocess, sys
if os.environ.get('WORKFLOW_DISPATCH_FAIL'): sys.exit(1)
position = sys.argv.index('--worker') - 1
subprocess.Popen(sys.argv[position:], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                 stderr=subprocess.DEVNULL, start_new_session=True)
"""
        )
        runner.chmod(0o700)
        control = self.root / "bin/systemctl"
        control.write_text(f"#!{sys.executable}\nraise SystemExit(3)\n")
        control.chmod(0o700)
        return self.env | {"FOLIO_WORKFLOW_EXECUTABLE": str(wrapper)}

    def test_durable_apply_survives_client_exit_and_rejects_request_reuse(self):
        identifier = self.plan()
        self.run_cli("build", identifier)
        env = self.durable_environment() | {"WORKFLOW_DELAY": "0.6"}
        process = subprocess.Popen(
            [
                sys.executable,
                str(workflow),
                "apply",
                identifier,
                "--request-id",
                "client-disconnect",
            ],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        jobs = self.root / "state/folio/deployments/workflows/jobs"
        deadline = time.monotonic() + 10
        while not list(jobs.glob("w-*.json")) and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertTrue(list(jobs.glob("w-*.json")))
        process.terminate()
        process.wait(timeout=5)
        job_id = next(jobs.glob("w-*.json")).stem
        while time.monotonic() < deadline:
            job = self.run_cli("status", job_id)["data"]
            if job["phase"] in {"succeeded", "failed"}:
                break
            time.sleep(0.05)
        self.assertEqual(job["phase"], "succeeded", job)
        self.assertTrue(
            all(self.read()[scope]["current"]["version"] == 1 for scope in ("system", "user"))
        )
        again = self.run_cli("apply", identifier, "--request-id", "client-disconnect", env=env)
        self.assertEqual(again["data"]["id"], job_id)
        self.run_cli("build", identifier, "--request-id", "client-disconnect", env=env, code=4)

    def test_queued_workflow_can_resume_after_dispatch_failure(self):
        identifier = self.plan()
        env = self.durable_environment()
        self.run_cli(
            "build",
            identifier,
            "--request-id",
            "retry-dispatch",
            env=env | {"WORKFLOW_DISPATCH_FAIL": "1"},
            code=3,
        )
        job_id = next((self.root / "state/folio/deployments/workflows/jobs").glob("*.json")).stem
        self.assertEqual(self.run_cli("status", job_id)["data"]["phase"], "queued")
        result = self.run_cli("resume", job_id, env=env)
        self.assertEqual(result["data"]["phase"], "succeeded")

    def test_partial_history_and_read_only_diagnostics(self):
        identifier = self.plan()
        state = self.read()
        state["system"]["unavailable"] = True
        self.write(state)
        history = self.run_cli("history")["data"]
        self.assertEqual(history["plans"][0]["planId"], identifier)
        self.assertTrue(history["scopedHistory"]["system"]["unavailable"])
        doctor = self.run_cli("doctor")["data"]
        self.assertEqual(doctor["health"], "degraded")
        self.assertTrue(any(f["code"] == "backend-unavailable" for f in doctor["findings"]))
        self.assertFalse(any(c[1] in ("apply", "rollback") for c in self.read()["calls"]))

    def test_resume_retries_failed_worker_only_after_effect_recovery(self):
        identifier = self.plan()
        self.run_cli("build", identifier)
        state = self.read()
        state["user"]["failTask"] = "apply"
        self.write(state)
        env = self.durable_environment()
        failed = self.run_cli("apply", identifier, env=env, code=1)["data"]
        state = self.read()
        failed_task = next(t for t in state["user"]["tasks"].values() if t["phase"] == "failed")
        failed_task["recoveryRequired"] = True
        state["user"].pop("failTask")
        self.write(state)
        apply_calls = sum(c[1] == "apply" for c in state["calls"])
        self.run_cli("resume", failed["id"], env=env, code=4)
        state = self.read()
        self.assertEqual(sum(c[1] == "apply" for c in state["calls"]), apply_calls)
        for task in state["user"]["tasks"].values():
            task["recoveryRequired"] = False
        self.write(state)
        resumed = self.run_cli("resume", failed["id"], env=env)["data"]
        self.assertEqual(resumed["phase"], "succeeded")
        self.assertTrue(
            all(self.read()[scope]["current"]["version"] == 1 for scope in ("system", "user"))
        )

    def test_resume_observes_previous_live_task_before_retry(self):
        identifier = self.plan()
        self.run_cli("build", identifier)
        state = self.read()
        state["user"]["failTask"] = "apply"
        self.write(state)
        env = self.durable_environment()
        job = self.run_cli("apply", identifier, env=env, code=1)["data"]
        state = self.read()
        state["user"].pop("failTask")
        task = next(t for t in state["user"]["tasks"].values() if t["phase"] == "failed")
        task.update(phase="running", polls=3)
        self.write(state)
        result = self.run_cli("resume", job["id"], env=env)["data"]
        self.assertEqual(result["phase"], "succeeded")
        self.assertTrue(
            all(t["phase"] == "succeeded" for t in self.read()["user"]["tasks"].values())
        )

    def test_resume_recovers_an_accepted_task_receipt_with_the_original_request(self):
        identifier = self.plan()
        self.run_cli("build", identifier)
        state = self.read()
        state["user"]["failTask"] = "apply"
        self.write(state)
        env = self.durable_environment()
        job = self.run_cli("apply", identifier, env=env, code=1)["data"]
        state = self.read()
        state["user"].pop("failTask")
        for task in state["user"]["tasks"].values():
            if task["phase"] == "failed":
                task.update(phase="running", polls=2)
        self.write(state)
        events = self.root / "state/folio/deployments/workflows/executions" / identifier
        event_path = next(
            p
            for p in events.glob("*.json")
            if json.loads(p.read_text()).get("workflowId") == job["id"]
        )
        event = json.loads(event_path.read_text())
        step = next(s for s in event["steps"] if s["scope"] == "user")
        original_task = step.pop("taskId")
        step["phase"] = "running"
        event_path.write_text(json.dumps(event))
        self.assertEqual(self.run_cli("resume", job["id"], env=env)["data"]["phase"], "succeeded")
        recovered = json.loads(event_path.read_text())
        self.assertEqual(
            next(s for s in recovered["steps"] if s["scope"] == "user")["taskId"], original_task
        )

    def test_legacy_task_envelope_is_preserved(self):
        identifier = "a" * 64
        state = self.read()
        state["user"]["plans"][identifier] = {"status": "planned", "comment": "legacy"}
        self.write(state)
        result = self.run_cli("build", identifier, env=self.env | {"FOLIO_NO_WAIT": "true"})
        self.assertIsNotNone(result["taskId"])
        self.assertIsNone(result["data"])
        state = self.read()
        state["user"]["fail"] = "build"
        self.write(state)
        result = self.run_cli("build", identifier, code=1)
        self.assertEqual(result["data"]["reason"], "injected failure")
        self.assertEqual(result["error"], "Injected build failure")

    def test_doctor_does_not_treat_recovered_application_history_as_pending(self):
        identifier = self.plan()
        self.run_cli("build", identifier)
        self.run_cli("apply", identifier)
        tasks = self.root / "state/folio/applications/tasks"
        tasks.mkdir(parents=True)
        (tasks / "old.json").write_text(
            json.dumps({"id": "old", "phase": "failed", "createdAt": "1"})
        )
        (tasks / "new.json").write_text(
            json.dumps({"id": "new", "phase": "succeeded", "createdAt": "2"})
        )
        self.assertEqual(self.run_cli("doctor")["data"]["health"], "healthy")
        (tasks / "old.json").write_text(
            json.dumps({"id": "old", "phase": "failed", "createdAt": "1", "recoveryRequired": True})
        )
        report = self.run_cli("doctor")["data"]
        self.assertTrue(
            any(f["code"] == "application-task-needs-attention" for f in report["findings"])
        )

    def test_cancel_in_terminal_discards_drafts(self):
        master, slave = pty.openpty()
        process = subprocess.Popen(
            [sys.executable, str(workflow), "plan", "--source", str(self.source)],
            env=self.env | {"FOLIO_JSON": "false"},
            stdin=slave,
            stdout=slave,
            stderr=slave,
        )
        os.close(slave)
        output = bytearray()
        deadline = time.monotonic() + 15
        try:
            while time.monotonic() < deadline:
                ready, _, _ = select.select([master], [], [], 0.1)
                if not ready:
                    continue
                output.extend(os.read(master, 65536))
                if b"Create this deployment plan?" in output:
                    os.write(master, b"n\n")
                    break
            else:
                self.fail("Confirmation prompt not shown")
            self.assertEqual(process.wait(timeout=10), 0)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
        self.assertTrue(all(not self.read()[s]["drafts"] for s in ("system", "user")))
        self.assertFalse(any(self.read()[s]["plans"] for s in ("system", "user")))


if __name__ == "__main__":
    unittest.main()
