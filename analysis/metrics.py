"""Image quality metrics for Eidolon experiments.

Usage
-----
    python analysis/metrics.py --ref baseline.png --test result.png
    python analysis/metrics.py --ref a.png --test b.png --json out/metrics.json

Why not just eyeball it
-----------------------
Eyeballing catches gross errors; it does not catch a 0.3 dB regression from a
"harmless" parameter tweak. Every experiment should be able to state a number.

Notes
-----
* Images are compared as float RGB in [0, 1]; 16-bit PNGs and HDR files are
  truncated to the LDR range by design (results/ should hold displayable frames).
* SSIM uses scikit-image when available, otherwise a uniform-window
  implementation that is close enough for regression tracking but NOT bit-exact
  with the reference MATLAB implementation. Do not quote it as such.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def load_rgb(path: Path) -> np.ndarray:
    img = Image.open(path)
    if img.mode not in ("RGB", "RGBA"):
        img = img.convert("RGB")
    if img.mode == "RGBA":
        img = img.convert("RGB")
    arr = np.asarray(img).astype(np.float64) / 255.0
    return arr


def rmse(a: np.ndarray, b: np.ndarray) -> float:
    return float(math.sqrt(np.mean((a - b) ** 2)))


def psnr(a: np.ndarray, b: np.ndarray) -> float:
    mse = float(np.mean((a - b) ** 2))
    if mse <= 0.0:
        return float("inf")
    return float(10.0 * math.log10(1.0 / mse))


def _ssim_uniform(a: np.ndarray, b: np.ndarray, window: int = 8) -> float:
    """Uniform-window SSIM over an image pair (H, W, C) in [0, 1]."""
    pad = window // 2
    scores = []
    for c in range(a.shape[2]):
        x = a[:, :, c]
        y = b[:, :, c]
        # Local means via integral images (cheap, no scipy dependency).
        xp = np.pad(x, pad, mode="reflect")
        yp = np.pad(y, pad, mode="reflect")
        kernel = np.ones((window, window), dtype=np.float64) / (window * window)

        def local_mean(img: np.ndarray) -> np.ndarray:
            from numpy.lib.stride_tricks import sliding_window_view

            view = sliding_window_view(img, (window, window))
            m = np.einsum("ijkl,kl->ij", view, kernel)
            # The padded view yields one extra row/column; crop back to the image.
            return m[: x.shape[0], : x.shape[1]]

        mu_x = local_mean(xp)
        mu_y = local_mean(yp)
        sigma_x2 = local_mean(xp * xp) - mu_x * mu_x
        sigma_y2 = local_mean(yp * yp) - mu_y * mu_y
        sigma_xy = local_mean(xp * yp) - mu_x * mu_y

        c1 = 0.01**2
        c2 = 0.03**2
        ssim_map = ((2 * mu_x * mu_y + c1) * (2 * sigma_xy + c2)) / (
            (mu_x**2 + mu_y**2 + c1) * (sigma_x2 + sigma_y2 + c2)
        )
        scores.append(float(np.mean(ssim_map)))
    return float(np.mean(scores))


def ssim(a: np.ndarray, b: np.ndarray) -> float:
    try:
        from skimage.metrics import structural_similarity  # type: ignore

        return float(structural_similarity(a, b, channel_axis=2, data_range=1.0))
    except Exception:
        return _ssim_uniform(a, b)


def flip(a: np.ndarray, b: np.ndarray):
    """Optional FLIP error map (mean value). Returns None when unavailable."""
    try:
        import flip_evaluator  # type: ignore

        _, mean, _ = flip_evaluator.evaluate(a, b, "LDR")
        return float(mean)
    except Exception:
        return None


def compute(ref_path: Path, test_path: Path) -> dict:
    ref = load_rgb(ref_path)
    test = load_rgb(test_path)
    if ref.shape != test.shape:
        raise SystemExit(
            f"Size mismatch: {ref_path.name} is {ref.shape[1]}x{ref.shape[0]}, "
            f"{test_path.name} is {test.shape[1]}x{test.shape[0]}. "
            "Compare like with like - fix the resolution in configs/*.json."
        )

    result = {
        "ref": str(ref_path),
        "test": str(test_path),
        "resolution": [int(ref.shape[1]), int(ref.shape[0])],
        "rmse": rmse(ref, test),
        "psnr": psnr(ref, test),
        "ssim": ssim(ref, test),
    }
    f = flip(ref, test)
    if f is not None:
        result["flip"] = f
    return result


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Compare two rendered frames.")
    parser.add_argument("--ref", type=Path, required=True, help="reference / baseline image")
    parser.add_argument("--test", type=Path, required=True, help="image to evaluate")
    parser.add_argument("--json", type=Path, help="write metrics as JSON to this path")
    args = parser.parse_args(argv)

    for p in (args.ref, args.test):
        if not p.is_file():
            raise SystemExit(f"no such file: {p}")

    result = compute(args.ref, args.test)

    print(f"ref   : {result['ref']}")
    print(f"test  : {result['test']}")
    print(f"size  : {result['resolution'][0]}x{result['resolution'][1]}")
    print(f"RMSE  : {result['rmse']:.6f}")
    print(f"PSNR  : {result['psnr']:.3f} dB")
    print(f"SSIM  : {result['ssim']:.6f}")
    if "flip" in result:
        print(f"FLIP  : {result['flip']:.6f}")
    else:
        print("FLIP  : (install flip-evaluator to enable)")

    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(f"\nwrote {args.json}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
