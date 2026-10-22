"""Private Mihomo controller operations; invoked by the authorized subscriber."""

import http.client
import json
import socket
import sys
from contextlib import closing
from urllib.parse import quote


class Controller(http.client.HTTPConnection):
    def __init__(self):
        super().__init__("localhost", timeout=4)

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect("/run/folio-mihomo/controller.sock")


def execute(request):
    with closing(Controller()) as connection:
        if request["action"] == "proxy-groups":
            connection.request("GET", "/proxies")
        elif request["action"] == "proxy-delay":
            node = request.get("node")
            if not isinstance(node, str) or not 1 <= len(node) <= 256:
                raise ValueError("Select a proxy node")
            # Fixed public test target: never accept arbitrary URLs from callers.
            connection.request(
                "GET",
                "/proxies/"
                + quote(node, safe="")
                + "/delay?timeout=2000&url="
                + quote("https://www.gstatic.com/generate_204", safe=""),
            )
        elif request["action"] == "proxy-group-select":
            group, node = request.get("group"), request.get("node")
            if not all(
                isinstance(value, str) and 1 <= len(value) <= 256
                for value in (group, node)
            ):
                raise ValueError("Select a proxy group and node")
            connection.request(
                "PUT",
                "/proxies/" + quote(group, safe=""),
                json.dumps({"name": node}),
                {"Content-Type": "application/json"},
            )
        else:
            raise ValueError("Unsupported proxy query")
        response = connection.getresponse()
        body = response.read(1024 * 1024 + 1)
        if request["action"] == "proxy-delay" and response.status == 404:
            # Provider nodes are absent from Mihomo's top-level /proxies map.
            # Resolve the provider internally; callers still supply only a node name.
            connection.request("GET", "/providers/proxies")
            provider_response = connection.getresponse()
            provider_body = provider_response.read(1024 * 1024 + 1)
            if provider_response.status != 200 or len(provider_body) > 1024 * 1024:
                raise OSError("Proxy provider inventory unavailable")
            providers = json.loads(provider_body).get("providers", {})
            provider = next((name for name, entry in providers.items()
                             if any(proxy.get("name") == node for proxy in entry.get("proxies", []))), None)
            if provider is None:
                raise ValueError("Unknown provider node")
            connection.request("GET", "/providers/proxies/" + quote(provider, safe="")
                               + "/" + quote(node, safe="") + "/healthcheck?timeout=2000&url="
                               + quote("https://www.gstatic.com/generate_204", safe=""))
            response = connection.getresponse()
            body = response.read(1024 * 1024 + 1)
        if response.status not in (200, 204) or len(body) > 1024 * 1024:
            raise OSError("Proxy query failed or timed out")
        if request["action"] == "proxy-group-select":
            return {"group": group, "selected": node}
        data = json.loads(body)
    if request["action"] == "proxy-groups":
        groups = [
            {
                "name": name,
                "type": entry.get("type"),
                "selected": entry.get("now"),
                "nodes": entry.get("all", []),
            }
            for name, entry in data.get("proxies", {}).items()
            if entry.get("type") == "Selector"
        ]
        return {"groups": groups}
    return {"node": request["node"], "delay": data["delay"]}


def main():
    try:
        request = json.load(sys.stdin)
        result = {
            "status": "success",
            "data": execute(request),
            "error": None,
            "taskId": None,
        }
        code = 0
    except (OSError, ValueError, KeyError, http.client.HTTPException):
        result = {
            "status": "unavailable",
            "data": None,
            "error": "Mihomo query is unavailable or the test timed out",
            "taskId": None,
        }
        code = 3
    json.dump(result, sys.stdout)
    return code


if __name__ == "__main__":
    sys.exit(main())
