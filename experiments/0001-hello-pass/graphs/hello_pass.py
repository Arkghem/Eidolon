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
