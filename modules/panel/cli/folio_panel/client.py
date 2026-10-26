"""Typed module clients. Secrets travel on stdin, never argv or log messages."""

import asyncio
import json
import tempfile
from pathlib import Path

from . import paths


class BackendError(Exception):
    def __init__(self, message, status="unavailable", code="backend-unavailable"):
        super().__init__(message)
        self.status = status
        self.code = code


async def process(arguments, request=None, timeout=65):
    child = await asyncio.create_subprocess_exec(
        *arguments,
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
    )
    try:
        output, _ = await asyncio.wait_for(
            child.communicate(json.dumps(request).encode() if request is not None else None),
            timeout,
        )
        if len(output) > 2 * 1024 * 1024:
            raise BackendError("Backend response is too large")
        return json.loads(output)
    except TimeoutError:
        raise BackendError("Backend timed out", code="backend-timeout") from None
    except ValueError:
        raise BackendError("Backend timed out or returned an invalid response") from None
    finally:
        if child.returncode is None:
            child.kill()
            await child.wait()


def result(reply):
    if not isinstance(reply, dict) or reply.get("status") != "success":
        message = reply.get("error") if isinstance(reply, dict) else None
        status = reply.get("status", "unavailable") if isinstance(reply, dict) else "unavailable"
        code = {"conflict": "configuration-conflict", "invalid": "invalid-configuration"}.get(
            status, "backend-unavailable"
        )
        raise BackendError(message or "Backend rejected the operation", status, code)
    return reply["data"]


class Client:
    async def settings(self):
        data = result(await process([paths.LEGACY, "--json", "config", "show"]))
        preferences = {
            key: value
            for key, value in data["configuration"]["folio-environment:environment"]
            .get("preferences", {})
            .items()
            if key not in {"scheme", "appearance"}
        }
        resolved = data["preferences"]
        labels = {
            "user-configuration": "user override",
            "system-configuration": "system setting",
            "system-default": "system default",
            "bootstrap-default": "bootstrap default",
        }
        return {
            "digest": data["digest"],
            "preferences": preferences,
            "defaults": resolved["defaults"],
            "effective": resolved["values"],
            "deployment": data["deployment"],
            "origins": {
                key: labels.get(origin, origin) for key, origin in resolved["origins"].items()
            },
        }

    async def save_settings(self, digest, preferences):
        # The full desired document stays private; the API exposes public preferences only.
        data = result(await process([paths.LEGACY, "--json", "config", "show"]))
        if data["digest"] != digest:
            raise BackendError(
                "Configuration changed. Reload settings before saving.",
                "conflict",
                "configuration-conflict",
            )
        document = data["configuration"]
        target = document["folio-environment:environment"].setdefault("preferences", {})
        for key, value in preferences.items():
            if key not in {"font-family", "font-size"}:
                raise BackendError(
                    "Theme selection is system-wide. Use folio theme set.",
                    "invalid",
                    "invalid-configuration",
                )
            if value is None:
                target.pop(key, None)
            else:
                target[key] = value
        with tempfile.TemporaryDirectory(prefix="folio-settings-") as directory:
            path = Path(directory) / "draft.json"
            path.write_text(json.dumps(document, ensure_ascii=False))
            path.chmod(0o600)
            return result(
                await process(
                    [
                        paths.LEGACY,
                        "--json",
                        "config",
                        "import",
                        str(path),
                        "--expected-digest",
                        digest,
                    ]
                )
            )

    async def wifi(self, action="status", **fields):
        return result(await process([paths.WIFI], {"action": action, **fields}))

    async def devices(self, action="status", **fields):
        return result(await process([paths.DEVICES], {"action": action, **fields}))

    async def proxy(self, action, **fields):
        root = (
            "folio-network:execute"
            if action in ("status", "proxy-mode")
            else "folio-network-panel:control"
        )
        # Proxy requests contain names/modes only. Wi-Fi secrets never use this path.
        with tempfile.TemporaryDirectory(prefix="folio-panel-") as directory:
            request = Path(directory, "request.json")
            # libyang rejects escaped UTF-16 surrogate pairs in emoji node names.
            request.write_text(
                json.dumps({root: {"action": action, **fields}}, ensure_ascii=False),
                encoding="utf-8",
            )
            request.chmod(0o600)
            reply = await process(
                [
                    paths.REPOSITORY,
                    "system",
                    "cfg",
                    "--rpc=" + str(request),
                    "--format",
                    "json",
                    "--timeout",
                    "30",
                ],
                timeout=35,
            )
        try:
            record = next(iter(reply.values()))
            if "result-json" not in record:
                raise BackendError(
                    record.get(
                        "error",
                        "Network panel API is unavailable; check installed models and subscriber",
                    )
                )
            return result(json.loads(record["result-json"]))
        except (TypeError, ValueError, StopIteration, KeyError):
            raise BackendError(
                "Network panel API is unavailable; check permissions, installed models and subscriber"
            ) from None
