# 0001-hello-pass render graph.
#
# Minimal graph that proves HelloPass is loadable and connected:
#   HelloPass (HDR RGBA16F) -> ToneMapper (LDR) -> presented output
#
# Deliberately does not use BlitPass: one pass fewer means one fewer thing to
# blame when the window stays black.

from falcor import *


def render_graph_HelloPass():
    g = RenderGraph("HelloPass")
    g.addPass(createPass("HelloPass"), "HelloPass")
    g.addPass(createPass("ToneMapper"), "ToneMapper")
    g.addEdge("HelloPass.color", "ToneMapper.src")
    g.markOutput("ToneMapper.dst")
    return g


HelloPass = render_graph_HelloPass()
try:
    m.addGraph(HelloPass)
except NameError:
    pass
