# research/apps/

预留给"需要自己掌管主循环"的课题——例如：

- 需要按固定帧序 + 脚本化输入做长时间采集
- 需要训练循环（PyTorch + Falcor Python 扩展，或 CUDA/ComputePass 反传）
- 需要自定义命令行参数的论文复现实验

## 约定

- 一个应用一个目录：`research/apps/<Name>/`，包含 `CMakeLists.txt`、`<Name>.cpp`。
- 在 `research/apps.txt` 里登记名字，`tools\sync-passes.ps1` 会把它注入到
  Falcor 构建树的同一个覆盖层块里（与 pass 相同机制，见 `docs/01-architecture.md`）。
- 用上游的 `add_falcor_executable(<Name>)` 创建目标，它会把可执行文件放进
  `<build>\bin[<cfg>]\`，并统一链接 `Falcor` 库。
- 清单是空的就什么都不注入；删掉名字后记得重跑 `sync-passes.ps1` 并重新 configure。

## 什么时候不要用它

如果只是"跑一个渲染图看效果"，用 `Mogwai -s <graph.py>` 就够了，别另起 app。
app 的价值只在：**你需要在 C++ 里控制帧循环/数据流，或需要脱离 Mogwai 的 UI 做批处理**。

（目前为空目录，首个需要的课题再填。）
