function results = generate_conservative_KC_Q24(output_dir)
%GENERATE_CONSERVATIVE_KC_Q24 Exhaustively synthesize Q16 K/C coefficients.
%
% This function searches every unsigned 16-bit K candidate (0...65535).
% For each K, it derives the minimum unsigned 16-bit C that makes the exact
% RTL Q24 staircase estimator no smaller than the analytical square-QAM BER
% over the complete design domain.  Among the valid one-sided candidates it
% minimizes the worst-case overestimation ratio.
%
% The generated arithmetic exactly matches FINAL_Q24_REFINE_datapath_20260812.v:
%   y       = K_Q16 * SNR_LINEAR_Q16                         (Q32)
%   shift   = y[...:32]
%   address = y[31:27]
%   base    = floor(C_Q16 * LUT_Q16 / 2^8)                  (Q24)
%   BER_Q24 = floor(base / 2^shift), or zero for shift >= 24
%
% Usage:
%   results = generate_conservative_KC_Q24;
%   results = generate_conservative_KC_Q24('my_output_folder');
%
% No channel realization is used.  The only numerical dependency is erfc,
% which is part of base MATLAB.

    if nargin < 1 || isempty(output_dir)
        output_dir = fileparts(mfilename('fullpath'));
    end
    if ~isfolder(output_dir)
        mkdir(output_dir);
    end

    qam = [4 16 64 256];
    base_threshold_db = [6 12 18 24];
    ber_fraction_bits = 24;
    residual_log2 = 20;
    residual_bound = 2^(-residual_log2);
    lut_q16 = uint64(floor(2.^(-(0:31)/32) * 65536));
    expected_k = [50734 10213 2436 602];
    expected_c = [12756 10206 8057 6506];

    n_qam = numel(qam);
    best_k = zeros(1, n_qam);
    best_c = zeros(1, n_qam);
    best_objective = inf(1, n_qam);
    min_ratio = nan(1, n_qam);
    domain_first = zeros(1, n_qam);
    domain_last = zeros(1, n_qam);
    domain_codes = zeros(1, n_qam);
    interval_count = zeros(1, n_qam);
    valid_k_count = zeros(1, n_qam);
    elapsed_s = zeros(1, n_qam);

    fprintf('\n============================================================\n');
    fprintf('Q24 one-sided K/C exhaustive synthesis\n');
    fprintf('K search space : every unsigned Q16 code, 0...65535\n');
    fprintf('C constraint   : unsigned Q16, 0...65535\n');
    fprintf('Residual bound : 2^{-%d} = %.12e\n', ...
        residual_log2, residual_bound);
    fprintf('============================================================\n');

    for ii = 1:n_qam
        M = qam(ii);
        lo = uint64(round(10^(base_threshold_db(ii)/10) * 65536));
        hi = find_last_active_snr_code(M, lo, residual_bound);

        domain_first(ii) = double(lo);
        domain_last(ii) = double(hi);
        domain_codes(ii) = double(hi - lo + uint64(1));

        fprintf('\n%d-QAM: SNR code %u...%u (%.9f...%.9f dB)\n', ...
            M, lo, hi, code_to_db(lo), code_to_db(hi));

        timer_qam = tic;
        current_best_j = Inf;
        current_best_c = Inf;
        current_best_k = Inf;
        current_min_ratio = NaN;
        current_intervals = 0;
        n_valid = 0;

        % Every unsigned 16-bit K is considered.  Candidates for which the
        % RTL shift reaches 24 inside the active domain are rejected before
        % interval construction because their BER output becomes zero.
        for k = 0:65535
            if k ~= 0 && floor(double(k) * double(hi) / 2^32) >= 24
                continue;
            end

            candidate = analyze_candidate( ...
                M, uint64(k), lo, hi, lut_q16, ber_fraction_bits);
            if ~candidate.valid
                continue;
            end
            n_valid = n_valid + 1;

            if lexicographically_better( ...
                    candidate.objective, candidate.c_q16, k, ...
                    current_best_j, current_best_c, current_best_k)
                current_best_j = candidate.objective;
                current_best_c = candidate.c_q16;
                current_best_k = k;
                current_min_ratio = candidate.min_ratio;
                current_intervals = candidate.interval_count;
            end
        end

        if ~isfinite(current_best_j)
            error('No legal unsigned-Q16 K/C pair exists for %d-QAM.', M);
        end

        best_k(ii) = current_best_k;
        best_c(ii) = current_best_c;
        best_objective(ii) = current_best_j;
        min_ratio(ii) = current_min_ratio;
        interval_count(ii) = current_intervals;
        valid_k_count(ii) = n_valid;
        elapsed_s(ii) = toc(timer_qam);

        fprintf(['  best K=%u, C=%u, min ratio=%.12f, ', ...
                 'max ratio=%.12f, intervals=%u, valid K=%u\n'], ...
            current_best_k, current_best_c, current_min_ratio, ...
            current_best_j, current_intervals, n_valid);
    end

    if any(best_k ~= expected_k) || any(best_c ~= expected_c)
        error(['Generated constants differ from the checked RTL bank. ', ...
               'Do not update MATLAB or RTL until the discrepancy is resolved.']);
    end

    results = table( ...
        qam(:), base_threshold_db(:), domain_first(:), domain_last(:), ...
        domain_codes(:), best_k(:), best_c(:), interval_count(:), ...
        valid_k_count(:), min_ratio(:), best_objective(:), elapsed_s(:), ...
        'VariableNames', { ...
            'QAM', 'BaseThreshold_dB', 'FirstSNRCode_Q16', ...
            'LastSNRCode_Q16', 'CoveredInputCodes', 'K_Q16', 'C_Q16', ...
            'StaircaseIntervals', 'ValidKCandidates', ...
            'MinimumEstimateToExactRatio', ...
            'WorstEstimateToExactRatio', 'SynthesisTime_s'});

    % A separately implemented verifier reconstructs the selected RTL
    % staircase and certifies its complete integer-code partition.
    verification = verify_conservative_KC_Q24_exhaustive( ...
        best_k, best_c, 'interval');

    config = struct();
    config.qam = qam;
    config.base_threshold_db = base_threshold_db;
    config.ber_fraction_bits = ber_fraction_bits;
    config.residual_log2 = residual_log2;
    config.residual_bound = residual_bound;
    config.lut_q16 = lut_q16;
    config.tie_break = 'minimum objective, then minimum C, then minimum K';

    save(fullfile(output_dir, 'KC_Q24_generated_results.mat'), ...
        'results', 'verification', 'config');
    write_results_csv(fullfile(output_dir, 'KC_Q24_generated_results.csv'), results);
    write_verilog_header(fullfile(output_dir, 'KC_Q24_generated_constants.vh'), ...
        best_k, best_c);
    write_text_report(fullfile(output_dir, 'KC_Q24_generated_report.txt'), ...
        results, verification, residual_log2);

    fprintf('\nGenerated constants exactly match the checked RTL bank.\n');
    fprintf('Covered Q16 input codes across all QAM domains: %.0f\n', ...
        sum(domain_codes));
    fprintf('Output directory: %s\n\n', output_dir);
    disp(results(:, {'QAM', 'K_Q16', 'C_Q16', ...
        'MinimumEstimateToExactRatio', 'WorstEstimateToExactRatio'}));
end


function candidate = analyze_candidate(M, k_q16, lo, hi, lut_q16, ber_frac)
    candidate = struct('valid', false, 'c_q16', NaN, ...
        'objective', Inf, 'min_ratio', NaN, 'interval_count', 0);

    [left, right, shift, address] = staircase_partition(k_q16, lo, hi);
    if isempty(left) || any(shift >= 24)
        return;
    end

    exact_left = qam_ber_exact(M, double(left) / 65536);
    required_q24 = uint64(ceil(exact_left * 2^ber_frac));
    lut_value = lut_q16(double(address) + 1);
    scale = uint64(2.^(8 + double(shift)));

    % floor(C*LUT/2^(8+shift)) >= required_q24 is equivalent to
    % C*LUT >= required_q24*2^(8+shift).  Therefore this is the exact
    % minimum C for every interval, not a numerical fit or line search.
    numerator = required_q24 .* scale;
    c_each = ceil_div_u64(numerator, lut_value);
    c_q16 = max(c_each);
    if c_q16 > 65535
        return;
    end

    estimate_q24 = idivide(c_q16 .* lut_value, scale, 'floor');
    exact_right = qam_ber_exact(M, double(right) / 65536);
    ratio_left = (double(estimate_q24) / 2^ber_frac) ./ exact_left;
    ratio_right = (double(estimate_q24) / 2^ber_frac) ./ exact_right;

    if any(estimate_q24 < required_q24)
        error('Internal one-sided construction failure for %d-QAM, K=%u.', ...
            M, k_q16);
    end

    candidate.valid = true;
    candidate.c_q16 = double(c_q16);
    candidate.objective = max(ratio_right);
    candidate.min_ratio = min(ratio_left);
    candidate.interval_count = numel(left);
end


function [left, right, shift, address] = staircase_partition(k_q16, lo, hi)
    step = uint64(2^27);
    if k_q16 == 0
        left = lo;
        right = hi;
        shift = uint64(0);
        address = uint64(0);
        return;
    end

    n_first = idivide(k_q16 .* lo, step, 'floor');
    n_last = idivide(k_q16 .* hi, step, 'floor');
    n = uint64(double(n_first):double(n_last));

    left = ceil_div_u64(n .* step, k_q16);
    right = ceil_div_u64((n + uint64(1)) .* step, k_q16) - uint64(1);
    left = max(left, lo);
    right = min(right, hi);

    keep = left <= right;
    n = n(keep);
    left = left(keep);
    right = right(keep);
    shift = idivide(n, uint64(32), 'floor');
    address = mod(n, uint64(32));
end


function q = ceil_div_u64(numerator, denominator)
    q = idivide(numerator + denominator - uint64(1), denominator, 'floor');
end


function hi = find_last_active_snr_code(M, lo, residual_bound)
    if qam_ber_exact(M, double(lo) / 65536) < residual_bound
        error('%d-QAM base threshold is already below the residual bound.', M);
    end

    low = lo;
    high = max(uint64(1), uint64(2) .* lo);
    while qam_ber_exact(M, double(high) / 65536) >= residual_bound
        high = uint64(2) .* high;
    end

    while high - low > uint64(1)
        mid = idivide(low + high, uint64(2), 'floor');
        if qam_ber_exact(M, double(mid) / 65536) >= residual_bound
            low = mid;
        else
            high = mid;
        end
    end
    hi = low;

    if qam_ber_exact(M, double(hi) / 65536) < residual_bound || ...
       qam_ber_exact(M, double(hi + uint64(1)) / 65536) >= residual_bound
        error('Active-domain endpoint search failed for %d-QAM.', M);
    end
end


function tf = lexicographically_better(j, c, k, best_j, best_c, best_k)
    tf = (j < best_j) || ...
         (j == best_j && c < best_c) || ...
         (j == best_j && c == best_c && k < best_k);
end


function ber = qam_ber_exact(M, snr_linear)
    argument = sqrt(3 .* snr_linear ./ (2 .* (M - 1)));
    ber = (4 / log2(M)) * (1 - 1 / sqrt(M)) * 0.5 .* erfc(argument);
end


function value_db = code_to_db(code)
    value_db = 10 * log10(double(code) / 65536);
end


function write_results_csv(filename, results)
    fid = fopen(filename, 'wt');
    if fid < 0
        error('Could not create %s.', filename);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

    fprintf(fid, ['QAM,BaseThreshold_dB,FirstSNRCode_Q16,LastSNRCode_Q16,', ...
        'CoveredInputCodes,K_Q16,C_Q16,StaircaseIntervals,ValidKCandidates,', ...
        'MinimumEstimateToExactRatio,WorstEstimateToExactRatio,SynthesisTime_s\n']);
    for ii = 1:height(results)
        fprintf(fid, '%d,%.9f,%.0f,%.0f,%.0f,%d,%d,%d,%d,%.15f,%.15f,%.6f\n', ...
            results.QAM(ii), results.BaseThreshold_dB(ii), ...
            results.FirstSNRCode_Q16(ii), results.LastSNRCode_Q16(ii), ...
            results.CoveredInputCodes(ii), results.K_Q16(ii), ...
            results.C_Q16(ii), results.StaircaseIntervals(ii), ...
            results.ValidKCandidates(ii), ...
            results.MinimumEstimateToExactRatio(ii), ...
            results.WorstEstimateToExactRatio(ii), results.SynthesisTime_s(ii));
    end
end


function write_verilog_header(filename, k, c)
    fid = fopen(filename, 'wt');
    if fid < 0
        error('Could not create %s.', filename);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

    fprintf(fid, '// Auto-generated by generate_conservative_KC_Q24.m\n');
    fprintf(fid, '// Order checked against FINAL_Q24_REFINE_datapath_20260812.v\n');
    fprintf(fid, 'localparam [15:0] K_256 = 16''d%d;\n', k(4));
    fprintf(fid, 'localparam [15:0] C_256 = 16''d%d;\n', c(4));
    fprintf(fid, 'localparam [15:0] K_64  = 16''d%d;\n', k(3));
    fprintf(fid, 'localparam [15:0] C_64  = 16''d%d;\n', c(3));
    fprintf(fid, 'localparam [15:0] K_16  = 16''d%d;\n', k(2));
    fprintf(fid, 'localparam [15:0] C_16  = 16''d%d;\n', c(2));
    fprintf(fid, 'localparam [15:0] K_4   = 16''d%d;\n', k(1));
    fprintf(fid, 'localparam [15:0] C_4   = 16''d%d;\n', c(1));
end


function write_text_report(filename, results, verification, residual_log2)
    fid = fopen(filename, 'wt');
    if fid < 0
        error('Could not create %s.', filename);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

    fprintf(fid, 'Q24 ONE-SIDED K/C EXHAUSTIVE SYNTHESIS REPORT\n');
    fprintf(fid, '============================================================\n');
    fprintf(fid, 'K candidates: all unsigned 16-bit values, 0...65535\n');
    fprintf(fid, 'C constraint: unsigned 16-bit values, 0...65535\n');
    fprintf(fid, 'Residual bound: 2^{-%d}\n', residual_log2);
    fprintf(fid, 'Total covered Q16 SNR codes: %.0f\n\n', ...
        sum(results.CoveredInputCodes));
    fprintf(fid, ['QAM  K_Q16  C_Q16  Intervals  InputCodes  ', ...
        'MinRatio  MaxRatio  Violations\n']);
    for ii = 1:height(results)
        fprintf(fid, '%3d  %5d  %5d  %9d  %10.0f  %.12f  %.12f  %d\n', ...
            results.QAM(ii), results.K_Q16(ii), results.C_Q16(ii), ...
            results.StaircaseIntervals(ii), results.CoveredInputCodes(ii), ...
            verification.MinimumEstimateToExactRatio(ii), ...
            verification.WorstEstimateToExactRatio(ii), ...
            verification.ViolatingIntervals(ii));
    end
    fprintf(fid, '\nPASS: all domains form contiguous integer-code partitions.\n');
    fprintf(fid, 'PASS: zero one-sided violations.\n');
    fprintf(fid, 'PASS: generated constants match the checked RTL parameters.\n');
end
