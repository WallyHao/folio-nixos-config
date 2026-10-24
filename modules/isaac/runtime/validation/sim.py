"""Finite Isaac Sim startup/physics check using a falling cube and ground plane."""

import argparse
import json
from pathlib import Path
import time
from isaacsim import SimulationApp

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--gui", action="store_true")
parser.add_argument("--screenshot", type=Path)
args = parser.parse_args()
app = SimulationApp({"headless": not args.gui, "width": 960, "height": 640})
try:
    import omni.timeline
    import omni.usd
    from isaacsim.core.simulation_manager import SimulationManager
    from isaacsim.core.experimental.prims import RigidPrim
    from pxr import Gf, UsdGeom, UsdLux, UsdPhysics
    import numpy as np

    omni.usd.get_context().new_stage()
    stage = omni.usd.get_context().get_stage()
    UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.z)
    scene = UsdPhysics.Scene.Define(stage, "/World/Physics")
    scene.CreateGravityDirectionAttr(Gf.Vec3f(0, 0, -1))
    scene.CreateGravityMagnitudeAttr(9.81)
    ground = UsdGeom.Cube.Define(stage, "/World/Ground")
    ground.CreateSizeAttr(1.0)
    ground.AddTranslateOp().Set(Gf.Vec3d(0, 0, -0.05))
    ground.AddScaleOp().Set(Gf.Vec3f(10, 10, 0.1))
    UsdPhysics.CollisionAPI.Apply(ground.GetPrim())
    shape = UsdGeom.Cube.Define(stage, "/World/Cube")
    shape.CreateSizeAttr(0.2)
    shape.AddTranslateOp().Set(Gf.Vec3d(0, 0, 1))
    shape.CreateDisplayColorAttr([Gf.Vec3f(0.1, 0.5, 0.9)])
    UsdPhysics.RigidBodyAPI.Apply(shape.GetPrim())
    UsdPhysics.CollisionAPI.Apply(shape.GetPrim())
    UsdPhysics.MassAPI.Apply(shape.GetPrim()).CreateMassAttr(1.0)
    UsdLux.DomeLight.Define(stage, "/World/Light").CreateIntensityAttr(1000.0)
    cube = RigidPrim("/World/Cube")
    if args.gui:
        from omni.kit.viewport.utility import get_active_viewport

        camera = UsdGeom.Camera.Define(stage, "/World/Camera")
        camera.AddTransformOp().Set(
            Gf.Matrix4d()
            .SetLookAt(Gf.Vec3d(2, 2, 1.5), Gf.Vec3d(0, 0, 0.2), Gf.Vec3d(0, 0, 1))
            .GetInverse()
        )
        get_active_viewport().camera_path = "/World/Camera"
    timeline = omni.timeline.get_timeline_interface()
    timeline.play()
    app.update()
    timeline.pause()
    heights = []
    for _ in range(180):
        SimulationManager.step()
        heights.append(float(cube.get_world_poses()[0].numpy()[0, 2]))
        if args.gui:
            app.update()
            time.sleep(1 / 60)
    assert np.isfinite(heights).all()
    assert heights[0] > 0.8 and 0.05 < heights[-1] < 0.2, heights[-10:]
    assert max(heights[-30:]) - min(heights[-30:]) < 0.02
    if args.screenshot:
        from omni.kit.viewport.utility import capture_viewport_to_file, get_active_viewport

        args.screenshot.parent.mkdir(parents=True, exist_ok=True)
        capture_viewport_to_file(get_active_viewport(), str(args.screenshot))
        for _ in range(120):
            app.update()
            if args.screenshot.exists() and args.screenshot.stat().st_size > 0:
                break
        assert args.screenshot.exists(), "Viewport capture did not complete"
        from PIL import Image

        with Image.open(args.screenshot) as frame:
            frame.load()
            pixels = np.asarray(frame.convert("RGB")).reshape(-1, 3)
            assert pixels.std(axis=0).max() > 1, "Viewport capture has no visible content"
    print(
        json.dumps(
            {
                "stage": "gui" if args.gui else "sim",
                "status": "passed",
                "steps": len(heights),
                "initialHeight": heights[0],
                "finalHeight": heights[-1],
                "screenshot": str(args.screenshot) if args.screenshot else None,
            }
        ),
        flush=True,
    )
finally:
    if "timeline" in globals():
        timeline.stop()
    # This check queues no Replicator work. Waiting for that unrelated workflow
    # can leave a paused simulation spinning during shutdown.
    app.close(wait_for_replicator=False)
