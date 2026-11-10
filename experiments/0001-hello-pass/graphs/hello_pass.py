# 0001-hello-pass render graph.
#
# Minimal graph that proves HelloPass is loadable and connected:
#   HelloPass (HDR RGBA16F) -> ToneMapper (LDR) -> presented output
#
# Deliberately does not use BlitPass: one pass fewer means one fewer thing to
# blame when the window stays black.

from falcor import *
import os


def render_graph_HelloPass():
    g = RenderGraph("HelloPass")
    g.addPass(createPass("HelloPass"), "HelloPass")
    # Pin the tone mapping so the smoke test is deterministic: auto exposure
    # depends on scene metadata, and this graph deliberately has no scene.
    g.addPass(createPass("ToneMapper", {"autoExposure": False}), "ToneMapper")
    g.addEdge("HelloPass.color", "ToneMapper.src")
    g.markOutput("ToneMapper.dst")
    return g


HelloPass = render_graph_HelloPass()
try:
    m.addGraph(HelloPass)
except NameError:
    pass

# Optional automated frame dump. tools/run-mogwai.ps1 -CaptureDir <path> sets
# EIDOLON_CAPTURE_DIR; the FrameCapture extension then writes PNGs for the given
# frame numbers while Mogwai runs. This is how a headless run produces evidence
# without a human pressing F12.
_capture_dir = os.environ.get("EIDOLON_CAPTURE_DIR")
if _capture_dir:
    try:
        # 'fc' is the FrameCapture extension object Mogwai injects into the
        # script context ('frameCapture' is only the pybind class name).
        fc.outputDir = _capture_dir
        fc.addFrames(HelloPass, [5, 10, 20])
        print("HelloPass: frame capture -> " + _capture_dir)
    except Exception as e:  # noqa: BLE001 - never break the graph for a capture hook
        print("HelloPass: frame capture setup failed: %r" % (e,))

