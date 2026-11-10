# <NNNN-slug> render graph.
#
# Loaded by tools/run-experiment.ps1 (or Mogwai -s <this file>).
# Keep the graph structure here and the numeric settings in configs/*.json so a
# graph can be reused across parameter sweeps.

from falcor import *
import os


def render_graph_<GRAPH_NAME>():
    g = RenderGraph("<GRAPH_NAME>")
    g.addPass(createPass("<PassName>"), "<PassName>")
    g.addPass(createPass("ToneMapper"), "ToneMapper")
    g.addEdge("<PassName>.color", "ToneMapper.src")
    g.markOutput("ToneMapper.dst")
    return g


<GRAPH_NAME> = render_graph_<GRAPH_NAME>()
try:
    m.addGraph(<GRAPH_NAME>)
except NameError:
    pass

# Optional frame dump; see experiments/0001-hello-pass/graphs/hello_pass.py and
# tools/run-mogwai.ps1 -CaptureDir. Keep this hook in every experiment graph so
# headless runs can produce evidence.
_capture_dir = os.environ.get("EIDOLON_CAPTURE_DIR")
if _capture_dir:
    try:
        # 'fc' is the FrameCapture extension object injected by Mogwai.
        fc.outputDir = _capture_dir
        fc.addFrames(<GRAPH_NAME>, [5, 10, 20])
        print("<GRAPH_NAME>: frame capture -> " + _capture_dir)
    except Exception as e:  # noqa: BLE001
        print("<GRAPH_NAME>: frame capture setup failed: %r" % (e,))
