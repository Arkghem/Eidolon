# vendor/

第三方代码。**只读**：除了由脚本生成的注入文件，这里不应该出现任何手工改动。

```
vendor/
└─ falcor/     # Falcor 渲染框架，git submodule，锁定 tag 9.0
```

## 初始化

```powershell
pwsh -File tools\bootstrap.ps1
```

或手工：

```powershell
git submodule update --init --recursive
git -C vendor/falcor checkout 9.0
git -C vendor/falcor submodule update --init --recursive
```

Falcor 自身还依赖 6 个子模块：`pybind11`、`glfw`、`args`、`fmt`、`imgui`、`vulkan-headers`。
拉完之后还要跑一次 `vendor\falcor\setup.bat` 拉 packman 依赖（cmake / ninja / python /
slang / 媒体包等，2–4 GB）。这两步 `tools\build.ps1` 会自动补。

## 允许出现的改动

只有一个：`vendor/falcor/Source/RenderPasses/CMakeLists.txt` 末尾的
`eidolon overlay` 生成块（由 `tools\sync-passes.ps1` 生成）。

```powershell
# 查看真实状态
git -C vendor/falcor status --short
```

除此之外的任何改动都属于"改了上游"，必须记进 `patches/README.md`，
否则下次升级会静默丢掉。

## 升级

```powershell
pwsh -File tools\upgrade-falcor.ps1 -Ref 9.0
```

当前锁定版本与 commit 见 `VERSION.md`。
