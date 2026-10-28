# ADR 0003 — RenderDoc 以进程外方式接入

- **状态**：已采纳（2026-10-28）
- **上下文**：研究需要逐帧分析。Falcor 9.0 的 `RenderContext`/`Core/API` 中
  **不存在**任何 RenderDoc capture 接口（已核对 `Source/Falcor/Core/API/RenderContext.h`，
  无 `RenderDoc`/`capture` 相关声明），所以无法在引擎内部触发抓帧。
- **选项**：
  1. 进程外：qrenderdoc 启动/附加 `Mogwai.exe`，或 `renderdoccmd capture`；
  2. 自研一个加载 `renderdoc_app.h` 的插件，提供进程内触发 + Python 绑定；
  3. 换用其他工具（Nsight Graphics / PIX）。
- **决定**：选 1，`tools/capture.ps1` 提供交互与自动化两种模式。
- **理由**：
  - 方案 1 与任何 D3D12 程序的调试方式一致，不依赖引擎版本，升级零成本。
  - 方案 2 能换来"脚本化抓帧"的便利，但要多维护一份 ABI 对接代码，
    而且抓帧时机（Present）本质上仍受进程外 hook 控制——收益与成本不成比例。
  - 方案 3 保留为补充（GPU 计数器、barrier 分析），不作为主路径。
- **后果**：
  - 自动化抓帧要求程序自行退出（`--wait-for-exit` 语义），
    所以 `capture.ps1 -Mode cmd` 需要 `--headless` 或自终止的脚本；
  - 每次抓帧必须落 `manifest.json`，否则 `.rdc` 很快失去可解释性；
  - 将来若真需要进程内触发，再写方案 2 的插件，本 ADR 失效并新增一条。
