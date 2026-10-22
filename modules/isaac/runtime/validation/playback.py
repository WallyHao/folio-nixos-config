"""Run the upstream RSL-RL playback entrypoint with a finite, checked rollout loop."""
import argparse
import json
from pathlib import Path

import torch

from isaaclab_rl.entrypoints import common

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--task", required=True)
parser.add_argument("--checkpoint", required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
stats = {"steps": 0, "completedEpisodes": 0, "rewardSum": 0.0}
original_create = common.create_isaaclab_env


def finite(value):
    if isinstance(value, torch.Tensor):
        assert torch.isfinite(value).all().item(), "Non-finite rollout tensor"
    elif isinstance(value, dict) or hasattr(value, "items"):
        for _, child in value.items():
            finite(child)
    elif isinstance(value, (list, tuple)):
        for child in value:
            finite(child)


def checked_environment(*positional, **keywords):
    env = original_create(*positional, **keywords)
    original_step = env.step

    def step(actions):
        finite(actions)
        result = original_step(actions)
        obs, reward, terminated, truncated, _ = result
        finite(obs)
        finite(reward)
        stats["steps"] += 1
        stats["rewardSum"] += float(reward.sum().item())
        stats["completedEpisodes"] += int((terminated | truncated).sum().item())
        return result

    env.step = step
    return env


def bounded_loop(step, *, dt, args_cli, env_cfg):
    with torch.inference_mode():
        for _ in range(1200):
            step()
    assert stats["steps"] == 1200, stats
    assert stats["completedEpisodes"] > 0, stats
    result = {"stage": "rollout", "status": "passed", "task": args.task,
              "checkpoint": args.checkpoint, "backend": "isaacsim_physx", **stats}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result), flush=True)


# Patch only this validation process, before the lazily loaded playback backend
# imports these functions. The policy, checkpoint loader and environment are the
# upstream implementations; the test supplies a finite loop and numeric checks.
common.create_isaaclab_env = checked_environment
common.run_playback = bounded_loop
from isaaclab_rl.entrypoints import run_play_cli

code = run_play_cli(["--rl_library", "rsl_rl", "--task", args.task, "--checkpoint", args.checkpoint,
                     "--num_envs", "4", "--seed", "42", "--viz", "none", "physics=isaacsim_physx"])
if code:
    raise SystemExit(code)
assert args.output.exists(), "Playback returned without completing its rollout"
