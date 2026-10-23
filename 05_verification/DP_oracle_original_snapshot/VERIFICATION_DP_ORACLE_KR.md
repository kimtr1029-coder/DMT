# 검증 보고서

## 1. 원본 보존 검사

- 세 원본 각각의 local function 34개를 수정본과 byte-level로 대조했다.
- 결과: `34/34 PASS`가 세 파일 모두에서 확인됐다.
- 즉 Proposed Engine의 K/C, Q24 LUT, BER accumulator, worst-QAM 선택,
  margin/refinement, allocation 및 RTL export 함수는 변경하지 않았다.
- 새 `run_exact_erfc_dp_oracle` 함수는 세 수정본에서 동일하며, 줄 끝 공백을
  정규화한 함수 본문의 SHA-256은
  `4a03e07549d9a9c2e26f40848841d10076e8c06cdbff7d14ae4ba69e2ca89c99`를 갖는다.

## 2. 구조 및 연결 검사

- 괄호 `()`, 대괄호 `[]`, 중괄호 `{}` balance: PASS
- `function/if/for/while/switch/try/end` block balance: PASS
- Figure 1, summary table, E2E case와 rate-gap 계산이 모두 `res_exact_oracle`을
  참조하는지 검사: PASS
- 과거 top-level `res_exact_indep` 및 `exact_rtl_indep` 참조 잔존 여부: 없음

## 3. DP 전역 최적성 검사

tone 수 1~6의 작은 문제를 만들고, 각 tone의 가능한 모든
`{unused, 4, 16, 64, 256-QAM}` 조합을 실제로 열거한 exhaustive search와 DP를
비교했다.

- random Q16-domain case: tone 수별 100개
- 전체 case: 600개
- 최대 feasible total bits 일치: `600/600 PASS`
- 같은 total bits에서 minimum exact weighted-error cost 일치: `600/600 PASS`

## 4. 두 deterministic 채널의 독립 수치 계산

MATLAB 파일과 별개의 Python/Numpy/Scipy 계산으로 채널 생성, Q16 quantization,
exact-erfc cost와 DP를 다시 구현했다.

| 환경 | DP oracle bits/OFDM symbol | Net rate | Exact BER |
|---|---:|---:|---:|
| channel25 | 1056 | 38.260870 Gbps | 9.815429e-05 |
| two-null | 1046 | 37.898551 Gbps | 9.856766e-05 |

동일한 독립 계산에서 현재 Proposed Q24/refinement 코드는 두 환경 모두 1034 bit를
선택했다. 따라서 예상 oracle gap은 channel25에서 22 bit, two-null에서 12 bit이다.
MATLAB 실행 결과가 이 값과 다르면 실행한 파일, `channel_25db.txt`, base threshold,
K/C 상수 또는 MATLAB 코드의 추가 수정 여부를 먼저 확인해야 한다.

## 5. 검증 범위의 한계

현재 작업 환경에는 MATLAB/Octave executable이 없어 `.m` 파일 자체를 MATLAB에서
직접 실행하지는 못했다. 대신 위의 정적 구조 검사, 원본 함수 보존 검사,
완전탐색 대조 및 독립 수치 계산을 수행했다. 최종 논문 수치를 확정할 때는 사용자의
MATLAB 버전에서 세 파일을 각각 한 번 실행하고 console assertion이 발생하지 않는지
확인해야 한다.
