#!/usr/bin/env python3
"""Emit every in-domain Q16-z bucket for exhaustive RTL comparison."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np

import generate_unbiased_chebyshev as g


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "build" / "exhaustive_vectors.bin"
DTYPE = np.dtype([
    ("snr_q16", "<u4"),
    ("tier", "<u4"),
    ("expected_ber_q24", "<u4"),
])
TIER = {4: 1, 16: 2, 64: 3, 256: 4}


def main() -> None:
    report = json.loads(
        (ROOT / "generated" / "unbiased_chebyshev_coefficients_and_audit.json").read_text()
    )
    coefficients = np.asarray(report["coefficients_q30"], dtype=np.int64)
    z_q16 = np.arange(g.Z_LO_Q16, g.Z_HI_Q16, dtype=np.int64)
    h_q30 = g.evaluate_h_q30(z_q16, coefficients)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("wb") as stream:
        for modulation in g.QAMS:
            rows = np.empty(len(z_q16), dtype=DTYPE)
            rows["snr_q16"] = g.minimum_snr_for_z_bucket(
                z_q16, g.Z_FACTOR_Q24[modulation]
            ).astype(np.uint32)
            rows["tier"] = TIER[modulation]
            rows["expected_ber_q24"] = g.final_ber_q24(
                h_q30, g.BER_SCALE_Q24[modulation]
            ).astype(np.uint32)
            rows.tofile(stream)
    print(f"generated {len(z_q16) * len(g.QAMS):,} exhaustive RTL records at {OUTPUT}")


if __name__ == "__main__":
    main()
