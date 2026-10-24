"""A bounded train, checkpoint-check and new-process policy rollout workflow."""

import datetime
import json
import math
from pathlib import Path
import subprocess
import sys

kind = sys.argv[1]
task = {"cartpole": "Isaac-Cartpole-Direct", "quadruped": "Isaac-Velocity-Flat-UnitreeGo2"}[kind]
iterations = 10 if kind == "cartpole" else 50
name = "folio_isaac_validation_" + kind
stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%f")
experiment = Path("logs/rsl_rl") / name
subprocess.run(
    [
        "uv",
        "run",
        "--no-sync",
        "isaaclab",
        "train",
        "--rl_library",
        "rsl_rl",
        "--task",
        task,
        "--num_envs",
        "64",
        "--max_iterations",
        str(iterations),
        "--seed",
        "42",
        "--viz",
        "none",
        "--experiment_name",
        name,
        "--run_name",
        stamp,
        "--logger",
        "tensorboard",
        "physics=isaacsim_physx",
        "agent.save_interval=5",
    ],
    check=True,
)
runs = list(experiment.glob("*" + stamp))
assert len(runs) == 1, runs
checkpoints = list(runs[0].glob("model_*.pt"))
assert checkpoints, "Training did not save a checkpoint"
checkpoint = max(checkpoints, key=lambda item: int(item.stem.split("_")[-1])).resolve()
subprocess.run(
    [sys.executable, str(Path(__file__).with_name("checkpoint.py")), str(checkpoint)], check=True
)
output = runs[0].resolve() / "playback_validation"
subprocess.run(
    [
        sys.executable,
        str(Path(__file__).with_name("playback.py")),
        "--task",
        task,
        "--checkpoint",
        str(checkpoint),
        "--output",
        str(output / "rollout.json"),
    ],
    check=True,
)
results = list(output.glob("*.json"))
assert results, "Playback did not produce metrics"


def finite(value):
    if isinstance(value, float):
        assert math.isfinite(value), "Non-finite playback metric"
    elif isinstance(value, dict):
        for child in value.values():
            finite(child)
    elif isinstance(value, list):
        for child in value:
            finite(child)


for result in results:
    finite(json.loads(result.read_text()))
print(
    json.dumps(
        {
            "stage": kind,
            "status": "passed",
            "task": task,
            "backend": "isaacsim_physx",
            "iterations": iterations,
            "checkpoint": str(checkpoint),
            "playbackSteps": 1200,
            "metrics": [str(result) for result in results],
        }
    ),
    flush=True,
)
