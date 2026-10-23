function report = verify_conservative_KC_Q24_exhaustive(K_q16, C_q16, mode)
%VERIFY_CONSERVATIVE_KC_Q24_EXHAUSTIVE Certify the bit-accurate Q24 bank.
%
% report = verify_conservative_KC_Q24_exhaustive
% report = verify_conservative_KC_Q24_exhaustive(K_q16, C_q16, mode)
%
% K_q16 and C_q16 use order [4 16 64 256].  mode is:
%   'interval' : exact compressed exhaustive proof (default)
%   'literal'  : directly enumerate every Q16 input code
%   'both'     : run both and require identical extrema
%
% 'interval' is exhaustive, not sampled.  It partitions every integer input
% code by n=floor(K*SNR/2^27).  The RTL estimate is constant within each
% partition.  The analytical BER is monotone decreasing, so the left endpoint
% proves the one-sided lower bound and the right endpoint gives the largest
% overestimation ratio.  The verifier also proves that the intervals are
% contiguous and cover the full domain without a gap or overlap.

    if nargin < 1 || isempty(K_q16)
        K_q16 = [50734 10213 2436 602];
    end
    if nargin < 2 || isempty(C_q16)
        C_q16 = [12756 10206 8057 6506];
    end
    if nargin < 3 || isempty(mode)
        mode = 'interval';
    end

    if ~isnumeric(K_q16) || ~isnumeric(C_q16) || ...
       numel(K_q16) ~= 4 || numel(C_q16) ~= 4
        error('K_q16 and C_q16 must each contain [4 16 64 256] values.');
    end
    if any(K_q16 < 0 | K_q16 > 65535 | K_q16 ~= floor(K_q16)) || ...
       any(C_q16 < 0 | C_q16 > 65535 | C_q16 ~= floor(C_q16))
        error('K_q16 and C_q16 must be unsigned 16-bit integers.');
    end
    if ~(strcmpi(mode, 'interval') || strcmpi(mode, 'literal') || ...
         strcmpi(mode, 'both'))
        error('mode must be ''interval'', ''literal'', or ''both''.');
    end

    qam = [4 16 64 256];
    base_threshold_db = [6 12 18 24];
    residual_bound = 2^-20;
    ber_frac = 24;
    lut_q16 = uint64(floor(2.^(-(0:31)/32) * 65536));

    n_qam = numel(qam);
    first_code = zeros(n_qam, 1);
    last_code = zeros(n_qam, 1);
    covered_codes = zeros(n_qam, 1);
    n_intervals = zeros(n_qam, 1);
    violating_intervals = zeros(n_qam, 1);
    minimum_c = zeros(n_qam, 1);
    min_ratio = zeros(n_qam, 1);
    max_ratio = zeros(n_qam, 1);
    min_abs_guard = zeros(n_qam, 1);
    literal_violations = nan(n_qam, 1);
    literal_min_ratio = nan(n_qam, 1);
    literal_max_ratio = nan(n_qam, 1);

    fprintf('\n============================================================\n');
    fprintf('Independent Q24 exhaustive verifier (%s mode)\n', lower(mode));
    fprintf('============================================================\n');

    for ii = 1:n_qam
        M = qam(ii);
        lo = uint64(round(10^(base_threshold_db(ii)/10) * 65536));
        hi = find_last_active_snr_code(M, lo, residual_bound);
        [left, right, shift, address] = staircase_partition( ...
            uint64(K_q16(ii)), lo, hi);

        certify_partition(left, right, lo, hi, M);
        if any(shift >= 24)
            error('%d-QAM reaches the RTL zero-output shift in the active domain.', M);
        end

        exact_left = qam_ber_exact(M, double(left) / 65536);
        exact_right = qam_ber_exact(M, double(right) / 65536);
        required_q24 = uint64(ceil(exact_left * 2^ber_frac));
        lut_value = lut_q16(double(address) + 1);
        scale = uint64(2.^(8 + double(shift)));
        estimate_q24 = idivide(uint64(C_q16(ii)) .* lut_value, scale, 'floor');
        required_c_each = ceil_div_u64(required_q24 .* scale, lut_value);

        violations = estimate_q24 < required_q24;
        ratio_at_left = (double(estimate_q24) / 2^ber_frac) ./ exact_left;
        ratio_at_right = (double(estimate_q24) / 2^ber_frac) ./ exact_right;

        first_code(ii) = double(lo);
        last_code(ii) = double(hi);
        covered_codes(ii) = sum(double(right - left + uint64(1)));
        n_intervals(ii) = numel(left);
        violating_intervals(ii) = sum(violations);
        minimum_c(ii) = double(max(required_c_each));
        min_ratio(ii) = min(ratio_at_left);
        max_ratio(ii) = max(ratio_at_right);
        min_abs_guard(ii) = min(double(estimate_q24) / 2^ber_frac - exact_left);

        if covered_codes(ii) ~= double(hi - lo + uint64(1))
            error('%d-QAM covered-code count is inconsistent.', M);
        end
        if violating_intervals(ii) ~= 0
            error('%d-QAM has %d one-sided interval violations.', ...
                M, violating_intervals(ii));
        end

        if strcmpi(mode, 'literal') || strcmpi(mode, 'both')
            literal = literal_code_scan( ...
                M, lo, hi, uint64(K_q16(ii)), uint64(C_q16(ii)), ...
                lut_q16, ber_frac);
            literal_violations(ii) = literal.violations;
            literal_min_ratio(ii) = literal.min_ratio;
            literal_max_ratio(ii) = literal.max_ratio;

            if literal.violations ~= 0
                error('%d-QAM literal scan found %d violating codes.', ...
                    M, literal.violations);
            end
            if strcmpi(mode, 'both') && ...
               (abs(literal.min_ratio - min_ratio(ii)) > 1e-12 || ...
                abs(literal.max_ratio - max_ratio(ii)) > 1e-12)
                error('%d-QAM interval and literal extrema disagree.', M);
            end
        end

        fprintf(['%3d-QAM: codes=%10.0f, intervals=%4d, violations=%d, ', ...
                 'C_min=%d, ratio=[%.12f, %.12f]\n'], ...
            M, covered_codes(ii), n_intervals(ii), ...
            violating_intervals(ii), minimum_c(ii), ...
            min_ratio(ii), max_ratio(ii));
    end

    report = table( ...
        qam(:), K_q16(:), C_q16(:), first_code, last_code, covered_codes, ...
        n_intervals, minimum_c, violating_intervals, min_abs_guard, ...
        min_ratio, max_ratio, literal_violations, literal_min_ratio, ...
        literal_max_ratio, ...
        'VariableNames', { ...
            'QAM', 'K_Q16', 'C_Q16', 'FirstSNRCode_Q16', ...
            'LastSNRCode_Q16', 'CoveredInputCodes', 'StaircaseIntervals', ...
            'MinimumLegalC_Q16', 'ViolatingIntervals', ...
            'MinimumAbsoluteGuard', 'MinimumEstimateToExactRatio', ...
            'WorstEstimateToExactRatio', 'LiteralViolatingCodes', ...
            'LiteralMinimumRatio', 'LiteralMaximumRatio'});

    fprintf('------------------------------------------------------------\n');
    fprintf('PASS: %.0f integer Q16 input codes are covered with no gap.\n', ...
        sum(covered_codes));
    fprintf('PASS: no one-sided BER violation was found.\n');
    fprintf('============================================================\n\n');
end


function stats = literal_code_scan(M, lo, hi, k_q16, c_q16, lut_q16, ber_frac)
    chunk_size = uint64(1000000);
    first = lo;
    violations = 0;
    min_ratio = Inf;
    max_ratio = 0;

    while first <= hi
        last = min(hi, first + chunk_size - uint64(1));
        codes = uint64(double(first):double(last));
        product = k_q16 .* codes;
        staircase_index = bitshift(product, -27);
        shift = bitshift(staircase_index, -5);
        address = bitand(staircase_index, uint64(31));
        lut_value = lut_q16(double(address) + 1);
        base_q24 = idivide(c_q16 .* lut_value, uint64(256), 'floor');

        estimate_q24 = zeros(size(base_q24), 'uint64');
        for ss = 0:23
            select = shift == ss;
            if any(select)
                estimate_q24(select) = idivide( ...
                    base_q24(select), uint64(2^ss), 'floor');
            end
        end

        exact_ber = qam_ber_exact(M, double(codes) / 65536);
        required_q24 = uint64(ceil(exact_ber * 2^ber_frac));
        violations = violations + sum(estimate_q24 < required_q24);
        ratio = (double(estimate_q24) / 2^ber_frac) ./ exact_ber;
        min_ratio = min(min_ratio, min(ratio));
        max_ratio = max(max_ratio, max(ratio));

        if last == hi
            break;
        end
        first = last + uint64(1);
    end

    stats = struct('violations', violations, ...
        'min_ratio', min_ratio, 'max_ratio', max_ratio);
end


function certify_partition(left, right, lo, hi, M)
    if isempty(left) || left(1) ~= lo || right(end) ~= hi
        error('%d-QAM staircase partition does not reach both domain ends.', M);
    end
    if any(left > right)
        error('%d-QAM staircase partition contains an empty interval.', M);
    end
    if numel(left) > 1 && ...
       any(left(2:end) ~= right(1:end-1) + uint64(1))
        error('%d-QAM staircase partition has a gap or overlap.', M);
    end
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
end


function ber = qam_ber_exact(M, snr_linear)
    argument = sqrt(3 .* snr_linear ./ (2 .* (M - 1)));
    ber = (4 / log2(M)) * (1 - 1 / sqrt(M)) * 0.5 .* erfc(argument);
end
