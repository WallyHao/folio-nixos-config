"""A real CUDA computation, run explicitly on the host GPU."""
import json
import numba
import numpy
import onnxruntime
import torch

assert torch.cuda.is_available(), "CUDA unavailable"
x = torch.randn(1024, 1024, device="cuda")
y = x @ x.T
torch.cuda.synchronize()
assert torch.isfinite(y).all().item(), "Non-finite CUDA result"
print(json.dumps({"stage": "cuda", "status": "passed", "torch": torch.__version__,
                  "cuda": torch.version.cuda, "gpu": torch.cuda.get_device_name(0),
                  "numpy": numpy.__version__, "numba": numba.__version__,
                  "onnxruntime": onnxruntime.__version__}))
