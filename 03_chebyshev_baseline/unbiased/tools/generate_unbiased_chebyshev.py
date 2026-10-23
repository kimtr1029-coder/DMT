#!/usr/bin/env python3
"""Generate the unbiased piecewise-Chebyshev BER coefficient bank.

This is deliberately the original Chebyshev fitting flow with exactly one
change: no segment-wise upward correction is added to c0.

The shared function is

    h(z) = erfc(sqrt(z)),  1.25 <= z < 12.25.

Each of the 44 intervals is fitted independently with a degree-4 polynomial in
the local Chebyshev coordinate u.  numpy.chebfit produces the coefficients,
which are converted to the power basis, quantized to Q30, and evaluated with
the same sign-symmetric rounding as the RTL Horner pipeline.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from numpy.polynomial import chebyshev as cheb
from scipy.special import erfc


ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / "rtl"
GEN = ROOT / "generated"

Q16 = 1 << 16
Q24 = 1 << 24
Q30 = 1 << 30

DOMAIN_LO = 1.25
DOMAIN_HI = 12.25
Z_LO_Q16 = round(DOMAIN_LO * Q16)
Z_HI_Q16 = round(DOMAIN_HI * Q16)

QAMS = (4, 16, 64, 256)
Z_FACTOR_Q24 = {4: 8_388_608, 16: 1_677_722, 64: 399_458, 256: 98_690}
BER_SCALE_Q24 = {4: 8_388_608, 16: 6_291_456,
                 64: 4_893_355, 256: 3_932_160}

DEGREE = 4
SEGMENT_WIDTH = 0.25
SEGMENTS = round((DOMAIN_HI - DOMAIN_LO) / SEGMENT_WIDTH)
STEP_Q16 = round(SEGMENT_WIDTH * Q16)
FIT_SAMPLES_PER_SEGMENT = 4001
TARGET_BER = 1.0e-4
TARGET_BAND = (5.0e-5, 2.0e-4)


def round_signed(values: np.ndarray, shift: int) -> np.ndarray:
    """Match sign-symmetric RTL rounding after every Horner multiply."""
    half = 1 << (shift - 1)
    return np.where(values >= 0, (values + half) >> shift,
                    -(((-values) + half) >> shift))


def ceil_div_array(num: np.ndarray, den: int) -> np.ndarray:
    return -np.floor_divide(-num, den)


def exact_ber(snr_linear: np.ndarray, modulation: int) -> np.ndarray:
    scale = (2.0 / math.log2(modulation)) * (1.0 - 1.0 / math.sqrt(modulation))
    argument = np.sqrt(3.0 * snr_linear / (2.0 * (modulation - 1.0)))
    return scale * erfc(argument)


def segment_and_u(z_q16: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    relative = z_q16.astype(np.int64) - Z_LO_Q16
    segment = relative // STEP_Q16
    offset = relative - segment * STEP_Q16
    # 0.25 = 2^14 Q16 codes, hence u = 2*offset/2^14 - 1.
    u_q30 = (offset << 17) - Q30
    return segment.astype(np.int64), u_q30.astype(np.int64)


def horner_fixed(coefficients: np.ndarray, x_q30: np.ndarray) -> np.ndarray:
    value = np.full_like(x_q30, int(coefficients[-1]), dtype=np.int64)
    for coefficient in coefficients[-2::-1]:
        value = int(coefficient) + round_signed(value * x_q30, 30)
    return value


def evaluate_h_q30(z_q16: np.ndarray, coefficients_q30: np.ndarray) -> np.ndarray:
    segment, u_q30 = segment_and_u(z_q16)
    result = np.empty_like(z_q16, dtype=np.int64)
    for index in range(SEGMENTS):
        selected = segment == index
        result[selected] = horner_fixed(coefficients_q30[index], u_q30[selected])
    return result


def fit_piecewise_chebyshev() -> np.ndarray:
    """Reproduce the original chebfit flow, without an upward c0 bias."""
    coefficients = []
    for index in range(SEGMENTS):
        lower = DOMAIN_LO + index * SEGMENT_WIDTH
        upper = lower + SEGMENT_WIDTH
        z = np.linspace(lower, upper, FIT_SAMPLES_PER_SEGMENT)
        u = (2.0 * z - (lower + upper)) / SEGMENT_WIDTH
        c_cheb = cheb.chebfit(u, erfc(np.sqrt(z)), DEGREE)
        c_power = cheb.cheb2poly(c_cheb)
        coefficients.append(np.rint(c_power * Q30).astype(np.int64))
    return np.asarray(coefficients, dtype=np.int64)


def final_ber_q24(h_q30: np.ndarray, scale_q24: int) -> np.ndarray:
    product = h_q30 * scale_q24
    return np.minimum(Q24 - 1, (product + (1 << 29)) >> 30).astype(np.int64)


def minimum_snr_for_z_bucket(z_q16: np.ndarray, factor_q24: int) -> np.ndarray:
    numerator = z_q16.astype(np.int64) * Q24 - (1 << 23)
    return np.maximum(0, ceil_div_array(numerator, factor_q24)).astype(np.int64)


def maximum_snr_for_z_bucket(z_q16: np.ndarray, factor_q24: int) -> np.ndarray:
    upper_exclusive = ceil_div_array(
        (z_q16.astype(np.int64) + 1) * Q24 - (1 << 23), factor_q24
    )
    return np.maximum(0, upper_exclusive - 1).astype(np.int64)


def safe_max(values: np.ndarray) -> float:
    return float(np.max(values)) if values.size else 0.0


def audit(coefficients_q30: np.ndarray) -> dict:
    z_q16 = np.arange(Z_LO_Q16, Z_HI_Q16, dtype=np.int64)
    h_q30 = evaluate_h_q30(z_q16, coefficients_q30)
    exact_h = erfc(np.sqrt(z_q16 / Q16))
    h_error = h_q30 / Q30 - exact_h
    report: dict = {
        "method": "unbiased degree-4 piecewise Chebyshev-basis least-squares fit",
        "h_error": {
            "minimum_signed": float(np.min(h_error)),
            "maximum_signed": float(np.max(h_error)),
            "maximum_absolute": float(np.max(np.abs(h_error))),
            "rmse": float(np.sqrt(np.mean(h_error * h_error))),
            "negative_codes": int(np.count_nonzero(h_error < 0.0)),
            "positive_codes": int(np.count_nonzero(h_error > 0.0)),
            "zero_codes": int(np.count_nonzero(h_error == 0.0)),
        },
        "qam": {},
    }

    for modulation in QAMS:
        minimum_snr = minimum_snr_for_z_bucket(z_q16, Z_FACTOR_Q24[modulation])
        maximum_snr = maximum_snr_for_z_bucket(z_q16, Z_FACTOR_Q24[modulation])
        exact_maximum = exact_ber(minimum_snr / Q16, modulation)
        exact_minimum = exact_ber(maximum_snr / Q16, modulation)
        estimate = final_ber_q24(h_q30, BER_SCALE_Q24[modulation]) / Q24

        # The RTL estimate is constant inside a z bucket.  Since BER decreases
        # monotonically with SNR, these two endpoints bound every Q16 SNR code.
        minimum_error = estimate - exact_maximum
        maximum_error = estimate - exact_minimum
        target_under = ((exact_maximum >= TARGET_BAND[0]) &
                        (exact_maximum <= TARGET_BAND[1]) &
                        (minimum_error < 0.0))
        target_over = ((exact_minimum >= TARGET_BAND[0]) &
                       (exact_minimum <= TARGET_BAND[1]) &
                       (maximum_error > 0.0))
        false_safe = (estimate <= TARGET_BER) & (exact_maximum > TARGET_BER)
        false_reject = (estimate > TARGET_BER) & (exact_minimum <= TARGET_BER)

        report["qam"][str(modulation)] = {
            "z_buckets": int(len(z_q16)),
            "underestimating_buckets_at_worst_endpoint": int(np.count_nonzero(minimum_error < 0.0)),
            "overestimating_buckets_at_best_endpoint": int(np.count_nonzero(maximum_error > 0.0)),
            "minimum_signed_error": float(np.min(minimum_error)),
            "maximum_signed_error": float(np.max(maximum_error)),
            "maximum_absolute_error": float(max(np.max(np.abs(minimum_error)),
                                                np.max(np.abs(maximum_error)))),
            "maximum_relative_underestimate_target_band": safe_max(
                -minimum_error[target_under] / exact_maximum[target_under]
            ),
            "maximum_relative_overestimate_target_band": safe_max(
                maximum_error[target_over] / exact_minimum[target_over]
            ),
            "false_safe_target_crossing_buckets": int(np.count_nonzero(false_safe)),
            "false_reject_target_crossing_buckets": int(np.count_nonzero(false_reject)),
        }
    return report


def verilog_signed(value: int, width: int = 32) -> str:
    return f"-{width}'sd{abs(value)}" if value < 0 else f"{width}'sd{value}"


def emit_rom(coefficients_q30: np.ndarray) -> None:
    lines = [
        "`timescale 1ns / 1ps",
        "",
        "// Generated by tools/generate_unbiased_chebyshev.py.",
        "// Unbiased two-sided Chebyshev-fit coefficients; no upward correction.",
        "module piecewise_cheb_coeff_rom_q30 (",
        "    input  wire [5:0] i_segment,",
        "    output reg signed [31:0] o_c0,",
        "    output reg signed [31:0] o_c1,",
        "    output reg signed [31:0] o_c2,",
        "    output reg signed [31:0] o_c3,",
        "    output reg signed [31:0] o_c4",
        ");",
        "    always @(*) begin",
        "        o_c0 = 32'sd0; o_c1 = 32'sd0; o_c2 = 32'sd0;",
        "        o_c3 = 32'sd0; o_c4 = 32'sd0;",
        "        case (i_segment)",
    ]
    for index, row in enumerate(coefficients_q30):
        values = "; ".join(
            f"o_c{degree} = {verilog_signed(int(row[degree]))}"
            for degree in range(DEGREE + 1)
        )
        lines.append(f"            6'd{index}: begin {values}; end")
    lines += [
        "            default: begin end",
        "        endcase",
        "    end",
        "endmodule",
    ]
    (RTL / "piecewise_cheb_coeff_rom_q30.v").write_text("\n".join(lines) + "\n")


def main() -> None:
    RTL.mkdir(parents=True, exist_ok=True)
    GEN.mkdir(parents=True, exist_ok=True)
    coefficients = fit_piecewise_chebyshev()
    chebyshev_audit = audit(coefficients)
    h_error = chebyshev_audit["h_error"]
    if not (h_error["minimum_signed"] < 0.0 < h_error["maximum_signed"]):
        raise RuntimeError("unbiased Chebyshev approximation is not two-sided")

    report = {
        "function": "h(z)=erfc(sqrt(z))",
        "domain_z": [DOMAIN_LO, DOMAIN_HI],
        "input_grid": "every Q16 z code",
        "fitting_method": "numpy.polynomial.chebyshev.chebfit",
        "fit_samples_per_segment": FIT_SAMPLES_PER_SEGMENT,
        "q_formats": {"input_snr": "Q16", "coefficients": "Q30", "output_ber": "Q24"},
        "segments": SEGMENTS,
        "segment_width": SEGMENT_WIDTH,
        "degree": DEGREE,
        "coefficient_bank_bits": SEGMENTS * (DEGREE + 1) * 32,
        "one_sided_bias_applied": False,
        "post_fit_minimax_optimization_applied": False,
        "chebyshev_audit": chebyshev_audit,
        "coefficients_q30": coefficients.tolist(),
    }
    emit_rom(coefficients)
    (GEN / "unbiased_chebyshev_coefficients_and_audit.json").write_text(
        json.dumps(report, indent=2) + "\n"
    )
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
