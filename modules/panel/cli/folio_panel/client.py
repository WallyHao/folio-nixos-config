"""Typed module clients. Secrets travel on stdin, never argv or log messages."""

import asyncio
import json
import tempfile
from pathlib import Path

from . import paths


class BackendError(Exception):
    def __init__(self, message, status="unavailable"):
        super().__init__(message)
        self.status = status


async def process(arguments, request=None, timeout=65):
    child = await asyncio.create_subprocess_exec(
        *arguments,
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
    )
    try:
        output, _ = await asyncio.wait_for(
            child.communicate(
                json.dumps(request).encode() if request is not None else None
            ),
            timeout,
        )
        if len(output) > 2 * 1024 * 1024:
            raise BackendError("Backend response is too large")
        return json.loads(output)
    except (TimeoutError, ValueError):
        raise BackendError(
            "Backend timed out or returned an invalid response"
        ) from None
    finally:
        if child.returncode is None:
            child.kill()
            await child.wait()


def result(reply):
    if not isinstance(reply, dict) or reply.get("status") != "success":
        message = reply.get("error") if isinstance(reply, dict) else None
        raise BackendError(message or "Backend rejected the operation")
    return reply["data"]


class Client:
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
            request.write_text(json.dumps({root: {"action": action, **fields}}))
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
