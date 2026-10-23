#!/usr/bin/env python3
"""Generate deterministic bit-exact vectors for the Chebyshev BER datapath."""

from __future__ import annotations

import json
import math
from pathlib import Path
import random

import numpy as np

import generate_unbiased_chebyshev as g


ROOT = Path(__file__).resolve().parents[1]
TB = ROOT / "tb"
HIGH_MARGIN = 100 << 16
THRESHOLD_DB = {4: 6, 16: 12, 64: 18, 256: 24}
TIER = {4: 1, 16: 2, 64: 3, 256: 4}


def q16(value: float) -> int:
    return math.floor(value * g.Q16 + 0.5)


def margins_for(modulation: int) -> tuple[int, int, int, int]:
    return (
        0 if modulation == 256 else HIGH_MARGIN,
        0 if modulation in (64, 256) else HIGH_MARGIN,
        0 if modulation in (16, 64, 256) else HIGH_MARGIN,
        0,
    )


def z_q16(snr_q16: int, modulation: int) -> int:
    return min(0xFFFFFFFF,
               (snr_q16 * g.Z_FACTOR_Q24[modulation] + (1 << 23)) >> 24)


def model_output(snr_q16: int, modulation: int,
                 coefficients: np.ndarray) -> int:
    z = z_q16(snr_q16, modulation)
    if z < g.Z_LO_Q16:
        return 0xFFFFFF
    if z >= g.Z_HI_Q16:
        return 0
    h_q30 = g.evaluate_h_q30(np.asarray([z], dtype=np.int64), coefficients)
    return int(g.final_ber_q24(h_q30, g.BER_SCALE_Q24[modulation])[0])


def emit(path: Path, rows: list[tuple[int, ...]]) -> None:
    lines = [
        "#pragma once",
        f"static constexpr std::array<test_vector, {len(rows)}> TEST_VECTORS {{{{",
    ]
    for row in rows:
        lines.append("    {" + ", ".join(f"{value}u" for value in row) + "},")
    lines += ["}};", ""]
    path.write_text("\n".join(lines), encoding="ascii")


def main() -> None:
    report = json.loads(
        (ROOT / "generated" / "unbiased_chebyshev_coefficients_and_audit.json").read_text()
    )
    if report["one_sided_bias_applied"] or report["post_fit_minimax_optimization_applied"]:
        raise RuntimeError("expected plain unbiased Chebyshev coefficients")
    coefficients = np.asarray(report["coefficients_q30"], dtype=np.int64)

    rng = random.Random(0xC0DEC024)
    samples: list[tuple[int, float]] = []
    for modulation in g.QAMS:
        threshold = THRESHOLD_DB[modulation]
        samples.extend((modulation, threshold + offset)
                       for offset in (0.0, 0.1, 3.0, 6.0, 9.0))
    for _ in range(4096):
        modulation = rng.choice(g.QAMS)
        samples.append((modulation,
                        THRESHOLD_DB[modulation] + rng.uniform(0.0, 9.2)))

    rows: list[tuple[int, ...]] = []
    for modulation, snr_db in samples:
        snr = q16(10.0 ** (snr_db / 10.0))
        margins = margins_for(modulation)
        common = (snr, THRESHOLD_DB[modulation] << 16, *margins)
        rows.append((*common, model_output(snr, modulation, coefficients), TIER[modulation]))

    TB.mkdir(parents=True, exist_ok=True)
    emit(TB / "chebyshev_vectors.hpp", rows)
    print(f"generated {len(rows)} deterministic Chebyshev vectors")


if __name__ == "__main__":
    main()
