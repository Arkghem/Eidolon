# third_party/renderdoc

`renderdoc_app.h` 是 RenderDoc 官方提供的进程内 API 头文件，按 MIT 许可随 RenderDoc 分发
（版权归 Baldur Karlsson；许可证原文保留在文件头部，不得删除）。

- 来源：本机安装的 RenderDoc 1.46（`C:\Program Files\RenderDoc\renderdoc_app.h`）
- 用途：让 `Eidolon::maybeCaptureAtFrame()`（见 `research/shared/include/Eidolon/RenderDoc.hpp`）
  能在运行时找到已被注入的 `renderdoc.dll` 并触发抓帧。
- 为什么需要它：Falcor 9.0 **没有**任何进程内 RenderDoc 集成，而 RenderDoc 1.46 的
  `renderdoccmd capture` 也不提供"抓第 N 帧"的参数（没有 `--capture-frame`/`--capture-all`）。
  没有这个钩子，自动化抓帧就无从触发。

升级 RenderDoc 时可以整份替换本文件；只要 `eRENDERDOC_API_Version_1_6_0` 之后的结构仍兼容，
我们的封装无需改动。
