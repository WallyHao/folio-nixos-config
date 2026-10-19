#!/usr/bin/env python3
"""Exercise the real OBS websocket in a disposable, loopback-only test guest."""
import base64
import hashlib
import io
import json
import os
from pathlib import Path
import sys

from PIL import Image
import websocket

for key in ("http_proxy", "https_proxy", "all_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY"):
    os.environ.pop(key, None)
connection = websocket.create_connection("ws://127.0.0.1:4455", timeout=10)
hello = json.loads(connection.recv())
assert hello["op"] == 0
assert "authentication" not in hello["d"], "Disposable OBS test websocket must have authentication disabled"
connection.send(json.dumps({"op": 1, "d": {"rpcVersion": 1, "eventSubscriptions": 0}}))
assert json.loads(connection.recv())["op"] == 2
sequence = 0


def request(name, data=None):
    global sequence
    sequence += 1
    identity = f"folio-test-{sequence}"
    connection.send(json.dumps({"op": 6, "d": {"requestType": name, "requestId": identity, "requestData": data or {}}}))
    while True:
        message = json.loads(connection.recv())
        if message["op"] != 7 or message["d"]["requestId"] != identity:
            continue
        response = message["d"]
        assert response["requestStatus"]["result"], (name, response["requestStatus"])
        return response.get("responseData", {})


mode = sys.argv[1]
if mode == "probe":
    version = request("GetVersion")
    print(json.dumps({"version": {key: version[key] for key in ("obsVersion", "obsWebSocketVersion", "rpcVersion")},
        "pipewireKinds": [kind for kind in request("GetInputKindList")["inputKinds"] if "pipewire" in kind]}))
elif mode == "create":
    scene = "Folio acceptance capture"
    name = "Folio acceptance screen"
    kinds = request("GetInputKindList")["inputKinds"]
    candidates = [kind for kind in kinds if kind.startswith("pipewire") and "capture" in kind and "audio" not in kind]
    assert candidates, kinds
    kind = next((kind for kind in candidates if "desktop" in kind or "screen" in kind), candidates[0])
    scenes = request("GetSceneList")["scenes"]
    if not any(entry["sceneName"] == scene for entry in scenes):
        request("CreateScene", {"sceneName": scene})
    request("SetCurrentProgramScene", {"sceneName": scene})
    inputs = request("GetInputList")["inputs"]
    if not any(entry["inputName"] == name for entry in inputs):
        request("CreateInput", {"sceneName": scene, "inputName": name, "inputKind": kind,
            "inputSettings": {}, "sceneItemEnabled": True})
    print(json.dumps({"scene": scene, "input": name, "kind": kind}))
elif mode == "properties":
    request("OpenInputPropertiesDialog", {"inputName": "Folio acceptance screen"})
elif mode == "snapshot":
    result = request("GetSourceScreenshot", {"sourceName": "Folio acceptance screen",
        "imageFormat": "png", "imageWidth": 640, "imageHeight": 400})
    raw = base64.b64decode(result["imageData"].split(",", 1)[1], validate=True)
    image = Image.open(io.BytesIO(raw)).convert("RGB")
    colors = len(image.getcolors(maxcolors=image.width * image.height) or [])
    Path(sys.argv[2]).write_bytes(raw)
    print(json.dumps({"width": image.width, "height": image.height, "colors": colors,
        "sha256": hashlib.sha256(image.tobytes()).hexdigest()}))
else:
    raise SystemExit("Expected probe, create or snapshot PATH")
connection.close()
