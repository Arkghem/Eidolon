# assets/

研究用的**大体积资产**，不入版本库（`.gitignore` 已排除 `scenes/`、`envmaps/`、`link/`、`orca/`、`pbrt/`）。

```
assets/
├─ scenes/      # .pyscene / .usd / glTF / pbrt-v4 场景
├─ envmaps/     # .exr / .hdr 环境光照
├─ link/        # 需要重建的资产（脚本生成的 SDF、BVH 缓存等）
├─ orca/        # ORCA 场景包解压位置
└─ pbrt/        # pbrt-v4 格式场景（Falcor 可直接加载）
```

## 如何被 Falcor 发现

`tools\run-mogwai.ps1` 会把 `assets\scenes` 与 `assets\envmaps` 追加进 `FALCOR_MEDIA_FOLDERS`（分号分隔），
于是场景脚本里可以直接写相对路径，例如：

```python
m.loadScene("my_scene/my_scene.pyscene")
```

只有 `assets\scenes`、`assets\envmaps` 存在时才会被加入搜索路径（脚本按存在性筛选）。

## 起步资产

Falcor 自带的媒体包由 packman 提供，位于 `vendor\falcor\media\`（已在 `.gitignore` 中），
默认用 `media\Arcade\Arcade.pyscene` 就够跑通全流程，无需额外下载。

## 重场景从哪里来

- [ORCA](https://developer.nvidia.com/orca)（NVIDIA 提供的 Falcor 优化场景集）
- [Benedikt Bitterli 的渲染资源](https://benedikt-bitterli.me/resources)（pbrt-v4 格式，Falcor 可加载）

下载后解压到对应子目录即可；**不要**把这些目录提交进 git（单场景常达数 GB）。
