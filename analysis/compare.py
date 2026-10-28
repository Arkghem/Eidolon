"""Compare an experiment's results against a baseline and emit a figure + CSV.

Usage
-----
    python analysis/compare.py --experiment 0001-hello-pass
    python analysis/compare.py --experiment 0007-foo --baseline baseline --out out/compare

Layout it expects (created by your own runs, not by the tooling):

    experiments/<exp>/results/
        baseline/  ref_0000.png     <- reference frames
        candidate/ out_0000.png     <- frames to evaluate

Frame names are matched by their trailing index, so `ref_0000.png` pairs with
`out_0000.png` and with `0000.png`.

matplotlib is optional: without it the numbers are still computed and written to
CSV/JSON, only the side-by-side figure is skipped.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from metrics import compute  # noqa: E402

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".bmp"}


def frame_key(path: Path) -> str:
    m = re.search(r"(\d+)(?=\.[^.]+$)", path.name)
    return m.group(1) if m else path.stem


def collect(folder: Path) -> dict:
    if not folder.is_dir():
        return {}
    return {frame_key(p): p for p in sorted(folder.iterdir()) if p.suffix.lower() in IMAGE_EXTS}


def save_grid(keys, base: dict, cand: dict, fig_path: Path) -> bool:
    """Write a baseline/candidate/|diff| grid. Returns False when matplotlib is absent."""
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        print("warning: matplotlib not installed - skipping the comparison figure.")
        print("         pip install -r analysis/requirements.txt")
        return False

    shown = keys[:3]
    fig, axes = plt.subplots(len(shown), 3, figsize=(12, 3.4 * len(shown)), squeeze=False)
    for row_idx, k in enumerate(shown):
        a = np.asarray(Image.open(base[k]).convert("RGB")).astype(np.float32) / 255.0
        b = np.asarray(Image.open(cand[k]).convert("RGB")).astype(np.float32) / 255.0
        diff = np.abs(a - b).mean(axis=2)
        panels = [
            (a, f"baseline {k}", None),
            (b, f"candidate {k}", None),
            (np.clip(diff * 8.0, 0, 1), "|diff| x8", "magma"),
        ]
        for col, (data, title, cmap) in enumerate(panels):
            ax = axes[row_idx][col]
            ax.imshow(data, cmap=cmap)
            ax.set_title(title, fontsize=9)
            ax.axis("off")
    fig.tight_layout()
    fig.savefig(fig_path, dpi=120)
    plt.close(fig)
    return True


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Baseline vs candidate comparison.")
    parser.add_argument("--experiment", required=True, help="experiment directory name, e.g. 0001-hello-pass")
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--baseline", default="baseline", help="subdirectory of results/ holding the reference")
    parser.add_argument("--candidate", default="candidate", help="subdirectory of results/ holding the new frames")
    parser.add_argument("--out", type=Path, default=None, help="output directory (default: experiments/<exp>/results/compare)")
    args = parser.parse_args(argv)

    results_dir = args.repo_root / "experiments" / args.experiment / "results"
    base_dir = results_dir / args.baseline
    cand_dir = results_dir / args.candidate
    out_dir = args.out or (results_dir / "compare")

    base = collect(base_dir)
    cand = collect(cand_dir)
    if not base:
        raise SystemExit(f"no baseline frames in {base_dir}\nAdd reference frames there first (see docs/04-experiments.md).")
    if not cand:
        raise SystemExit(f"no candidate frames in {cand_dir}")

    keys = sorted(set(base) & set(cand))
    if not keys:
        raise SystemExit(f"no matching frame indices between {base_dir} and {cand_dir}")

    out_dir.mkdir(parents=True, exist_ok=True)

    rows = []
    for k in keys:
        m = compute(base[k], cand[k])
        m["frame"] = k
        rows.append(m)
        print(f"frame {k}: PSNR {m['psnr']:.3f} dB  SSIM {m['ssim']:.4f}  RMSE {m['rmse']:.6f}")

    csv_path = out_dir / "metrics.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    json_path = out_dir / "metrics.json"
    json_path.write_text(json.dumps(rows, indent=2), encoding="utf-8")

    fig_path = out_dir / "compare.png"
    save_grid(keys, base, cand, fig_path)

    mean_psnr = float(np.mean([r["psnr"] for r in rows]))
    mean_ssim = float(np.mean([r["ssim"] for r in rows]))
    print()
    print(f"frames : {len(rows)}")
    print(f"PSNR   : {mean_psnr:.3f} dB (mean)")
    print(f"SSIM   : {mean_ssim:.4f} (mean)")
    if fig_path.is_file():
        print(f"figure : {fig_path}")
    print(f"csv    : {csv_path}")
    print(f"json   : {json_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
