# <NNNN-slug> render graph.
#
# Loaded by tools/run-experiment.ps1 (or Mogwai -s <this file>).
# Keep the graph structure here and the numeric settings in configs/*.json so a
# graph can be reused across parameter sweeps.

from falcor import *


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
