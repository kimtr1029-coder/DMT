% One-click entry point for paper requirement item 1.
clear; clc;

% false: rigorous interval-partition proof (fast, already exhaustive)
% true : additionally enumerate all 134,915,306 integer Q16 input codes
RUN_LITERAL_ALL_CODES = false;

results = generate_conservative_KC_Q24; %#ok<NASGU>

if RUN_LITERAL_ALL_CODES
    literal_report = verify_conservative_KC_Q24_exhaustive([], [], 'both'); %#ok<NASGU>
end
