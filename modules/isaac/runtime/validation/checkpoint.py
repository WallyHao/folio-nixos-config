"""Validate a locally produced, trusted checkpoint and its TensorBoard scalars."""
import argparse
import json
import math
from pathlib import Path

import torch
from tensorboard.backend.event_processing.event_accumulator import EventAccumulator

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("checkpoint", type=Path)
args = parser.parse_args()
checkpoint = torch.load(args.checkpoint, map_location="cpu", weights_only=False)
count = 0


def inspect(value):
    global count
    if isinstance(value, torch.Tensor):
        assert torch.isfinite(value).all().item(), "Non-finite checkpoint tensor"
        count += 1
    elif isinstance(value, dict):
        for child in value.values():
            inspect(child)
    elif isinstance(value, (list, tuple)):
        for child in value:
            inspect(child)


inspect(checkpoint)
assert count > 0
events = EventAccumulator(str(args.checkpoint.parent)).Reload()
tags = events.Tags()["scalars"]
assert tags, "No training scalars recorded"
for tag in tags:
    assert all(math.isfinite(event.value) for event in events.Scalars(tag)), tag
print(json.dumps({"stage": "checkpoint", "status": "passed", "checkpoint": str(args.checkpoint),
                  "tensorCount": count, "scalarTags": tags, "iteration": checkpoint.get("iter")}))
