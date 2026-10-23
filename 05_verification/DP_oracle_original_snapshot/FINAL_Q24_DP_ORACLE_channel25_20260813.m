% =========================================================================
% [TWO-TRX BIDIRECTIONAL LOCAL-RX -> LOCAL-TX ARCHITECTURE]
%
% One physical cable is used in both directions:
%   TX_A -- A->B --> RX_B
%   TX_B -- B->A --> RX_A
%
% Local adaptation:
%   RX_A measures B->A SNR -> Engine A -> LOCAL TX_A map for A->B
%   RX_B measures A->B SNR -> Engine B -> LOCAL TX_B map for B->A
%
% Required map equalities:
%   Engine A map == TX_A map == RX_B map   (A->B)
%   Engine B map == TX_B map == RX_A map   (B->A)
%
% Exact-erfc reference comparisons and the existing figures are preserved.
% One additional bidirectional TRX figure is appended after those figures.
% Preamble-based SNR estimation itself remains outside this model.
% =========================================================================

clear all; close all; clc;

%% ========================================================================
%% 1. System & channel_25db.txt Setup
%% ========================================================================
Fs = 20e9;
N_FFT = 512;
N_CP = 40;
N_subcarriers = 255;

df = Fs / N_FFT;
f_axis_Hz = (1:N_subcarriers) * df;
f_axis_GHz = f_axis_Hz / 1e9;

% -------------------------------------------------------------------------
% Locate channel_25db.txt.
% The file may be placed either beside this script or in MATLAB's current
% working folder.
% Required format:
%   column 1,2: pole real/imaginary parts
%   column 3,4: residue real/imaginary parts
% -------------------------------------------------------------------------
script_path = mfilename('fullpath');
if isempty(script_path)
    script_dir = pwd;
else
    script_dir = fileparts(script_path);
end

channel_file = fullfile(script_dir, 'channel_25db.txt');
if ~isfile(channel_file)
    channel_file = fullfile(pwd, 'channel_25db.txt');
end
if ~isfile(channel_file)
    error(['channel_25db.txt was not found. Place it beside this MATLAB ', ...
           'script or in the current working directory.']);
end

% Parse the comma-separated file explicitly. The supplied channel file has
% a fifth metadata column and a trailing comma on each row; only the first
% four pole/residue values are used here.
fid_channel = fopen(channel_file, 'rt');
if fid_channel < 0
    error('Could not open channel_25db.txt for reading.');
end

channel_data = zeros(0, 4);
channel_line_number = 0;
channel_bad_line = 0;
while true
    channel_line = fgetl(fid_channel);
    if ~ischar(channel_line)
        break;
    end

    channel_line_number = channel_line_number + 1;
    channel_line = strtrim(channel_line);
    if isempty(channel_line)
        continue;
    end

    channel_values = sscanf(strrep(channel_line, ',', ' '), '%f');
    if numel(channel_values) < 4
        channel_bad_line = channel_line_number;
        break;
    end
    channel_data(end + 1, :) = channel_values(1:4).'; %#ok<AGROW>
end
fclose(fid_channel);

if channel_bad_line ~= 0
    error('channel_25db.txt line %d has fewer than four numeric values.', ...
        channel_bad_line);
end
if isempty(channel_data)
    error('channel_25db.txt contains no channel entries.');
end
if any(~isfinite(channel_data(:)))
    error('channel_25db.txt contains NaN or Inf.');
end

% -------------------------------------------------------------------------
% Reconstruct the frequency response from pole-residue data.
% H(f) = sum_i r_i / (j*2*pi*f + p_i)
% -------------------------------------------------------------------------
H_exact = complex(zeros(size(f_axis_Hz)));
for i = 1:size(channel_data, 1)
    p = channel_data(i, 1) + 1j * channel_data(i, 2);
    r = channel_data(i, 3) + 1j * channel_data(i, 4);
    H_exact = H_exact + r ./ (1j * 2 * pi * f_axis_Hz + p);
end

H_abs = abs(H_exact);
H_abs = max(H_abs, 1e-15);
H_mag_linear = H_abs.^2;
H_mag_dB = 20 * log10(H_abs);
H_mag_dB_plot = H_mag_dB - max(H_mag_dB);

% -------------------------------------------------------------------------
% Receiver SNR model used by the channel_25db.txt simulations.
% -------------------------------------------------------------------------
Tx_Swing_V = 0.5;
R_clip_tx = 6.0;
DAC_ENOB = 8;

R_clip_rx = 6.0;
ADC_ENOB = 8;
Noise_RMS_V = 0.8e-3;
Implementation_Loss_dB = 4.0;

Estimated_Tx_RMS = Tx_Swing_V / R_clip_tx;
Tx_Power = Estimated_Tx_RMS^2;

Delta_Tx = (2 * Tx_Swing_V) / (2^DAC_ENOB);
Q_Noise_Tx = (Delta_Tx^2) / 12;

Thermal_Noise_Power = Noise_RMS_V^2;

Rx_RMS_est = sqrt(Tx_Power * mean(H_mag_linear) + Thermal_Noise_Power);
Delta_Rx = (2 * R_clip_rx * Rx_RMS_est) / (2^ADC_ENOB);
Q_Noise_Rx = (Delta_Rx^2) / 12;

Signal_Rx = Tx_Power .* H_mag_linear;
Noise_Rx = (Q_Noise_Tx .* H_mag_linear) ...
         + Thermal_Noise_Power ...
         + Q_Noise_Rx;

Ideal_SNR_dB = 10 * log10(max(Signal_Rx, realmin) ./ max(Noise_Rx, realmin));
SNR_dB = Ideal_SNR_dB - Implementation_Loss_dB;
SNR_linear = 10.^(SNR_dB / 10);

% -------------------------------------------------------------------------
% TWO-TRX reciprocal-link interpretation.
% The SAME physical channel H_exact is used for A->B and B->A.
% With symmetric TX/RX assumptions, the two measured SNR profiles are
% identical in the nominal baseline. No directional calibration block is used.
% -------------------------------------------------------------------------
H_AB = H_exact;   % TX_A -> RX_B
H_BA = H_exact;   % TX_B -> RX_A

SNR_RX_A_IN_dB = SNR_dB;   % RX_A measures incoming B->A
SNR_RX_B_IN_dB = SNR_dB;   % RX_B measures incoming A->B

% Local-RX -> local-TX assumption used by this system:
% Engine A directly reuses RX_A's B->A SNR profile for TX_A's A->B loading.
% Engine B directly reuses RX_B's A->B SNR profile for TX_B's B->A loading.
% No directional calibration term is applied.
SNR_ENGINE_A_dB = SNR_RX_A_IN_dB;
SNR_ENGINE_B_dB = SNR_RX_B_IN_dB;

% The top-level controller/figure variables represent Engine A.
SNR_dB = SNR_ENGINE_A_dB;
SNR_linear = 10.^(SNR_dB / 10);

fprintf('\n============================================================\n');
fprintf('[channel_25db.txt single conservative-Q24 BER engine test]\n');
fprintf('Loaded file          : %s\n', channel_file);
fprintf('Pole-residue entries : %d\n', size(channel_data, 1));
fprintf('Relative channel gain: %.2f ~ %.2f dB\n', min(H_mag_dB_plot), max(H_mag_dB_plot));
fprintf('Controller SNR range : %.2f ~ %.2f dB\n', min(SNR_dB), max(SNR_dB));
fprintf('============================================================\n');

Target_BER = 1e-4;   % single BER target used everywhere in this script
RUN_E2E = true;   % run the existing E2E verification/figures

qam_list = [4 16 64 256];
base_th = [6 12 18 24];        % [4 16 64 256], unit: dB
max_iter = 1000;

% Final estimator format and residual guarantee.
% K/C and the 32-entry exponential LUT remain Q16, while the BER result is
% carried in Q24.  The one-sided coefficient bank is verified from each
% QAM's base threshold down to exact BER = 2^-20.  BER below that floor is
% covered by reserving 2^-20 in the controller's global target comparison.
BER_FRAC = 24;
BER_RESIDUAL_LOG2 = 20;
BER_RESIDUAL_BOUND = 2^(-BER_RESIDUAL_LOG2);
RUNTIME_BER_LIMIT = Target_BER - BER_RESIDUAL_BOUND;
if RUNTIME_BER_LIMIT <= 0
    error('Target_BER must be larger than the conservative residual bound.');
end

% Scan-only latency estimate. Actual RTL latency also includes pipeline
% fill/flush and FSM overhead, so this is reported as an estimate.
LATENCY_EST_CLOCK_HZ = 100e6;

%% ========================================================================
%% 2. Export SNR Table for Verilog Testbench
%% ========================================================================
% RTL uses unsigned Q16 dB. Negative SNR dB would wrap if directly cast to
% uint32, so clip below 0 dB for safe threshold comparison.
SNR_dB_for_rtl = max(SNR_dB, 0);
snr_db_q16 = round(SNR_dB_for_rtl * 65536);
snr_linear_q16 = round(SNR_linear * 65536);
SNR_linear_eval = double(snr_linear_q16) / 65536; % common BER-evaluation SNR

% Engine-B input is generated from RX_B's A->B measurement and is used to
% configure LOCAL TX_B for the reciprocal B->A direction.
SNR_ENGINE_B_dB_for_rtl = max(SNR_ENGINE_B_dB, 0);
snr_b_db_q16 = round(SNR_ENGINE_B_dB_for_rtl * 65536);
snr_b_linear_q16 = round(10.^(SNR_ENGINE_B_dB/10) * 65536);

fid = fopen('rx_a_snr_db_q16.mem', 'w');
for k = 1:N_subcarriers
    fprintf(fid, '%08X\n', uint32(snr_db_q16(k)));
end
fclose(fid);

fid = fopen('rx_a_snr_linear_q16.mem', 'w');
for k = 1:N_subcarriers
    fprintf(fid, '%08X\n', uint32(snr_linear_q16(k)));
end
fclose(fid);

fprintf('\n============================================================\n');
fprintf('[MATLAB -> Verilog TB Export]\n');
fprintf('Exported rx_a_snr_db_q16.mem and rx_a_snr_linear_q16.mem\n');
fprintf('SNR dB range for RTL = %.2f ~ %.2f dB\n', min(SNR_dB_for_rtl), max(SNR_dB_for_rtl));
fprintf('============================================================\n');

%% ========================================================================
%% 3. Single Conservative-BER LUT Setup
%% ========================================================================
lut_hw = floor(2.^(-(0:31)/32) * 65536) / 65536;
snr_sweep_db = 0:0.01:50;

[K_map, C_map, K_q16_map, C_q16_map] = ...
    load_conservative_ber_constants(qam_list);

% Fail fast if a MATLAB/version change produces constants different from
% the intended single-bank RTL parameters. Order: [4 16 64 256].
RTL_K_FIT_EXPECTED = [50734 10213 2436 602];
RTL_C_FIT_EXPECTED = [12756 10206 8057 6506];
rtl_k_fit_now = [K_q16_map(4) K_q16_map(16) K_q16_map(64) K_q16_map(256)];
rtl_c_fit_now = [C_q16_map(4) C_q16_map(16) C_q16_map(64) C_q16_map(256)];
if any(rtl_k_fit_now ~= RTL_K_FIT_EXPECTED) || ...
   any(rtl_c_fit_now ~= RTL_C_FIT_EXPECTED)
    error(['Loaded conservative K/C constants differ from the expected RTL values. ' ...
           'Update the MATLAB/RTL constants together before simulation.']);
end

verify_conservative_ber_constants( ...
    qam_list, base_th, K_q16_map, C_q16_map, ...
    BER_FRAC, BER_RESIDUAL_BOUND);

fprintf('\n============================================================\n');
fprintf('[Single Conservative BER-LUT Constants]\n');
fprintf('BER datapath = Q%d, residual guard = 2^{-%d} = %.6e\n', ...
    BER_FRAC, BER_RESIDUAL_LOG2, BER_RESIDUAL_BOUND);
fprintf('Runtime estimator limit = %.6e; system exact-BER target = %.6e\n', ...
    RUNTIME_BER_LIMIT, Target_BER);
fprintf('One K/C bank is used for every scan and the final allocation.\n');
fprintf('QAM\tK(float)\tC(float)\tK_Q16\tC_Q16\n');
for i = 1:length(qam_list)
    M = qam_list(i);
    fprintf('%d\t%.8f\t%.8f\t%d\t%d\n', M, ...
        K_map(M), C_map(M), K_q16_map(M), C_q16_map(M));
end
fprintf('============================================================\n');

%% ========================================================================
%% 5. Controller-Level Models + RTL-Matched LUT Models
%% ========================================================================
% IMPORTANT FOR FINAL CONSISTENCY:
% - The exact-erfc DP oracle is the offline global optimum over the same
%   QAM/base-threshold candidate set used by the proposed engine.
% - The exact-erfc global-margin controller is retained only as an ablation.
% - All LUT-based results used in Figures 1,2,6 are bit-accurate RTL models
%   (Q16 inputs/constants and Q24 BER). This keeps MATLAB consistent with RTL.
% - RTL-matched model uses:
%     * Q16 SNR_dB and SNR_linear inputs exported to Verilog TB
%     * Q16 K/C and LUT constants with a Q24 BER result
%     * margin step = 6554 / 65536 = 0.100006 dB
%     * bit-weighted BER target: sum(bits_k*BER_k)/sum(bits_k) <= Target_BER
%     * residual-guarded Q24 target comparison without division
%     * average-error QAM selection using cross multiplication
%     * upward margin search followed by one-step downward local refinement
%     * one conservative K/C bank throughout the complete controller

% Standard overall BER definition:
%   BER_overall = sum_k(bits_k * BER_k) / sum_k(bits_k).
% Exact oracle uses full-precision erfc BER with Q16 SNR/allocation and
% maximizes the total loaded bits by dynamic programming.
% LUT models use bit-accurate Q24 BER and an integer cross-multiplied check.
TARGET_BER_NUM = 1;
TARGET_BER_DEN = 10000;
if abs(Target_BER - TARGET_BER_NUM/TARGET_BER_DEN) > 1e-12
    error('This integer target mapping assumes Target_BER = 1e-4.');
end
MARGIN_STEP_Q16_RTL = 6554;
base_th_q16 = round(base_th * 65536);    % [4 16 64 256]

exact_rtl_global = run_global_model_exact_rtl_control( ...
    snr_db_q16, snr_linear_q16, Fs, N_FFT, N_CP, ...
    base_th_q16, Target_BER, MARGIN_STEP_Q16_RTL, max_iter);

res_exact_global = make_result_struct( ...
    'A) Exact-erfc Global-Margin Heuristic (Ablation)', ...
    exact_rtl_global.M_alloc_final, exact_rtl_global.Bits_alloc_final, ...
    exact_rtl_global.net_rate_final, ...
    compute_total_ber('exact', exact_rtl_global.M_alloc_final, exact_rtl_global.Bits_alloc_final, SNR_linear_eval, K_map, C_map, lut_hw), ...
    compute_total_ber('exact', exact_rtl_global.M_alloc_final, exact_rtl_global.Bits_alloc_final, SNR_linear_eval, K_map, C_map, lut_hw), ...
    exact_rtl_global.margins_db, exact_rtl_global.thresholds_db, exact_rtl_global.iter);

exact_oracle = run_exact_erfc_dp_oracle( ...
    snr_db_q16, snr_linear_q16, Fs, N_FFT, N_CP, ...
    base_th_q16, Target_BER);

res_exact_oracle = make_result_struct( ...
    'B) Exact-erfc DP Oracle (Same-Candidate Global Optimum)', ...
    exact_oracle.M_alloc_final, exact_oracle.Bits_alloc_final, ...
    exact_oracle.net_rate_final, exact_oracle.overall_ber, ...
    exact_oracle.overall_ber, nan(1, 4), nan(1, 4), 0);

if res_exact_oracle.trueBER > Target_BER * (1 + 1e-10)
    error('Exact-erfc DP oracle exceeds Target_BER. Check the DP implementation.');
end

fprintf('\n============================================================\n');
fprintf('[Offline Exact-erfc Dynamic-Programming Oracle]\n');
fprintf('Global objective      : maximize total loaded bits\n');
fprintf('Candidate QAM         : unused / 4 / 16 / 64 / 256\n');
fprintf('Base thresholds [4 16 64 256] = [%.4f %.4f %.4f %.4f] dB (Q16)\n', ...
    double(base_th_q16) / 65536);
fprintf('Oracle total bits     : %d\n', exact_oracle.total_bits);
fprintf('Oracle net rate       : %.6f Gbps\n', exact_oracle.net_rate_final/1e9);
fprintf('Oracle exact BER      : %.6e\n', exact_oracle.overall_ber);
fprintf('DP terminal states    : %d\n', exact_oracle.terminal_state_count);
fprintf('============================================================\n');

% C. Single conservative Q24 LUT + global margin
rtl_lut_global = run_global_model_rtl_matched( ...
    snr_db_q16, snr_linear_q16, Fs, N_FFT, N_CP, ...
    base_th_q16, K_q16_map, C_q16_map, ...
    TARGET_BER_NUM, TARGET_BER_DEN, MARGIN_STEP_Q16_RTL, max_iter);

fitted_ber_global = compute_total_ber_rtl_custom_q24( ...
    rtl_lut_global.M_alloc_final, rtl_lut_global.Bits_alloc_final, ...
    snr_linear_q16, K_q16_map, C_q16_map);

res_lut_global = make_result_struct( ...
    'C) Conservative Q24 LUT + Bit-Weighted Global Margin', ...
    rtl_lut_global.M_alloc_final, rtl_lut_global.Bits_alloc_final, ...
    rtl_lut_global.net_rate_final, ...
    fitted_ber_global, ...
    compute_total_ber('exact', rtl_lut_global.M_alloc_final, rtl_lut_global.Bits_alloc_final, SNR_linear_eval, K_map, C_map, lut_hw), ...
    rtl_lut_global.margins_db, rtl_lut_global.thresholds_db, rtl_lut_global.iter);

% D. Proposed engine: one conservative bank drives upward and refinement scans.
rtl_lut_indep = run_indep_model_rtl_matched( ...
    snr_db_q16, snr_linear_q16, Fs, N_FFT, N_CP, ...
    base_th_q16, K_q16_map, C_q16_map, ...
    TARGET_BER_NUM, TARGET_BER_DEN, MARGIN_STEP_Q16_RTL, max_iter);

fitted_ber_proposed = compute_total_ber_rtl_custom_q24( ...
    rtl_lut_indep.M_alloc_final, rtl_lut_indep.Bits_alloc_final, ...
    snr_linear_q16, K_q16_map, C_q16_map);
true_ber_proposed = compute_total_ber('exact', ...
    rtl_lut_indep.M_alloc_final, rtl_lut_indep.Bits_alloc_final, ...
    SNR_linear_eval, K_map, C_map, lut_hw);

res_proposed = make_result_struct( ...
    'D) Proposed Engine: Conservative Q24 LUT + Per-QAM Refinement', ...
    rtl_lut_indep.M_alloc_final, rtl_lut_indep.Bits_alloc_final, ...
    rtl_lut_indep.net_rate_final, ...
    fitted_ber_proposed, true_ber_proposed, ...
    rtl_lut_indep.margins_db, rtl_lut_indep.thresholds_db, rtl_lut_indep.iter);

%% ========================================================================
%% 6. Single-Estimator Proposed-Engine Result
%% ========================================================================
M_alloc_proposed = res_proposed.M_alloc;
Bits_alloc_proposed = res_proposed.Bits_alloc;
net_rate_proposed = res_proposed.net_rate;
final_margins_q16 = rtl_lut_indep.margins_q16;
final_margins_db = rtl_lut_indep.margins_db;
final_thresholds_db = rtl_lut_indep.thresholds_db;

[rtl_expected_weighted_err_q24, rtl_expected_total_bits] = ...
    rtl_bitweighted_error_sums_custom_q24( ...
    M_alloc_proposed, Bits_alloc_proposed, snr_linear_q16, ...
    K_q16_map, C_q16_map);
rtl_expected_pass = bitweighted_target_met( ...
    rtl_expected_weighted_err_q24, rtl_expected_total_bits, ...
    TARGET_BER_NUM, TARGET_BER_DEN);

if ~rtl_expected_pass
    error('The conservative-Q24 controller stopped without satisfying its guarded target.');
end
res_proposed.valid = true_ber_proposed <= Target_BER;

% Scan-only latency estimate for a one-tone-per-cycle reused datapath.
upward_scans = rtl_lut_indep.iter + 1;
refinement_scans = rtl_lut_indep.refinement_scans;
search_scans = upward_scans + refinement_scans;
tone_evals = (search_scans + 1) * N_subcarriers; % + final allocation stream
scan_time_us_est = 1e6 * tone_evals / LATENCY_EST_CLOCK_HZ;

fprintf('\n============================================================\n');
fprintf('[Single Conservative-BER Proposed-Engine Result]\n');
fprintf('The same conservative Q16 K/C bank and Q24 BER path are used in every scan.\n');
fprintf('Exact erfc is used only for offline reporting.\n');
fprintf('------------------------------------------------------------\n');
fprintf('Final margin [4 16 64 256] = [%.4f %.4f %.4f %.4f] dB\n', final_margins_db);
fprintf('Final threshold [4 16 64 256] = [%.4f %.4f %.4f %.4f] dB\n', final_thresholds_db);
fprintf('Net Rate = %.6f Gbps\n', net_rate_proposed / 1e9);
fprintf('Runtime conservative-Q24 BER = %.6e (guarded limit %.6e)\n', ...
    fitted_ber_proposed, RUNTIME_BER_LIMIT);
fprintf('Offline exact BER      = %.6e (system target %.1e)\n', ...
    true_ber_proposed, Target_BER);
fprintf('------------------------------------------------------------\n');
fprintf('[Scan-only latency estimate @ %.0f MHz, one tone/cycle]\n', LATENCY_EST_CLOCK_HZ/1e6);
fprintf('Upward scans = %d, refinement scans = %d, accepted decrements = %d\n', ...
    upward_scans, refinement_scans, rtl_lut_indep.refinement_accepts);
fprintf('Total tone evaluations including final stream = %d\n', tone_evals);
fprintf('Estimated scan time = %.3f us (pipeline/FSM overhead excluded)\n', scan_time_us_est);
fprintf('============================================================\n');

if ~res_proposed.valid
    error(['Offline exact BER exceeds the system target despite the one-sided fit and residual guard. ' ...
           'Check coefficient/domain consistency before using this result.']);
end

oracle_total_bits = sum(res_exact_oracle.Bits_alloc);
proposed_total_bits = sum(res_proposed.Bits_alloc);
oracle_qam_set = [4 16 64 256];
expected_proposed_bits = zeros(size(res_proposed.M_alloc));
for qidx = 1:4
    expected_proposed_bits(res_proposed.M_alloc == oracle_qam_set(qidx)) = 2*qidx;
end
if any(~ismember(res_proposed.M_alloc, [0 oracle_qam_set]))
    error('Proposed allocation contains a QAM option absent from the oracle.');
end
if ~isequal(res_proposed.Bits_alloc, expected_proposed_bits)
    error('Proposed M/bit allocation mapping is inconsistent with the oracle.');
end
for qidx = 1:4
    proposed_assigned = (res_proposed.M_alloc == oracle_qam_set(qidx));
    if any(snr_db_q16(proposed_assigned) < base_th_q16(qidx))
        error('Proposed allocation is outside the oracle candidate set.');
    end
end
if res_proposed.trueBER <= Target_BER * (1 + 1e-10) && ...
   oracle_total_bits < proposed_total_bits
    error(['DP oracle loaded fewer bits than an exact-feasible proposed ', ...
           'allocation. This indicates an oracle candidate/DP bug.']);
end
rate_gap_final = res_exact_oracle.net_rate - res_proposed.net_rate;
fprintf('Rate gap to exact-erfc DP oracle = %.6f Gbps (%d bits/symbol)\n', ...
    rate_gap_final/1e9, oracle_total_bits - proposed_total_bits);

%% 7. Export MATLAB Final Reference for Verilog Comparison
%% ========================================================================
% Tier mapping must match Verilog:
%   4 = 256-QAM, 3 = 64-QAM, 2 = 16-QAM, 1 = 4-QAM, 0 = unused
qam_tier_ref = zeros(1, N_subcarriers);
qam_tier_ref(M_alloc_proposed == 4)   = 1;
qam_tier_ref(M_alloc_proposed == 16)  = 2;
qam_tier_ref(M_alloc_proposed == 64)  = 3;
qam_tier_ref(M_alloc_proposed == 256) = 4;

fid = fopen('rx_a_qam_ref.mem', 'w');
for k = 1:N_subcarriers
    fprintf(fid, '%01X\n', uint32(qam_tier_ref(k)));
end
fclose(fid);

% Machine-readable self-check metadata matching the final RTL outputs.
rtl_weighted_u64 = uint64(rtl_expected_weighted_err_q24);
rtl_weighted_low = uint32(bitand(rtl_weighted_u64, uint64(4294967295)));
rtl_weighted_high = uint32(bitshift(rtl_weighted_u64, -32));

rtl_expected_words = uint32([ ...
    rtl_lut_indep.refinement_accepts, ...       % 0 accepted decrements
    rtl_lut_indep.refinement_scans, ...         % 1 candidate scans
    rtl_lut_indep.iter, ...                     % 2 upward updates
    final_margins_q16(1), ...                   % 3 margin 4
    final_margins_q16(2), ...                   % 4 margin 16
    final_margins_q16(3), ...                   % 5 margin 64
    final_margins_q16(4), ...                   % 6 margin 256
    rtl_expected_total_bits, ...                % 7
    rtl_weighted_low, ...                       % 8
    rtl_weighted_high, ...                      % 9
    rtl_expected_pass]);                        % 10

fid = fopen('rx_a_expected.mem', 'w');
for k = 1:length(rtl_expected_words)
    fprintf(fid, '%08X\n', rtl_expected_words(k));
end
fclose(fid);

fid = fopen('rx_a_summary.txt', 'w');
fprintf(fid, '[MATLAB Single Conservative-Q24 Allocation Reference]\n');
fprintf(fid, 'Final margin [4 16 64 256] = [%.4f %.4f %.4f %.4f] dB\n', final_margins_db);
fprintf(fid, 'Final threshold [4 16 64 256] = [%.4f %.4f %.4f %.4f] dB\n', final_thresholds_db);
fprintf(fid, 'QAM count [4 16 64 256] = [%d %d %d %d]\n', ...
    res_proposed.qam_count(1), res_proposed.qam_count(2), ...
    res_proposed.qam_count(3), res_proposed.qam_count(4));
fprintf(fid, 'Unused = %d\n', sum(M_alloc_proposed == 0));
fprintf(fid, 'Total loaded bits per OFDM symbol = %d\n', sum(Bits_alloc_proposed));
fprintf(fid, 'Estimated net data rate = %.6f Gbps\n', net_rate_proposed / 1e9);
fprintf(fid, 'Runtime conservative-Q24 BER = %.6e\n', fitted_ber_proposed);
fprintf(fid, 'Offline exact BER by erfc = %.6e\n', true_ber_proposed);
fclose(fid);

fprintf('\n============================================================\n');
fprintf('[MATLAB Reference Export for Verilog Comparison]\n');
fprintf('Exported rx_a_qam_ref.mem\n');
fprintf('Exported rx_a_expected.mem\n');
fprintf('Exported rx_a_summary.txt\n');
fprintf('Reference total bits = %d\n', sum(Bits_alloc_proposed));
fprintf('Reference net rate   = %.6f Gbps\n', net_rate_proposed / 1e9);
fprintf('Reference QAM count [4 16 64 256] = [%d %d %d %d], unused=%d\n', ...
    res_proposed.qam_count(1), res_proposed.qam_count(2), ...
    res_proposed.qam_count(3), res_proposed.qam_count(4), ...
    sum(M_alloc_proposed == 0));
fprintf('============================================================\n');

%% 8. Summary Table
%% ========================================================================
results = [ ...
    res_exact_global, ...
    res_exact_oracle, ...
    res_lut_global, ...
    res_proposed ...
];

fprintf('\n============================================================\n');
fprintf('[Final Controller-Level Comparison]\n');
fprintf('The proposed engine uses one conservative-Q24 LUT estimator throughout.\n');
fprintf(['The exact-erfc DP oracle is the offline global optimum over the same ', ...
         'QAM/base-threshold candidates.\n']);
fprintf('The exact-erfc global-margin controller is an ablation, not the oracle.\n');
fprintf('============================================================\n');
fprintf('%-62s | Rate(Gbps) | Runtime BER | Exact BER  | Iter | QAM count [4 16 64 256]\n', 'Method');
fprintf('%s\n', repmat('-', 1, 145));

for i = 1:length(results)
    r = results(i);
    fprintf('%-62s | %9.3f | %.3e | %.3e | %4d | [%3d %3d %3d %3d]\n', ...
        r.name, r.net_rate / 1e9, r.predBER, r.trueBER, r.iter, ...
        r.qam_count(1), r.qam_count(2), r.qam_count(3), r.qam_count(4));
end
fprintf('============================================================\n');

%% ========================================================================
%% 9. Visualization 1 - Final Paper Figure 1
%% ========================================================================
% For the paper, only the two most important end results are shown:
%   1) Exact-erfc dynamic-programming oracle allocation
%   2) Proposed engine allocation
% All displayed BER values are recalculated OFFLINE with the exact-erfc BER
% expression using each method's FINAL QAM allocation.

ber_B = compute_total_ber('exact', ...
    res_exact_oracle.M_alloc, res_exact_oracle.Bits_alloc, ...
    SNR_linear_eval, K_map, C_map, lut_hw);

ber_proposed = compute_total_ber('exact', ...
    res_proposed.M_alloc, res_proposed.Bits_alloc, ...
    SNR_linear_eval, K_map, C_map, lut_hw);

figure('Name', 'Figure 1: Exact-erfc DP Oracle vs Proposed Engine', ...
    'Position', [100, 100, 1450, 570], 'Color', 'w');

y_min = -35;
y_max = 5;

subplot(1, 2, 1);
plot_allocation(f_axis_GHz, df, H_mag_dB_plot, res_exact_oracle.M_alloc, ...
    y_min, y_max, sprintf([ ...
        'Exact-erfc DP Oracle Allocation\n' ...
        'Rate %.3f Gbps | BER %.3e'], ...
        res_exact_oracle.net_rate/1e9, ber_B));

subplot(1, 2, 2);
plot_allocation(f_axis_GHz, df, H_mag_dB_plot, res_proposed.M_alloc, ...
    y_min, y_max, sprintf([ ...
        'Proposed Engine Allocation (Conservative Q24 LUT)\n' ...
        'Rate %.3f Gbps | Runtime BER %.3e\nOffline exact BER %.3e'], ...
        res_proposed.net_rate/1e9, fitted_ber_proposed, ber_proposed));

%% ========================================================================
%% 10. Visualization 2 - Conservative LUT vs Exact erfc BER Curves
%% ========================================================================
% Paper-style single-panel comparison.
%   - LUT approximation : solid line
%   - Exact erfc        : dashed line
%   - One color per QAM order
%   - No crossing-point annotations
%   - Target BER is fixed at 1e-4

figure('Name', 'Combined QAM BER Curves: LUT vs Exact erfc', ...
    'Position', [200, 150, 1050, 700], 'Color', 'w');

qam_colors = lines(length(qam_list));
legend_handles = gobjects(1, 2 * length(qam_list) + 1);
legend_labels = cell(1, 2 * length(qam_list) + 1);

hold on;
grid on;
box on;

for i = 1:length(qam_list)
    M = qam_list(i);
    snr_lin_sweep = 10.^(snr_sweep_db / 10);

    ber_exact_curve = qam_ber_exact(M, snr_lin_sweep);

    % Use the continuous conservative exponential for visualization.  The
    % bit-accurate Q24 staircase remains in all controller/RTL comparisons.
    ber_lut_curve = qam_ber_lut(M, snr_lin_sweep, K_map, C_map, lut_hw);

    % LUT approximation: solid line
    h_lut = semilogy(snr_sweep_db, ber_lut_curve, '-', ...
        'Color', qam_colors(i, :), 'LineWidth', 2.2);

    % Exact erfc: dashed line
    h_exact = semilogy(snr_sweep_db, ber_exact_curve, '--', ...
        'Color', qam_colors(i, :), 'LineWidth', 2.2);

    legend_handles(2*i - 1) = h_lut;
    legend_handles(2*i) = h_exact;
    legend_labels{2*i - 1} = sprintf('%d-QAM Conservative LUT', M);
    legend_labels{2*i} = sprintf('%d-QAM Exact erfc', M);
end

% System target BER
h_target = yline(1e-4, ':', 'Target BER', ...
    'Color', [0 0 0], 'LineWidth', 1.7, ...
    'LabelHorizontalAlignment', 'right', ...
    'LabelVerticalAlignment', 'bottom');

legend_handles(end) = h_target;
legend_labels{end} = 'Target BER';

set(gca, ...
    'YScale', 'log', ...
    'FontSize', 12, ...
    'LineWidth', 1.0, ...
    'YMinorGrid', 'on', ...
    'XMinorGrid', 'on');

xlabel('SNR (dB)', 'FontSize', 13);
ylabel('BER', 'FontSize', 13);
title('QAM BER Curves: Conservative LUT vs Exact erfc', ...
    'FontSize', 14, 'FontWeight', 'normal');

xlim([0 35]);
ylim([1e-8 1]);
yticks(10.^(-8:2:0));

legend(legend_handles, legend_labels, ...
    'Location', 'southwest', ...
    'NumColumns', 2, ...
    'FontSize', 10);

% Optional paper-quality export:
% exportgraphics(gcf, 'Fig3_Combined_QAM_BER_Curves.png', 'Resolution', 300);
% exportgraphics(gcf, 'Fig3_Combined_QAM_BER_Curves.pdf', 'ContentType', 'vector');

%% ========================================================================
%% 11-13. Optional End-to-End OFDM Verification
%% ========================================================================
if RUN_E2E
%% ========================================================================
%% 11. End-to-End OFDM Waveform Verification
%% ========================================================================
fprintf('\n============================================================\n');
fprintf('[End-to-End OFDM Waveform Verification]\n');
fprintf('Assumption: perfect sync / CP-sufficient / perfect one-tap FDE\n');
fprintf('============================================================\n');

N_OFDM_SYM_E2E = 5000;   % Debug: 1000~3000, final plot: 10000~50000

H_full = ones(1, N_FFT);
H_full(1) = 1;
H_full(2:256) = H_exact;
H_full(257) = 1;
H_full(258:512) = conj(fliplr(H_exact));

e2e_cases = [ ...
    res_exact_oracle, ...
    res_lut_global, ...
    res_proposed ...
];

e2e_results = [];

for ci = 1:length(e2e_cases)
    fprintf('\nRunning E2E OFDM case %d/%d: %s\n', ci, length(e2e_cases), e2e_cases(ci).name);

    e2e_tmp = run_e2e_ofdm_case( ...
        e2e_cases(ci), N_OFDM_SYM_E2E, SNR_linear, ...
        H_full, H_exact, N_FFT, N_CP);

    if ci == 1
        e2e_results = repmat(e2e_tmp, 1, length(e2e_cases));
    end
    e2e_results(ci) = e2e_tmp;
end

fprintf('\n============================================================\n');
fprintf('[End-to-End OFDM BER Comparison]\n');
fprintf('N_OFDM_SYM = %d\n', N_OFDM_SYM_E2E);
fprintf('============================================================\n');
fprintf('%-62s | Rate(Gbps) | Analytical True BER | E2E Measured BER | Bits | Errors\n', 'Method');
fprintf('%s\n', repmat('-', 1, 135));

for ci = 1:length(e2e_results)
    fprintf('%-62s | %9.3f | %.3e           | %.3e          | %d | %d\n', ...
        e2e_results(ci).name, e2e_results(ci).net_rate / 1e9, ...
        e2e_results(ci).analytical_trueBER, e2e_results(ci).measuredBER, ...
        e2e_results(ci).totalBits, e2e_results(ci).errorBits);
end
fprintf('============================================================\n');

fprintf('\n[Analytical BER vs E2E BER Mismatch]\n');
for ci = 1:length(e2e_results)
    ana = e2e_results(ci).analytical_trueBER;
    meas = e2e_results(ci).measuredBER;
    ratio = meas / ana;
    fprintf('%-62s : E2E / Analytical = %.3f\n', e2e_results(ci).name, ratio);
end

%% ========================================================================
%% 12. Visualization 3 - Analytical BER vs E2E BER
%% ========================================================================
figure('Name', 'Analytical BER vs End-to-End OFDM BER', ...
    'Position', [250, 250, 1000, 500], 'Color', 'w');

case_labels = {'Exact DP Oracle', 'Conservative LUT Global', 'Proposed Conservative LUT'};
ana_ber = [e2e_results.analytical_trueBER];
meas_ber = [e2e_results.measuredBER];
bar_data = [ana_ber(:), meas_ber(:)];

bar(bar_data);
set(gca, 'YScale', 'log');
grid on;
ylabel('BER');
title('Controller Analytical BER vs End-to-End OFDM Measured BER');
set(gca, 'XTickLabel', case_labels);
legend('Analytical true BER', 'E2E measured BER', 'Location', 'best');
yline(Target_BER, '--', 'Target BER');

%% ========================================================================
%% 13. Visualization 4 - Rate vs E2E BER
%% ========================================================================
figure('Name', 'Net Rate vs End-to-End OFDM BER', ...
    'Position', [300, 300, 1000, 500], 'Color', 'w');

rate_e2e = [e2e_results.net_rate] / 1e9;
meas_ber_e2e = [e2e_results.measuredBER];

yyaxis left;
bar(rate_e2e);
ylabel('Net Data Rate (Gbps)');
ylim([0 max(rate_e2e)*1.15]);
grid on;

yyaxis right;
semilogy(1:length(meas_ber_e2e), meas_ber_e2e, '-o', 'LineWidth', 2);
ylabel('E2E Measured BER');
yline(Target_BER, '--', 'Target BER');

set(gca, 'XTick', 1:length(case_labels));
set(gca, 'XTickLabel', case_labels);
title('Net Rate and End-to-End OFDM Measured BER');



else
    fprintf('\n[E2E verification skipped] RUN_E2E=false\n');
end

%% ========================================================================
%% 14. Visualization 5 - Bit-Weighted Q24 Per-QAM Margin History
%% ========================================================================
% IMPORTANT:
% This version uses transmitted-bit-weighted BER:
%   sum(bits_k * BER_k) / sum(bits_k) <= Target_BER.
% For the guarded Q24 LUT path, the divider-free comparison is:
%   weighted_err_q24 * 10000 <= total_loaded_bits * 16617216.
% Tier selection still uses average per-tone BER and cross multiplication.
% The Verilog RTL must use the same single conservative K/C bank before a direct
% ModelSim cycle-by-cycle comparison is valid.

res_lut_indep_rtl = rtl_lut_indep;

margin_hist = res_lut_indep_rtl.margin_history_db;
update_idx = 0:(size(margin_hist, 1)-1);
final_margin_rtl = res_lut_indep_rtl.margins_db;
final_threshold_rtl = res_lut_indep_rtl.thresholds_db;
final_qam_count_rtl = res_lut_indep_rtl.qam_count_final; % [4 16 64 256 unused]

fprintf('\n============================================================\n');
fprintf('[Bit-Weighted Q24 MATLAB Margin History]\n');
fprintf('This uses Q16 SNR/LUT, Q24 BER, guarded target control, and local refinement.\n');
fprintf('Total margin updates = %d\n', res_lut_indep_rtl.iter);
fprintf('Refinement accepts/scans = %d / %d\n', ...
    res_lut_indep_rtl.refinement_accepts, res_lut_indep_rtl.refinement_scans);
fprintf('Final Margin 256-QAM = %.4f dB\n', final_margin_rtl(4));
fprintf('Final Margin  64-QAM = %.4f dB\n', final_margin_rtl(3));
fprintf('Final Margin  16-QAM = %.4f dB\n', final_margin_rtl(2));
fprintf('Final Margin   4-QAM = %.4f dB\n', final_margin_rtl(1));
fprintf('------------------------------------------------------------\n');
fprintf('Final allocation count\n');
fprintf('256-QAM = %d\n', final_qam_count_rtl(4));
fprintf(' 64-QAM = %d\n', final_qam_count_rtl(3));
fprintf(' 16-QAM = %d\n', final_qam_count_rtl(2));
fprintf('  4-QAM = %d\n', final_qam_count_rtl(1));
fprintf(' unused = %d\n', final_qam_count_rtl(5));
fprintf('Total loaded bits per OFDM symbol = %d\n', sum(res_lut_indep_rtl.Bits_alloc_final));
fprintf('Estimated net data rate = %.6f Gbps\n', res_lut_indep_rtl.net_rate_final / 1e9);
fprintf('============================================================\n');

% Export RTL-matched margin history to text files for direct comparison.
fid = fopen('matlab_rtlmatched_margin_history.csv', 'w');
fprintf(fid, 'update_idx,margin_4qam_db,margin_16qam_db,margin_64qam_db,margin_256qam_db\n');
for ii = 1:size(margin_hist, 1)
    fprintf(fid, '%d,%.6f,%.6f,%.6f,%.6f\n', ...
        ii-1, margin_hist(ii,1), margin_hist(ii,2), margin_hist(ii,3), margin_hist(ii,4));
end
fclose(fid);

fid = fopen('matlab_rtlmatched_margin_summary.txt', 'w');
fprintf(fid, '[Bit-Weighted Q24 MATLAB Margin Summary]\n');
fprintf(fid, 'Total margin updates = %d\n', res_lut_indep_rtl.iter);
fprintf(fid, 'Refinement accepts/scans = %d / %d\n', ...
    res_lut_indep_rtl.refinement_accepts, res_lut_indep_rtl.refinement_scans);
fprintf(fid, 'Final Margin 256-QAM = %.4f dB\n', final_margin_rtl(4));
fprintf(fid, 'Final Margin  64-QAM = %.4f dB\n', final_margin_rtl(3));
fprintf(fid, 'Final Margin  16-QAM = %.4f dB\n', final_margin_rtl(2));
fprintf(fid, 'Final Margin   4-QAM = %.4f dB\n', final_margin_rtl(1));
fprintf(fid, 'Final allocation count [4 16 64 256 unused] = [%d %d %d %d %d]\n', ...
    final_qam_count_rtl(1), final_qam_count_rtl(2), final_qam_count_rtl(3), ...
    final_qam_count_rtl(4), final_qam_count_rtl(5));
fprintf(fid, 'Total loaded bits per OFDM symbol = %d\n', sum(res_lut_indep_rtl.Bits_alloc_final));
fprintf(fid, 'Estimated net data rate = %.6f Gbps\n', res_lut_indep_rtl.net_rate_final / 1e9);
fclose(fid);

figure('Name', 'RTL-Matched Per-QAM Margin History and Final Allocation', ...
    'Position', [350, 120, 1300, 850], 'Color', 'w');

subplot(2, 2, 1);
plot(update_idx, margin_hist(:,1), 'LineWidth', 2); hold on;
plot(update_idx, margin_hist(:,2), 'LineWidth', 2);
plot(update_idx, margin_hist(:,3), 'LineWidth', 2);
plot(update_idx, margin_hist(:,4), 'LineWidth', 2);
grid on;
xlabel('Margin update count');
ylabel('Margin (dB)');
title(sprintf('Q24 Per-QAM Margin Evolution: %d up, %d down', ...
    res_lut_indep_rtl.iter, res_lut_indep_rtl.refinement_accepts));
legend('4-QAM', '16-QAM', '64-QAM', '256-QAM', 'Location', 'best');

subplot(2, 2, 2);
bar(final_margin_rtl);
grid on;
ylabel('Final margin (dB)');
title('Final Margin after Bit-Weighted LUT Independent Loop');
set(gca, 'XTickLabel', {'4-QAM','16-QAM','64-QAM','256-QAM'});
for ii = 1:4
    text(ii, final_margin_rtl(ii), sprintf('%.2f', final_margin_rtl(ii)), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
end

subplot(2, 2, 3);
bar(final_threshold_rtl);
grid on;
ylabel('Final threshold (dB)');
title('Final Threshold from Single Conservative-LUT Margin Control');
set(gca, 'XTickLabel', {'4-QAM','16-QAM','64-QAM','256-QAM'});
for ii = 1:4
    text(ii, final_threshold_rtl(ii), sprintf('%.2f', final_threshold_rtl(ii)), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
end

subplot(2, 2, 4);
bar(final_qam_count_rtl);
grid on;
ylabel('Number of subcarriers');
title(sprintf('Bit-Weighted Final Allocation, bits = %d, rate = %.4f Gbps', ...
    sum(res_lut_indep_rtl.Bits_alloc_final), res_lut_indep_rtl.net_rate_final / 1e9));
set(gca, 'XTickLabel', {'4-QAM','16-QAM','64-QAM','256-QAM','Unused'});
for ii = 1:5
    text(ii, final_qam_count_rtl(ii), sprintf('%d', final_qam_count_rtl(ii)), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
end

%% ========================================================================
%% 15. Two-TRX Bidirectional Extension
%% ========================================================================
% The top-level controller result above is Engine A:
%   RX_A(B->A measured SNR) -> Engine A -> TX_A(A->B)
% and the same map is used by peer RX_B.
ENGINE_A = res_proposed;
TX_A_MAP = ENGINE_A.M_alloc;
RX_B_MAP = TX_A_MAP;

% Run a second, identical controller instance for Engine B:
%   RX_B(A->B measured SNR) -> Engine B -> TX_B(B->A)
% and the same map is used by peer RX_A.
ENGINE_B = run_local_engine_final( ...
    snr_b_db_q16, snr_b_linear_q16, ...
    Fs, N_FFT, N_CP, Target_BER, ...
    base_th_q16, ...
    K_map, C_map, lut_hw, ...
    K_q16_map, C_q16_map, ...
    TARGET_BER_NUM, TARGET_BER_DEN, ...
    MARGIN_STEP_Q16_RTL, max_iter);

TX_B_MAP = ENGINE_B.M_alloc;
RX_A_MAP = TX_B_MAP;

% Explicit mapper/demapper consistency checks.
assert(isequal(TX_A_MAP, RX_B_MAP), ...
    'A->B map mismatch: TX_A and RX_B must use the same allocation.');
assert(isequal(TX_B_MAP, RX_A_MAP), ...
    'B->A map mismatch: TX_B and RX_A must use the same allocation.');

% In the default reciprocal + symmetric baseline, both engines
% see identical SNR profiles, so their maps should also be identical.
if isequal(snr_db_q16, snr_b_db_q16) && isequal(snr_linear_q16, snr_b_linear_q16)
    assert(isequal(TX_A_MAP, TX_B_MAP), ...
        'Symmetric baseline error: Engine A and Engine B allocations differ.');
end

fprintf('\n============================================================\n');
fprintf('[TWO-TRX LOCAL RX -> LOCAL TX CHECK]\n');
fprintf('One physical cable: max|H_AB-H_BA| = %.3e\n', max(abs(H_AB-H_BA)));
fprintf('Engine A -> TX_A / RX_B : bits/sym=%d, rate=%.6f Gbps, BER=%.3e\n', ...
    sum(ENGINE_A.Bits_alloc), ENGINE_A.net_rate/1e9, ENGINE_A.trueBER);
fprintf('Engine B -> TX_B / RX_A : bits/sym=%d, rate=%.6f Gbps, BER=%.3e\n', ...
    sum(ENGINE_B.Bits_alloc), ENGINE_B.net_rate/1e9, ENGINE_B.trueBER);
fprintf('Map consistency A->B: TX_A == RX_B : PASS\n');
fprintf('Map consistency B->A: TX_B == RX_A : PASS\n');
fprintf('============================================================\n');

% Export Engine-B reference.  Existing Engine-A rx_a_* export above is kept.
export_engine_b_reference( ...
    'rx_b', snr_b_db_q16, snr_b_linear_q16, ENGINE_B, ...
    K_q16_map, C_q16_map, ...
    TARGET_BER_NUM, TARGET_BER_DEN);

%% ========================================================================
%% 16. Bidirectional E2E Check over the SAME Cable
%% ========================================================================
if RUN_E2E
    H_full_AB = ones(1, N_FFT);
    H_full_AB(1) = 1;
    H_full_AB(2:256) = H_AB;
    H_full_AB(257) = 1;
    H_full_AB(258:512) = conj(fliplr(H_AB));

    H_full_BA = ones(1, N_FFT);
    H_full_BA(1) = 1;
    H_full_BA(2:256) = H_BA;
    H_full_BA(257) = 1;
    H_full_BA(258:512) = conj(fliplr(H_BA));

    % A->B: Engine A configures TX_A; peer RX_B uses the same map.
    e2e_A_to_B = run_e2e_ofdm_case( ...
        ENGINE_A, N_OFDM_SYM_E2E, 10.^(SNR_ENGINE_A_dB/10), ...
        H_full_AB, H_AB, N_FFT, N_CP);

    % B->A: Engine B configures TX_B; peer RX_A uses the same map.
    e2e_B_to_A = run_e2e_ofdm_case( ...
        ENGINE_B, N_OFDM_SYM_E2E, 10.^(SNR_ENGINE_B_dB/10), ...
        H_full_BA, H_BA, N_FFT, N_CP);

    fprintf('\n============================================================\n');
    fprintf('[BIDIRECTIONAL E2E OFDM / ONE CABLE]\n');
    fprintf('A->B  TX_A -> RX_B : BER=%.6e, bits=%d, errors=%d\n', ...
        e2e_A_to_B.measuredBER, e2e_A_to_B.totalBits, e2e_A_to_B.errorBits);
    fprintf('B->A  TX_B -> RX_A : BER=%.6e, bits=%d, errors=%d\n', ...
        e2e_B_to_A.measuredBER, e2e_B_to_A.totalBits, e2e_B_to_A.errorBits);
    fprintf('============================================================\n');
end

%% ========================================================================
%% 17. Visualization 6 - Bidirectional TRX Allocation
%% ========================================================================
% Figures 1-6 above are the existing controller figures.
figure('Name', 'Figure 6: Bidirectional TRX Allocation over One Cable', ...
       'Position', [250, 180, 1050, 650], 'Color', 'w');

subplot(2,1,1);
stairs(f_axis_GHz, ENGINE_A.Bits_alloc, 'LineWidth', 1.6);
grid on;
ylim([-0.5 8.5]);
yticks([0 2 4 6 8]);
ylabel('Bits / subcarrier');
title('A->B: RX_A SNR -> Engine A -> TX_A / RX_B');

subplot(2,1,2);
stairs(f_axis_GHz, ENGINE_B.Bits_alloc, 'LineWidth', 1.6);
grid on;
ylim([-0.5 8.5]);
yticks([0 2 4 6 8]);
xlabel('Frequency (GHz)');
ylabel('Bits / subcarrier');
title('B->A: RX_B SNR -> Engine B -> TX_B / RX_A');


%% ========================================================================
%% 18. Visualization 7 - Sensitivity to Directional SNR Mismatch
%% ========================================================================
% PURPOSE:
% Characterize the operating range of the single conservative-LUT controller under a
% violation of the symmetric bidirectional-SNR assumption.
%
% IMPORTANT:
% - No robustness guard is added.
% - No extra calibration block is added.
% - The nominal conservative-LUT per-QAM-margin result is unchanged.
% - The nominal QAM allocation is FIXED during this sensitivity sweep.
% - The controller is NOT rerun for each mismatch value.
%
% System interpretation:
%   Engine A uses the SNR observed at RX_A (B->A) to configure LOCAL TX_A
%   for the opposite A->B direction.
%
%   Engine B uses the SNR observed at RX_B (A->B) to configure LOCAL TX_B
%   for the opposite B->A direction.
%
% The nominal system assumes:
%   SNR_A_to_B ~= SNR_B_to_A
%
% Sensitivity test:
%   actual outgoing SNR = local-RX observed SNR - Delta_SNR
%
% Delta_SNR >= 0 represents the adverse case in which the actual outgoing
% direction is worse than the locally observed opposite direction.
%
% The resulting crossing with Target_BER is reported as the directional
% SNR-mismatch tolerance of the evaluated nominal allocation.

SENSITIVITY_MAX_LOSS_DB = 2.0;
SENSITIVITY_STEP_DB = 0.05;
mismatch_loss_db = 0:SENSITIVITY_STEP_DB:SENSITIVITY_MAX_LOSS_DB;

ber_mismatch_A_to_B = zeros(size(mismatch_loss_db));
ber_mismatch_B_to_A = zeros(size(mismatch_loss_db));

for mi = 1:length(mismatch_loss_db)
    Delta_SNR_dB = mismatch_loss_db(mi);

    % ---------------------------------------------------------------
    % A->B sensitivity
    % Engine A keeps the nominal TX_A/RX_B allocation.
    % Only the actual A->B link SNR is reduced.
    % ---------------------------------------------------------------
    actual_A_to_B_snr_db = SNR_RX_A_IN_dB - Delta_SNR_dB;
    actual_A_to_B_snr_linear = 10.^(actual_A_to_B_snr_db/10);

    ber_mismatch_A_to_B(mi) = compute_total_ber( ...
        'exact', ENGINE_A.M_alloc, ENGINE_A.Bits_alloc, ...
        actual_A_to_B_snr_linear, K_map, C_map, lut_hw);

    % ---------------------------------------------------------------
    % B->A sensitivity
    % Engine B keeps the nominal TX_B/RX_A allocation.
    % Only the actual B->A link SNR is reduced.
    % ---------------------------------------------------------------
    actual_B_to_A_snr_db = SNR_RX_B_IN_dB - Delta_SNR_dB;
    actual_B_to_A_snr_linear = 10.^(actual_B_to_A_snr_db/10);

    ber_mismatch_B_to_A(mi) = compute_total_ber( ...
        'exact', ENGINE_B.M_alloc, ENGINE_B.Bits_alloc, ...
        actual_B_to_A_snr_linear, K_map, C_map, lut_hw);
end

% Per-direction BER-target crossing.
tol_A_to_B_db = estimate_tolerable_snr_loss( ...
    mismatch_loss_db, ber_mismatch_A_to_B, Target_BER);

tol_B_to_A_db = estimate_tolerable_snr_loss( ...
    mismatch_loss_db, ber_mismatch_B_to_A, Target_BER);

% Conservative system tolerance: BOTH directions must still meet the target.
tol_bidir_db = min(tol_A_to_B_db, tol_B_to_A_db);

fprintf('\n============================================================\n');
fprintf('[DIRECTIONAL SNR-MISMATCH SENSITIVITY]\n');
fprintf('No guard / no extra calibration / nominal allocation fixed.\n');
fprintf('Definition: actual outgoing SNR = local-RX observed SNR - Delta_SNR\n');
fprintf('Controller is NOT rerun during the mismatch sweep.\n');
fprintf('Sweep resolution = %.3f dB, maximum tested mismatch = %.2f dB\n', ...
    SENSITIVITY_STEP_DB, SENSITIVITY_MAX_LOSS_DB);
fprintf('------------------------------------------------------------\n');
fprintf('A->B BER-target tolerance = %.3f dB\n', tol_A_to_B_db);
fprintf('B->A BER-target tolerance = %.3f dB\n', tol_B_to_A_db);
fprintf('Bidirectional conservative tolerance = %.3f dB\n', tol_bidir_db);
fprintf('Criterion: exact bit-weighted BER <= %.1e in BOTH directions\n', Target_BER);
fprintf('------------------------------------------------------------\n');
fprintf('This value is the sensitivity of THIS evaluated allocation;\n');
fprintf('it is NOT a claim about the typical SNR mismatch of all wireline TRXs.\n');
fprintf('============================================================\n');

figure('Name', 'Figure 7: Sensitivity to Directional SNR Mismatch', ...
       'Position', [300, 180, 1050, 620], 'Color', 'w');

semilogy(mismatch_loss_db, ber_mismatch_A_to_B, '-', 'LineWidth', 2.0);
hold on;
semilogy(mismatch_loss_db, ber_mismatch_B_to_A, '--', 'LineWidth', 2.0);
yline(Target_BER, ':', 'Target BER', 'LineWidth', 1.7);

if tol_bidir_db < SENSITIVITY_MAX_LOSS_DB
    xline(tol_bidir_db, '-.', ...
        sprintf('Tolerance = %.2f dB', tol_bidir_db), ...
        'LineWidth', 1.5, ...
        'LabelVerticalAlignment', 'middle');
end

grid on;
box on;
xlabel('Adverse directional SNR mismatch, \DeltaSNR (dB)');
ylabel('Exact bit-weighted BER');
title('Sensitivity of Nominal Local-RX-to-Local-TX Allocation');

legend('A->B: fixed Engine-A allocation', ...
       'B->A: fixed Engine-B allocation', ...
       'Target BER', ...
       'Location', 'northwest');

xlim([0 SENSITIVITY_MAX_LOSS_DB]);
ylim([1e-7 1e-2]);

if tol_bidir_db >= SENSITIVITY_MAX_LOSS_DB
    text(0.98*SENSITIVITY_MAX_LOSS_DB, 2.0e-4, ...
        sprintf('Tolerance > %.1f dB (tested range)', ...
        SENSITIVITY_MAX_LOSS_DB), ...
        'HorizontalAlignment', 'right');
else
    text(0.98*SENSITIVITY_MAX_LOSS_DB, 2.0e-4, ...
        sprintf('Target BER maintained up to about %.2f dB adverse mismatch', ...
        tol_bidir_db), ...
        'HorizontalAlignment', 'right');
end




function tol_db = estimate_tolerable_snr_loss(loss_db, ber_curve, target_ber)
% Estimate the BER-target crossing in log10(BER) versus SNR-loss space.
% BER is monotonic nondecreasing with loss for a fixed allocation.

    pass_idx = find(ber_curve <= target_ber);

    if isempty(pass_idx)
        tol_db = 0.0;
        return;
    end

    last_pass = pass_idx(end);

    if last_pass >= length(loss_db)
        % The entire tested range still satisfies the target.
        tol_db = loss_db(end);
        return;
    end

    x1 = loss_db(last_pass);
    x2 = loss_db(last_pass + 1);

    y1 = max(ber_curve(last_pass), realmin);
    y2 = max(ber_curve(last_pass + 1), realmin);

    ly1 = log10(y1);
    ly2 = log10(y2);
    lyt = log10(target_ber);

    if abs(ly2 - ly1) < 1e-15
        tol_db = x1;
    else
        frac = (lyt - ly1) / (ly2 - ly1);
        frac = min(max(frac, 0), 1);
        tol_db = x1 + frac * (x2 - x1);
    end
end


function res_final = run_local_engine_final( ...
    snr_db_q16, snr_linear_q16, ...
    Fs, N_FFT, N_CP, Target_BER, ...
    base_th_q16, ...
    K_map, C_map, lut_hw, ...
    K_q16_map, C_q16_map, ...
    TARGET_BER_NUM, TARGET_BER_DEN, ...
    MARGIN_STEP_Q16_RTL, max_iter)

    SNR_linear_eval = double(snr_linear_q16) / 65536;

    % The second TRX uses the same conservative-Q24 estimator as Engine A.
    rtl_lut_indep_b = run_indep_model_rtl_matched( ...
        snr_db_q16, snr_linear_q16, Fs, N_FFT, N_CP, ...
        base_th_q16, K_q16_map, C_q16_map, ...
        TARGET_BER_NUM, TARGET_BER_DEN, ...
        MARGIN_STEP_Q16_RTL, max_iter);

    fitted_ber = compute_total_ber_rtl_custom_q24( ...
        rtl_lut_indep_b.M_alloc_final, rtl_lut_indep_b.Bits_alloc_final, ...
        snr_linear_q16, K_q16_map, C_q16_map);
    true_ber = compute_total_ber( ...
        'exact', rtl_lut_indep_b.M_alloc_final, rtl_lut_indep_b.Bits_alloc_final, ...
        SNR_linear_eval, K_map, C_map, lut_hw);

    res_final = make_result_struct( ...
        'Engine B Single Conservative-Q24 LUT', ...
        rtl_lut_indep_b.M_alloc_final, rtl_lut_indep_b.Bits_alloc_final, ...
        rtl_lut_indep_b.net_rate_final, fitted_ber, true_ber, ...
        rtl_lut_indep_b.margins_db, ...
        rtl_lut_indep_b.thresholds_db, rtl_lut_indep_b.iter);

    res_final.valid = true_ber <= Target_BER;
    res_final.margins_q16 = rtl_lut_indep_b.margins_q16;
    res_final.refinement_accepts = rtl_lut_indep_b.refinement_accepts;
    res_final.refinement_scans = rtl_lut_indep_b.refinement_scans;
end


function export_engine_b_reference( ...
    prefix, snr_db_q16, snr_linear_q16, res_final, ...
    K_q16_map, C_q16_map, TARGET_BER_NUM, TARGET_BER_DEN)

    fid = fopen([prefix '_snr_db_q16.mem'], 'w');
    for k = 1:length(snr_db_q16)
        fprintf(fid, '%08X\n', uint32(snr_db_q16(k)));
    end
    fclose(fid);

    fid = fopen([prefix '_snr_linear_q16.mem'], 'w');
    for k = 1:length(snr_linear_q16)
        fprintf(fid, '%08X\n', uint32(snr_linear_q16(k)));
    end
    fclose(fid);

    qam_tier_ref = zeros(1, length(res_final.M_alloc));
    qam_tier_ref(res_final.M_alloc == 4)   = 1;
    qam_tier_ref(res_final.M_alloc == 16)  = 2;
    qam_tier_ref(res_final.M_alloc == 64)  = 3;
    qam_tier_ref(res_final.M_alloc == 256) = 4;

    fid = fopen([prefix '_qam_ref.mem'], 'w');
    for k = 1:length(qam_tier_ref)
        fprintf(fid, '%01X\n', uint32(qam_tier_ref(k)));
    end
    fclose(fid);

    [weighted_err_q24, total_bits] = ...
        rtl_bitweighted_error_sums_custom_q24( ...
        res_final.M_alloc, res_final.Bits_alloc, snr_linear_q16, ...
        K_q16_map, C_q16_map);

    expected_pass = bitweighted_target_met( ...
        weighted_err_q24, total_bits, TARGET_BER_NUM, TARGET_BER_DEN);

    fprintf('Exported Engine-B files: %s_snr_db_q16.mem, %s_snr_linear_q16.mem, %s_qam_ref.mem\n', ...
        prefix, prefix, prefix);
    fprintf('Engine-B conservative-Q24 target check = %d\n', expected_pass);
end


function [K_map, C_map, K_q16_map, C_q16_map] = ...
    load_conservative_ber_constants(qam_list)

    % Offline one-sided optimization result.  Order is [4 16 64 256].
    % Constants were selected against the actual Q16-K/Q16-C, 32-entry-LUT,
    % Q24-output arithmetic, rather than against an unquantized exponential.
    K_table = [50734 10213 2436 602];
    C_table = [12756 10206 8057 6506];

    K_map = zeros(1, 256);
    C_map = zeros(1, 256);
    K_q16_map = zeros(1, 256);
    C_q16_map = zeros(1, 256);

    for ii = 1:length(qam_list)
        M = qam_list(ii);
        K_q16_map(M) = K_table(ii);
        C_q16_map(M) = C_table(ii);
        K_map(M) = K_table(ii) / 65536;
        C_map(M) = C_table(ii) / 65536;
    end
end


function verify_conservative_ber_constants( ...
    qam_list, base_th, K_q16_map, C_q16_map, ber_frac, residual_bound)

    % Dense deterministic design-domain check.  The exact curve is required
    % to be no larger than the bit-accurate Q24 estimator whenever exact BER
    % is at least the residual bound.  Below that point the controller guard
    % covers the maximum omitted contribution.
    verify_db = 0:0.001:40;
    for ii = 1:length(qam_list)
        M = qam_list(ii);
        snr_lin = 10.^(verify_db / 10);
        snr_q16 = round(snr_lin * 65536);
        exact_ber = qam_ber_exact(M, double(snr_q16) / 65536);
        active = (verify_db >= base_th(ii)) & ...
                 (exact_ber >= residual_bound);

        est_q = zeros(size(verify_db));
        active_idx = find(active);
        for kk = 1:length(active_idx)
            jj = active_idx(kk);
            est_q(jj) = rtl_qam_ber_lut_err_q24_custom( ...
                M, snr_q16(jj), K_q16_map(M), C_q16_map(M));
        end
        est_ber = est_q / 2^ber_frac;

        if any(est_ber(active) + 1e-15 < exact_ber(active))
            error('Conservative Q24 estimator check failed for %d-QAM.', M);
        end
    end
end


function ber_total = compute_total_ber_rtl_custom_q24( ...
    M_alloc, Bits_alloc, snr_linear_q16, K_q16_map, C_q16_map)

    [weighted_err_q24, total_bits] = rtl_bitweighted_error_sums_custom_q24( ...
        M_alloc, Bits_alloc, snr_linear_q16, K_q16_map, C_q16_map);

    if total_bits == 0
        ber_total = 0;
    else
        ber_total = double(weighted_err_q24) / (double(total_bits) * 2^24);
    end
end


function [weighted_err_q24, total_bits] = ...
    rtl_bitweighted_error_sums_custom_q24( ...
    M_alloc, Bits_alloc, snr_linear_q16, K_q16_map, C_q16_map)

    weighted_err_q24 = 0;
    total_bits = 0;

    for kk = 1:length(M_alloc)
        M = M_alloc(kk);
        bits = Bits_alloc(kk);
        if M == 0 || bits == 0
            continue;
        end

        err_q24 = rtl_qam_ber_lut_err_q24_custom( ...
            M, snr_linear_q16(kk), K_q16_map(M), C_q16_map(M));
        weighted_err_q24 = weighted_err_q24 + bits * err_q24;
        total_bits = total_bits + bits;
    end
end


function err_q24 = rtl_qam_ber_lut_err_q24_custom( ...
    M, snr_linear_q16, k_const, c_const)

    if M == 0
        err_q24 = 0;
        return;
    end

    lut = [ ...
        65536, 64131, 62757, 61412, 60096, 58809, 57548, 56315, ...
        55108, 53928, 52772, 51641, 50535, 49452, 48392, 47355, ...
        46340, 45347, 44376, 43425, 42494, 41584, 40693, 39821, ...
        38967, 38132, 37315, 36516, 35733, 34968, 34218, 33485 ...
    ];

    y_mult = double(k_const) * double(snr_linear_q16);
    y_int = floor(y_mult / 2^32);
    y_frac = floor(mod(y_mult, 2^32) / 2^27);
    y_frac = min(max(y_frac, 0), 31);

    lut_val = lut(y_frac + 1);
    % C(Q16)*LUT(Q16) is Q32.  Shift by eight to retain a Q24 BER base.
    base = floor(double(c_const) * double(lut_val) / 2^8);

    % RTL retains a five-bit shift and forces zero when the exponent is >=24.
    if y_int >= 24
        err_q24 = 0;
    else
        err_q24 = floor(base / 2^y_int);
    end
end


function net_rate = compute_net_rate(Bits_alloc, Fs, N_FFT, N_CP)
    net_rate = (Fs * (sum(Bits_alloc) / N_FFT)) * (N_FFT / (N_FFT + N_CP));
end


function ber_total = compute_total_ber(ber_mode, M_alloc, Bits_alloc, SNR_linear, K_map, C_map, lut_hw)
    [ber_total, ~] = compute_total_ber_with_error_profile( ...
        ber_mode, M_alloc, Bits_alloc, SNR_linear, K_map, C_map, lut_hw);
end


function [ber_total, err_full] = compute_total_ber_with_error_profile( ...
    ber_mode, M_alloc, Bits_alloc, SNR_linear, K_map, C_map, lut_hw)

    active_idx = M_alloc > 0;
    err_full = zeros(size(M_alloc));

    if ~any(active_idx)
        ber_total = 0;
        return;
    end

    M_act = M_alloc(active_idx);
    Bits_act = Bits_alloc(active_idx);
    SNR_act = SNR_linear(active_idx);

    if strcmpi(ber_mode, 'exact')
        ber_array = qam_ber_exact(M_act, SNR_act);
    elseif strcmpi(ber_mode, 'lut')
        ber_array = qam_ber_lut(M_act, SNR_act, K_map, C_map, lut_hw);
    else
        error('Unknown BER mode: %s', ber_mode);
    end

    err_active = ber_array .* Bits_act;
    err_full(active_idx) = err_active;
    ber_total = sum(err_active) / sum(Bits_act);
end


function ber = qam_ber_exact(M, SNR_linear)
    arg = sqrt(3 .* SNR_linear ./ (2 .* (M - 1)));
    ber = (4 ./ log2(M)) .* (1 - 1 ./ sqrt(M)) .* 0.5 .* erfc(arg);
end


function ber = qam_ber_lut(M, SNR_linear, K_map, C_map, lut_hw)
    K = K_map(M);
    C = C_map(M);

    Y = K .* SNR_linear;
    Y_int = floor(Y);
    Y_frac = Y - Y_int;

    lut_address = floor(Y_frac * 32) + 1;
    lut_address = min(max(lut_address, 1), 32);

    hw_lut_val = lut_hw(lut_address);
    ber = C .* (hw_lut_val .* (2.^(-Y_int)));
end


function res = make_result_struct(name, M_alloc, Bits_alloc, net_rate, ...
    predBER, trueBER, margins, thresholds, iter)

    qam_count = [ ...
        sum(M_alloc == 4), ...
        sum(M_alloc == 16), ...
        sum(M_alloc == 64), ...
        sum(M_alloc == 256) ...
    ];

    res.name = name;
    res.M_alloc = M_alloc;
    res.Bits_alloc = Bits_alloc;
    res.net_rate = net_rate;
    res.predBER = predBER;
    res.trueBER = trueBER;
    res.margins = margins;
    res.thresholds = thresholds;
    res.iter = iter;
    res.qam_count = qam_count;
    res.valid = true;

    % Optional debug/history fields. Empty for models that do not use them.
    res.margin_history = [];
    res.predBER_history = [];
    res.rate_history = [];
    res.update_qam_history = [];
    res.err_sums_history = [];

end


function plot_allocation(f_axis_GHz, df, H_mag_dB_plot, M_alloc, y_min, y_max, ttl)
    hold on;

    % Allocation colors used in the background.
    color_256 = [0.9 0.9 1.0];   % light blue
    color_64  = [0.9 1.0 0.9];   % light green
    color_16  = [1.0 1.0 0.9];   % light yellow
    color_4   = [1.0 0.9 0.9];   % light red

    for k = 1:length(M_alloc)
        M = M_alloc(k);

        if M == 256
            c = color_256;
        elseif M == 64
            c = color_64;
        elseif M == 16
            c = color_16;
        elseif M == 4
            c = color_4;
        else
            continue;
        end

        f_c = f_axis_GHz(k);
        patch([f_c-df/2e9, f_c+df/2e9, f_c+df/2e9, f_c-df/2e9], ...
              [y_min, y_min, y_max, y_max], ...
              c, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    end

    % Channel response.
    plot(f_axis_GHz, H_mag_dB_plot, 'k', 'LineWidth', 2, ...
         'HandleVisibility', 'off');

    % Dummy patch handles only for a compact QAM-allocation legend.
    h256 = patch(nan, nan, color_256, 'EdgeColor', [0.55 0.55 0.55]);
    h64  = patch(nan, nan, color_64,  'EdgeColor', [0.55 0.55 0.55]);
    h16  = patch(nan, nan, color_16,  'EdgeColor', [0.55 0.55 0.55]);
    h4   = patch(nan, nan, color_4,   'EdgeColor', [0.55 0.55 0.55]);

    xlim([0 10]);
    ylim([y_min y_max]);
    xlabel('Frequency (GHz)');
    ylabel('Channel (dB)');
    title(ttl);
    grid on;

    legend([h256 h64 h16 h4], ...
        {'256-QAM', '64-QAM', '16-QAM', '4-QAM'}, ...
        'Location', 'northeast', ...
        'NumColumns', 2, ...
        'FontSize', 9);

    hold off;
end


function e2e = run_e2e_ofdm_case(res_case, N_OFDM_SYM, SNR_linear, ...
    H_full, H_pos, N_FFT, N_CP)

    M_alloc = res_case.M_alloc;
    active_bins = find(M_alloc > 0);

    X_freq = zeros(N_FFT, N_OFDM_SYM);
    tx_bits_cell = cell(1, length(active_bins));
    totalBits = 0;

    for ii = 1:length(active_bins)
        k = active_bins(ii);
        M = M_alloc(k);
        b = log2(M);

        tx_bits = randi([0 1], N_OFDM_SYM * b, 1);
        tx_sym = qam_mod_bits_custom(tx_bits, M);

        pos_idx = k + 1;
        neg_idx = N_FFT - k + 1;

        X_freq(pos_idx, :) = tx_sym.';
        X_freq(neg_idx, :) = conj(tx_sym.');

        tx_bits_cell{ii} = tx_bits;
        totalBits = totalBits + length(tx_bits);
    end

    tx_time = ifft(X_freq, N_FFT, 1);
    tx_cp = [tx_time(end-N_CP+1:end, :); tx_time]; %#ok<NASGU>

    Y_freq = bsxfun(@times, H_full(:), X_freq);
    N_freq = zeros(N_FFT, N_OFDM_SYM);

    for ii = 1:length(active_bins)
        k = active_bins(ii);
        pos_idx = k + 1;
        neg_idx = N_FFT - k + 1;

        snr_k = SNR_linear(k);
        noise_var_eq = 1 / snr_k;

        n_eq = sqrt(noise_var_eq/2) * ...
            (randn(1, N_OFDM_SYM) + 1j * randn(1, N_OFDM_SYM));

        n_ch = H_pos(k) * n_eq;
        N_freq(pos_idx, :) = n_ch;
        N_freq(neg_idx, :) = conj(n_ch);
    end

    Y_freq_noisy = Y_freq + N_freq;

    rx_time_no_cp = ifft(Y_freq_noisy, N_FFT, 1);
    rx_cp = [rx_time_no_cp(end-N_CP+1:end, :); rx_time_no_cp];
    rx_payload = rx_cp(N_CP+1:end, :);
    Y_fft = fft(rx_payload, N_FFT, 1);

    errorBits = 0;

    for ii = 1:length(active_bins)
        k = active_bins(ii);
        M = M_alloc(k);
        pos_idx = k + 1;

        rx_eq = Y_fft(pos_idx, :) ./ H_pos(k);
        rx_bits = qam_demod_symbols_custom(rx_eq.', M);
        tx_bits = tx_bits_cell{ii};
        errorBits = errorBits + sum(rx_bits ~= tx_bits);
    end

    measuredBER = errorBits / totalBits;

    e2e.name = res_case.name;
    e2e.net_rate = res_case.net_rate;
    e2e.analytical_predBER = res_case.predBER;
    e2e.analytical_trueBER = res_case.trueBER;
    e2e.measuredBER = measuredBER;
    e2e.totalBits = totalBits;
    e2e.errorBits = errorBits;
    e2e.N_OFDM_SYM = N_OFDM_SYM;
end


function symbols = qam_mod_bits_custom(bits, M)
    bits = bits(:);
    b = log2(M);
    m_side = sqrt(M);
    b_axis = b / 2;

    if mod(length(bits), b) ~= 0
        error('Bit length must be multiple of log2(M).');
    end

    bit_mat = reshape(bits, b, []).';
    bits_I_gray = bit_mat(:, 1:b_axis);
    bits_Q_gray = bit_mat(:, b_axis+1:end);

    gray_I = bits_to_int_msb(bits_I_gray);
    gray_Q = bits_to_int_msb(bits_Q_gray);

    idx_I = gray_to_binary_int(gray_I);
    idx_Q = gray_to_binary_int(gray_Q);

    levels = (-(m_side-1):2:(m_side-1)).';
    I = levels(double(idx_I) + 1);
    Q = levels(double(idx_Q) + 1);

    norm_factor = sqrt((2/3) * (M - 1));
    symbols = (I + 1j * Q) / norm_factor;
end


function bits = qam_demod_symbols_custom(symbols, M)
    symbols = symbols(:);
    b = log2(M);
    m_side = sqrt(M);
    b_axis = b / 2;

    norm_factor = sqrt((2/3) * (M - 1));
    sym_scaled = symbols * norm_factor;

    levels = (-(m_side-1):2:(m_side-1)).';
    I_val = real(sym_scaled);
    Q_val = imag(sym_scaled);

    distI = abs(bsxfun(@minus, I_val.', levels));
    distQ = abs(bsxfun(@minus, Q_val.', levels));

    [~, idx_I] = min(distI, [], 1);
    [~, idx_Q] = min(distQ, [], 1);

    idx_I = idx_I(:) - 1;
    idx_Q = idx_Q(:) - 1;

    gray_I = binary_to_gray_int(idx_I);
    gray_Q = binary_to_gray_int(idx_Q);

    bits_I = int_to_bits_msb(gray_I, b_axis);
    bits_Q = int_to_bits_msb(gray_Q, b_axis);

    bit_mat = [bits_I bits_Q];
    bits = reshape(bit_mat.', [], 1);
end


function vals = bits_to_int_msb(bit_mat)
    [~, nbits] = size(bit_mat);
    weights = 2.^(nbits-1:-1:0);
    vals = bit_mat * weights.';
    vals = uint32(vals);
end


function bit_mat = int_to_bits_msb(vals, nbits)
    vals = uint32(vals(:));
    bit_mat = zeros(length(vals), nbits);

    for bi = 1:nbits
        bit_pos = nbits - bi + 1;
        bit_mat(:, bi) = bitget(vals, bit_pos);
    end
end


function bin_val = gray_to_binary_int(gray_val)
    gray_val = uint32(gray_val(:));
    bin_val = gray_val;
    shift_val = bitshift(gray_val, -1);

    while any(shift_val ~= 0)
        bin_val = bitxor(bin_val, shift_val);
        shift_val = bitshift(shift_val, -1);
    end

    bin_val = double(bin_val);
end


function gray_val = binary_to_gray_int(bin_val)
    bin_val = uint32(bin_val(:));
    gray_val = bitxor(bin_val, bitshift(bin_val, -1));
    gray_val = double(gray_val);
end


function res = run_exact_erfc_dp_oracle( ...
    snr_db_q16, snr_linear_q16, Fs, N_FFT, N_CP, ...
    base_th_q16, target_ber)

    % Offline global reference.  For each tone, choose one option from
    % {unused, 4, 16, 64, 256-QAM}.  For every attainable total bit count,
    % dynamic programming retains the allocation with the minimum exact
    % bit-error sum, sum_k(bits_k*BER_k).  The largest state satisfying
    %
    %   sum_k(bits_k*BER_k) <= target_ber * sum_k(bits_k)
    %
    % is therefore the global maximum-rate allocation over this candidate
    % set.  QAM candidates use the same Q16 base-threshold restrictions as
    % the proposed engine; there is no fixed-total-bit constraint.

    qam_options = [0 4 16 64 256];
    bit_options = [0 2 4 6 8];
    bit_units = bit_options / 2;

    n_tones = length(snr_db_q16);
    if length(snr_linear_q16) ~= n_tones
        error('DP oracle SNR_dB and SNR_linear vector lengths differ.');
    end
    if numel(base_th_q16) ~= 4
        error('DP oracle requires four base thresholds [4 16 64 256].');
    end
    if target_ber <= 0
        error('DP oracle target_ber must be positive.');
    end

    max_bit_units = 4 * n_tones;  % 8 bits/tone divided by the 2-bit unit
    dp_cost = inf(1, max_bit_units + 1);
    dp_cost(1) = 0.0;

    % choice(tone,state) stores 0...4 for the option selected at that tone.
    % Value 255 marks an unreachable state.  The predecessor state is the
    % current state minus bit_units(option), so a separate predecessor table
    % is unnecessary.
    choice = repmat(uint8(255), n_tones, max_bit_units + 1);
    active_max_units = 0;

    for tone = 1:n_tones
        old_cost = dp_cost;
        new_cost = inf(1, max_bit_units + 1);
        new_choice = repmat(uint8(255), 1, max_bit_units + 1);
        source_indices = 1:(active_max_units + 1);

        for option_code = 0:4
            M = qam_options(option_code + 1);
            bits = bit_options(option_code + 1);
            units = bit_units(option_code + 1);

            if option_code == 0
                weighted_error = 0.0;
            else
                % option_code 1...4 maps to [4 16 64 256].
                if snr_db_q16(tone) < base_th_q16(option_code)
                    continue;
                end
                snr_linear = double(snr_linear_q16(tone)) / 65536;
                weighted_error = bits * qam_ber_exact(M, snr_linear);
            end

            destination_indices = source_indices + units;
            candidate_cost = old_cost(source_indices) + weighted_error;
            better = candidate_cost < new_cost(destination_indices);

            destination_better = destination_indices(better);
            new_cost(destination_better) = candidate_cost(better);
            new_choice(destination_better) = uint8(option_code);
        end

        dp_cost = new_cost;
        choice(tone, :) = new_choice;
        active_max_units = active_max_units + 4;
    end

    total_bits_grid = 2 * (0:max_bit_units);
    % The tolerance only protects a boundary comparison from floating-point
    % roundoff; it is many orders below one Q24 BER LSB at this bit count.
    feasible = dp_cost <= target_ber * total_bits_grid + 1e-15;
    best_state = find(feasible, 1, 'last');
    if isempty(best_state)
        error('DP oracle found no feasible state, including the unused state.');
    end
    best_units = best_state - 1;

    M_alloc_final = zeros(1, n_tones);
    Bits_alloc_final = zeros(1, n_tones);
    remaining_units = best_units;

    for tone = n_tones:-1:1
        option_code = double(choice(tone, remaining_units + 1));
        if option_code == 255
            error('DP oracle backtracking reached an unreachable state.');
        end

        M_alloc_final(tone) = qam_options(option_code + 1);
        Bits_alloc_final(tone) = bit_options(option_code + 1);
        remaining_units = remaining_units - bit_units(option_code + 1);
    end

    if remaining_units ~= 0
        error('DP oracle backtracking did not terminate at the zero-bit state.');
    end

    % Recompute independently from the recovered allocation.
    [overall_ber, ~, ~] = exact_bitweighted_metrics( ...
        M_alloc_final, Bits_alloc_final, snr_linear_q16);
    total_bits = sum(Bits_alloc_final);
    recovered_cost = overall_ber * total_bits;
    if total_bits == 0
        recovered_cost = 0.0;
    end
    if abs(recovered_cost - dp_cost(best_state)) > ...
       1e-12 * max(1.0, abs(dp_cost(best_state)))
        error('DP oracle recovered allocation does not match its terminal cost.');
    end
    if overall_ber > target_ber * (1 + 1e-10)
        error('DP oracle recovered allocation violates the exact BER target.');
    end

    % Certify that every assigned option was present in the declared Q16
    % candidate set.  This is what makes the proposed allocation a feasible
    % DP candidate whenever its offline exact BER meets the target.
    for qidx = 1:4
        assigned = (M_alloc_final == qam_options(qidx + 1));
        if any(snr_db_q16(assigned) < base_th_q16(qidx))
            error('DP oracle assigned a QAM option below its base threshold.');
        end
    end

    res.M_alloc_final = M_alloc_final;
    res.Bits_alloc_final = Bits_alloc_final;
    res.total_bits = total_bits;
    res.overall_ber = overall_ber;
    res.minimum_weighted_error = dp_cost(best_state);
    res.terminal_state_count = sum(isfinite(dp_cost));
    res.net_rate_final = compute_net_rate( ...
        Bits_alloc_final, Fs, N_FFT, N_CP);
end


function res = run_global_model_exact_rtl_control(snr_db_q16, snr_linear_q16, Fs, N_FFT, N_CP, ...
    base_th_q16, target_ber, margin_step_q16, max_iter)

    % Q16 allocation/margin update, but full-precision exact erfc BER target.
    margins_q16 = zeros(1, 4);
    iter = 0;
    margin_history_q16 = margins_q16;

    while true
        [M_alloc, Bits_alloc] = allocate_qam_rtl_q16( ...
            snr_db_q16, base_th_q16, margins_q16);
        [overall_ber, ~, ~] = exact_bitweighted_metrics( ...
            M_alloc, Bits_alloc, snr_linear_q16);

        if overall_ber <= target_ber
            break;
        end

        margins_q16 = margins_q16 + margin_step_q16;
        iter = iter + 1;
        margin_history_q16 = [margin_history_q16; margins_q16]; %#ok<AGROW>

        if iter >= max_iter
            warning('Exact bit-weighted global model reached max_iter.');
            break;
        end
    end

    [M_alloc_final, Bits_alloc_final] = allocate_qam_rtl_q16( ...
        snr_db_q16, base_th_q16, margins_q16);

    res.iter = iter;
    res.margins_q16 = margins_q16;
    res.margins_db = margins_q16 / 65536;
    res.margin_history_q16 = margin_history_q16;
    res.margin_history_db = margin_history_q16 / 65536;
    res.thresholds_q16 = base_th_q16 + margins_q16;
    res.thresholds_db = res.thresholds_q16 / 65536;
    res.M_alloc_final = M_alloc_final;
    res.Bits_alloc_final = Bits_alloc_final;
    res.net_rate_final = compute_net_rate(Bits_alloc_final, Fs, N_FFT, N_CP);
end

function res = run_indep_model_exact_rtl_control(snr_db_q16, snr_linear_q16, Fs, N_FFT, N_CP, ...
    base_th_q16, target_ber, margin_step_q16, max_iter)

    % Overall stop condition is transmitted-bit-weighted exact BER.
    % Tier selection remains average per-tone BER via cross multiplication.
    margins_q16 = zeros(1, 4);
    iter = 0;
    margin_history_q16 = margins_q16;

    while true
        [M_alloc, Bits_alloc] = allocate_qam_rtl_q16( ...
            snr_db_q16, base_th_q16, margins_q16);
        [overall_ber, err_sum, cnt] = exact_bitweighted_metrics( ...
            M_alloc, Bits_alloc, snr_linear_q16);

        if overall_ber <= target_ber
            break;
        end

        worst_idx = rtl_select_worst_qam_avg(err_sum, cnt);
        margins_q16(worst_idx) = margins_q16(worst_idx) + margin_step_q16;
        iter = iter + 1;
        margin_history_q16 = [margin_history_q16; margins_q16]; %#ok<AGROW>

        if iter >= max_iter
            warning('Exact bit-weighted independent model reached max_iter.');
            break;
        end
    end

    if iter < max_iter
        [margins_q16, margin_history_q16, refinement_accepts, refinement_scans] = ...
            refine_margins_exact_rtl_control( ...
            snr_db_q16, snr_linear_q16, base_th_q16, target_ber, ...
            margin_step_q16, max_iter, margins_q16, margin_history_q16);
    else
        refinement_accepts = 0;
        refinement_scans = 0;
    end

    [M_alloc_final, Bits_alloc_final] = allocate_qam_rtl_q16( ...
        snr_db_q16, base_th_q16, margins_q16);

    res.iter = iter;
    res.refinement_accepts = refinement_accepts;
    res.refinement_scans = refinement_scans;
    res.margins_q16 = margins_q16;
    res.margins_db = margins_q16 / 65536;
    res.margin_history_q16 = margin_history_q16;
    res.margin_history_db = margin_history_q16 / 65536;
    res.thresholds_q16 = base_th_q16 + margins_q16;
    res.thresholds_db = res.thresholds_q16 / 65536;
    res.M_alloc_final = M_alloc_final;
    res.Bits_alloc_final = Bits_alloc_final;
    res.net_rate_final = compute_net_rate(Bits_alloc_final, Fs, N_FFT, N_CP);
end

function [overall_ber, err_sum, cnt] = exact_bitweighted_metrics( ...
    M_alloc, Bits_alloc, snr_linear_q16)

    % Overall BER = sum(bits_k * BER_k) / sum(bits_k).
    % err_sum/cnt are per-tone quantities used only for QAM-tier selection.
    err_sum = zeros(1, 4);
    cnt = zeros(1, 4);
    weighted_error = 0.0;
    total_bits = sum(Bits_alloc);

    if total_bits == 0
        overall_ber = 0.0;
        return;
    end

    for k = 1:length(M_alloc)
        M = M_alloc(k);
        bits = Bits_alloc(k);
        if M == 0 || bits == 0
            continue;
        end

        snr_lin = double(snr_linear_q16(k)) / 65536;
        ber_exact = qam_ber_exact(M, snr_lin);
        weighted_error = weighted_error + bits * ber_exact;

        idx = qam_to_index(M);
        err_sum(idx) = err_sum(idx) + ber_exact;
        cnt(idx) = cnt(idx) + 1;
    end

    overall_ber = weighted_error / total_bits;
end

function res = run_global_model_rtl_matched(snr_db_q16, snr_linear_q16, Fs, N_FFT, N_CP, ...
    base_th_q16, K_q16_map, C_q16_map, ...
    target_num, target_den, margin_step_q16, max_iter)

    % Single conservative-Q24 LUT with guarded bit-weighted comparison.
    margins_q16 = zeros(1, 4);
    iter = 0;
    margin_history_q16 = margins_q16;

    while true
        [M_alloc, Bits_alloc] = allocate_qam_rtl_q16( ...
            snr_db_q16, base_th_q16, margins_q16);
        [weighted_err_q24, total_bits, ~, ~] = rtl_bitweighted_error_sums_q24( ...
            M_alloc, Bits_alloc, snr_linear_q16, K_q16_map, C_q16_map);

        if bitweighted_target_met(weighted_err_q24, total_bits, target_num, target_den)
            break;
        end

        margins_q16 = margins_q16 + margin_step_q16;
        iter = iter + 1;
        margin_history_q16 = [margin_history_q16; margins_q16]; %#ok<AGROW>

        if iter >= max_iter
            warning('Bit-weighted Q24 LUT global model reached max_iter.');
            break;
        end
    end

    [M_alloc_final, Bits_alloc_final] = allocate_qam_rtl_q16( ...
        snr_db_q16, base_th_q16, margins_q16);

    qam_count_final = [sum(M_alloc_final == 4), sum(M_alloc_final == 16), ...
        sum(M_alloc_final == 64), sum(M_alloc_final == 256), sum(M_alloc_final == 0)];

    res.iter = iter;
    res.margins_q16 = margins_q16;
    res.margins_db = margins_q16 / 65536;
    res.margin_history_q16 = margin_history_q16;
    res.margin_history_db = margin_history_q16 / 65536;
    res.thresholds_q16 = base_th_q16 + margins_q16;
    res.thresholds_db = res.thresholds_q16 / 65536;
    res.M_alloc_final = M_alloc_final;
    res.Bits_alloc_final = Bits_alloc_final;
    res.qam_count_final = qam_count_final;
    res.net_rate_final = compute_net_rate(Bits_alloc_final, Fs, N_FFT, N_CP);
end

function res = run_indep_model_rtl_matched(snr_db_q16, snr_linear_q16, Fs, N_FFT, N_CP, ...
    base_th_q16, K_q16_map, C_q16_map, ...
    target_num, target_den, margin_step_q16, max_iter)

    % Overall stop condition uses transmitted-bit-weighted LUT BER.
    % Tier selection remains average per-tone LUT BER via cross multiplication.
    margins_q16 = zeros(1, 4);
    iter = 0;
    margin_history_q16 = margins_q16;

    while true
        [M_alloc, Bits_alloc] = allocate_qam_rtl_q16( ...
            snr_db_q16, base_th_q16, margins_q16);
        [weighted_err_q24, total_bits, err_sum, cnt] = rtl_bitweighted_error_sums_q24( ...
            M_alloc, Bits_alloc, snr_linear_q16, K_q16_map, C_q16_map);

        if bitweighted_target_met(weighted_err_q24, total_bits, target_num, target_den)
            break;
        end

        worst_idx = rtl_select_worst_qam_avg(err_sum, cnt);
        margins_q16(worst_idx) = margins_q16(worst_idx) + margin_step_q16;

        iter = iter + 1;
        margin_history_q16 = [margin_history_q16; margins_q16]; %#ok<AGROW>

        if iter >= max_iter
            warning('Bit-weighted Q24 LUT independent model reached max_iter.');
            break;
        end
    end

    if iter < max_iter
        [margins_q16, margin_history_q16, refinement_accepts, refinement_scans] = ...
            refine_margins_rtl_matched( ...
            snr_db_q16, snr_linear_q16, base_th_q16, ...
            K_q16_map, C_q16_map, target_num, target_den, ...
            margin_step_q16, max_iter, margins_q16, margin_history_q16);
    else
        refinement_accepts = 0;
        refinement_scans = 0;
    end

    [M_alloc_final, Bits_alloc_final] = allocate_qam_rtl_q16( ...
        snr_db_q16, base_th_q16, margins_q16);

    qam_count_final = [sum(M_alloc_final == 4), sum(M_alloc_final == 16), ...
        sum(M_alloc_final == 64), sum(M_alloc_final == 256), sum(M_alloc_final == 0)];

    res.iter = iter;
    res.refinement_accepts = refinement_accepts;
    res.refinement_scans = refinement_scans;
    res.margins_q16 = margins_q16;
    res.margins_db = margins_q16 / 65536;
    res.margin_history_q16 = margin_history_q16;
    res.margin_history_db = margin_history_q16 / 65536;
    res.thresholds_q16 = base_th_q16 + margins_q16;
    res.thresholds_db = res.thresholds_q16 / 65536;
    res.M_alloc_final = M_alloc_final;
    res.Bits_alloc_final = Bits_alloc_final;
    res.qam_count_final = qam_count_final;
    res.net_rate_final = compute_net_rate(Bits_alloc_final, Fs, N_FFT, N_CP);
end


function [margins_q16, margin_history_q16, accepts, scans] = ...
    refine_margins_exact_rtl_control( ...
    snr_db_q16, snr_linear_q16, base_th_q16, target_ber, ...
    margin_step_q16, max_accepts, margins_q16, margin_history_q16)

    accepts = 0;
    scans = 0;

    while accepts < max_accepts
        best_found = false;
        best_bits = -1;
        best_margins = margins_q16;

        % Fixed tie order: [4 16 64 256].
        for qidx = 1:4
            if margins_q16(qidx) < margin_step_q16
                continue;
            end

            candidate = margins_q16;
            candidate(qidx) = candidate(qidx) - margin_step_q16;
            [M_candidate, Bits_candidate] = allocate_qam_rtl_q16( ...
                snr_db_q16, base_th_q16, candidate);
            candidate_ber = exact_bitweighted_metrics( ...
                M_candidate, Bits_candidate, snr_linear_q16);
            scans = scans + 1;

            candidate_bits = sum(Bits_candidate);
            if candidate_ber <= target_ber && ...
               (~best_found || candidate_bits > best_bits)
                best_found = true;
                best_bits = candidate_bits;
                best_margins = candidate;
            end
        end

        if ~best_found
            break;
        end

        margins_q16 = best_margins;
        accepts = accepts + 1;
        margin_history_q16 = [margin_history_q16; margins_q16]; %#ok<AGROW>
    end

    if accepts >= max_accepts
        warning('Exact downward refinement reached max_accepts.');
    end
end


function [margins_q16, margin_history_q16, accepts, scans] = ...
    refine_margins_rtl_matched( ...
    snr_db_q16, snr_linear_q16, base_th_q16, ...
    K_q16_map, C_q16_map, target_num, target_den, ...
    margin_step_q16, max_accepts, margins_q16, margin_history_q16)

    accepts = 0;
    scans = 0;

    while accepts < max_accepts
        best_found = false;
        best_bits = -1;
        best_margins = margins_q16;

        % Fixed tie order: [4 16 64 256], identical to the RTL candidate FSM.
        for qidx = 1:4
            if margins_q16(qidx) < margin_step_q16
                continue;
            end

            candidate = margins_q16;
            candidate(qidx) = candidate(qidx) - margin_step_q16;
            [M_candidate, Bits_candidate] = allocate_qam_rtl_q16( ...
                snr_db_q16, base_th_q16, candidate);
            [weighted_err_q24, total_bits] = ...
                rtl_bitweighted_error_sums_q24( ...
                M_candidate, Bits_candidate, snr_linear_q16, ...
                K_q16_map, C_q16_map);
            scans = scans + 1;

            candidate_bits = sum(Bits_candidate);
            candidate_pass = bitweighted_target_met( ...
                weighted_err_q24, total_bits, target_num, target_den);
            if candidate_pass && (~best_found || candidate_bits > best_bits)
                best_found = true;
                best_bits = candidate_bits;
                best_margins = candidate;
            end
        end

        if ~best_found
            break;
        end

        margins_q16 = best_margins;
        accepts = accepts + 1;
        margin_history_q16 = [margin_history_q16; margins_q16]; %#ok<AGROW>
    end

    if accepts >= max_accepts
        warning('Q24 downward refinement reached max_accepts.');
    end
end


function [M_alloc, Bits_alloc] = allocate_qam_rtl_q16(snr_db_q16, base_th_q16, margins_q16)

    N = length(snr_db_q16);
    M_alloc = zeros(1, N);
    Bits_alloc = zeros(1, N);

    % Order: [4 16 64 256]
    th4   = base_th_q16(1);
    th16  = base_th_q16(2);
    th64  = base_th_q16(3);
    th256 = base_th_q16(4);

    for k = 1:N
        snr = snr_db_q16(k);

        eff256 = max(snr - margins_q16(4), 0);
        eff64  = max(snr - margins_q16(3), 0);
        eff16  = max(snr - margins_q16(2), 0);
        eff4   = max(snr - margins_q16(1), 0);

        if eff256 >= th256
            M_alloc(k) = 256;
            Bits_alloc(k) = 8;
        elseif eff64 >= th64
            M_alloc(k) = 64;
            Bits_alloc(k) = 6;
        elseif eff16 >= th16
            M_alloc(k) = 16;
            Bits_alloc(k) = 4;
        elseif eff4 >= th4
            M_alloc(k) = 4;
            Bits_alloc(k) = 2;
        else
            M_alloc(k) = 0;
            Bits_alloc(k) = 0;
        end
    end
end

function [weighted_err_q24, total_bits, err_sum, cnt] = rtl_bitweighted_error_sums_q24( ...
    M_alloc, Bits_alloc, snr_linear_q16, K_q16_map, C_q16_map)

    % BER values are Q24. Overall numerator is sum(bits_k * BER_q24,k).
    % Order of err_sum/cnt: [4 16 64 256].
    weighted_err_q24 = 0;
    total_bits = 0;
    err_sum = zeros(1, 4);
    cnt = zeros(1, 4);

    for k = 1:length(M_alloc)
        M = M_alloc(k);
        bits = Bits_alloc(k);
        if M == 0 || bits == 0
            continue;
        end

        err_q24 = rtl_qam_ber_lut_err_q24_custom( ...
            M, snr_linear_q16(k), K_q16_map(M), C_q16_map(M));
        weighted_err_q24 = weighted_err_q24 + bits * err_q24;
        total_bits = total_bits + bits;

        idx = qam_to_index(M);
        err_sum(idx) = err_sum(idx) + err_q24;
        cnt(idx) = cnt(idx) + 1;
    end
end

function met = bitweighted_target_met(weighted_err_q24, total_bits, target_num, target_den)
    if total_bits == 0
        met = true;
        return;
    end

    % Q24 estimate plus a 2^-20 residual allowance must meet the system
    % target.  In Q24 units the residual is 16 counts per transmitted bit.
    ber_scale = 2^24;
    residual_guard_q24 = 2^(24 - 20);
    rhs_per_bit = ber_scale * target_num - residual_guard_q24 * target_den;
    if rhs_per_bit < 0
        error('BER target is smaller than the configured residual guard.');
    end

    met = (weighted_err_q24 * target_den) <= ...
          (total_bits * rhs_per_bit);
end

function idx = qam_to_index(M)
    if M == 4
        idx = 1;
    elseif M == 16
        idx = 2;
    elseif M == 64
        idx = 3;
    elseif M == 256
        idx = 4;
    else
        error('Unsupported QAM order: %g', M);
    end
end

function worst_idx = rtl_select_worst_qam_avg(err_sum, cnt)

    % This mirrors the shared worst-QAM comparison tree in the controller RTL.
    % MATLAB order: 1=4, 2=16, 3=64, 4=256

    err256 = err_sum(4); cnt256 = cnt(4);
    err64  = err_sum(3); cnt64  = cnt(3);
    err16  = err_sum(2); cnt16  = cnt(2);
    err4   = err_sum(1); cnt4   = cnt(1);

    % Pair 256 vs 64
    if ((cnt256 > 0 && cnt64 == 0) || ...
        (cnt256 > 0 && cnt64 > 0 && (err256 * cnt64 >= err64 * cnt256)))
        win12_idx = 4; win12_err = err256; win12_cnt = cnt256;
    else
        win12_idx = 3; win12_err = err64;  win12_cnt = cnt64;
    end

    % Pair 16 vs 4
    if ((cnt16 > 0 && cnt4 == 0) || ...
        (cnt16 > 0 && cnt4 > 0 && (err16 * cnt4 >= err4 * cnt16)))
        win34_idx = 2; win34_err = err16; win34_cnt = cnt16;
    else
        win34_idx = 1; win34_err = err4;  win34_cnt = cnt4;
    end

    % Final pair winner
    if ((win12_cnt > 0 && win34_cnt == 0) || ...
        (win12_cnt > 0 && win34_cnt > 0 && (win12_err * win34_cnt >= win34_err * win12_cnt)))
        worst_idx = win12_idx;
    else
        worst_idx = win34_idx;
    end
end
