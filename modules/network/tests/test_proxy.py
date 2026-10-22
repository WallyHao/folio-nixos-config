"""Controller routing for subscription nodes without changing proxy selections."""
import importlib.util
import json
import os
from urllib.parse import quote

import pytest

spec = importlib.util.spec_from_file_location("proxy_backend", os.environ["FOLIO_PROXY_SOURCE"])
proxy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proxy)


class Response:
    def __init__(self, status, body):
        self.status = status
        self.body = json.dumps(body).encode()

    def read(self, limit):
        return self.body[:limit]


def controller(monkeypatch, responses):
    calls = []
    class Connection:
        def request(self, *args):
            calls.append(args)
        def getresponse(self):
            return responses.pop(0)
        def close(self):
            pass
    monkeypatch.setattr(proxy, "Controller", Connection)
    return calls


def test_provider_node_latency_uses_provider_route(monkeypatch):
    node, provider = "🇯🇵 日本 | IEPL", "我的订阅"
    calls = controller(monkeypatch, [Response(404, {}), Response(200, {"providers": {
        provider: {"proxies": [{"name": node}]}}}), Response(200, {"delay": 37})])
    assert proxy.execute({"action": "proxy-delay", "node": node}) == {"node": node, "delay": 37}
    assert calls[1] == ("GET", "/providers/proxies")
    assert calls[2][1].startswith("/providers/proxies/" + quote(provider, safe="") + "/" + quote(node, safe="") + "/healthcheck?")
    assert all(call[0] == "GET" for call in calls)


def test_static_proxy_latency_needs_no_provider_lookup(monkeypatch):
    calls = controller(monkeypatch, [Response(200, {"delay": 84})])
    assert proxy.execute({"action": "proxy-delay", "node": "DIRECT"})["delay"] == 84
    assert len(calls) == 1


def test_unknown_node_is_not_tested_or_selected(monkeypatch):
    calls = controller(monkeypatch, [Response(404, {}), Response(200, {"providers": {}})])
    with pytest.raises(ValueError):
        proxy.execute({"action": "proxy-delay", "node": "missing"})
    assert len(calls) == 2
