# Unbiased Chebyshev Baseline 검증 보고서

## 1. 수정 범위 확인

최종 coefficient 생성 경로는 다음 하나뿐이다.

```text
4001 samples/segment
 -> numpy.polynomial.chebyshev.chebfit(degree=4)
 -> chebyshev.cheb2poly
 -> Q30 round-to-nearest
 -> RTL coefficient ROM
```

`solve_conservative_biases`, `c0 += bias`, minimax LP 및 fixed-point coefficient
search는 사용하지 않는다. 원본 conservative ROM을 역검사하여 새 ROM과의 차이가
44개 `c0`의 기존 bias뿐임을 확인했다.

```text
PASS: original chebfit coefficient reproduction
removed c0 bias range = 137 ... 2320 Q30 codes
c1 ... c4 differences = 0
```

## 2. 수치 audit 범위

- `1.25 <= z < 12.25`
- Q16 z-code 720,896개
- 4/16/64/256-QAM
- 각 z bucket에 들어오는 최소/최대 Q16 SNR code 검사
- bucket-endpoint BER case 5,767,168개
- exact reference: software `erfc`
- RTL rounding: 각 Horner multiply의 sign-symmetric rounding 및 최종 Q24 rounding 포함

### h(z) 결과

```text
minimum signed error = -3.998919607950402e-8
maximum signed error = +3.7507303943251635e-8
maximum absolute error = 3.998919607950402e-8
RMSE = 2.0655523389862867e-9
negative Q16-z codes = 363,139
positive Q16-z codes = 357,757
```

### Target-band BER 결과

| QAM | Underestimate | Overestimate | False-safe | False-reject |
|---:|---:|---:|---:|---:|
| 4 | 0.05945299% | 0.05983565% | 0 | 9 |
| 16 | 0.06046051% | 0.05975006% | 0 | 9 |
| 64 | 0.06108939% | 0.05892318% | 0 | 8 |
| 256 | 0.06343633% | 0.05679715% | 0 | 6 |

## 3. RTL bit-exact 결과

```text
PASS: 4,116 directed/random continuous vectors
PASS: 2,883,584 exhaustive Q16-z/QAM vectors
datapath latency = 7 clocks
initiation interval = 1 clock
Python fixed-point model vs RTL mismatch = 0
```

Full hierarchy structural check:

```text
Yosys hierarchy/proc/opt_clean/check: Found and reported 0 problems
```

## 4. Channel-profile 결과

공통 조건:

- 255 tones
- one-cycle synchronous SNR-table response
- 100-MHz clock
- 기존 공통 controller와 0.1-dB margin step
- 기존 공통 guarded target constant 유지
- latency: start active edge부터 done active edge까지

### channel25

```text
cycles = 51,109 (511.09 us)
updates = 180, refinement accepts = 0, scans = 4
bits = 1,044, rate = 37.8260869565 Gbps
runtime estimated BER = 9.77245555527e-5
offline exact-erfc BER = 9.77361640428e-5
exact target violation = 0
tiers: unused=10, 4-QAM=76, 16-QAM=74, 64-QAM=82, 256-QAM=13
```

### two-null

```text
cycles = 58,103 (581.03 us)
updates = 182, refinement accepts = 6, scans = 28
bits = 1,044, rate = 37.8260869565 Gbps
runtime estimated BER = 9.64612111278e-5
offline exact-erfc BER = 9.64741663988e-5
exact target violation = 0
tiers: unused=34, 4-QAM=67, 16-QAM=40, 64-QAM=81, 256-QAM=33
```

## 5. 검증 결론

이번 RTL은 기존 one-sided Chebyshev에서 bias만 제거한 정상적인 two-sided
Chebyshev baseline이다. 새 coefficient는 원래 `chebfit`과 정확히 일치하며,
minimax 또는 다른 fitting 방식으로 변경되지 않았다. 두 채널에서 최종 allocation과
latency는 이전 결과와 같았지만 runtime BER 값은 unbiased coefficient에 맞게 다시
계산되었다. 논문용 area/power는 동일 합성 환경에서 별도로 재측정해야 한다.
