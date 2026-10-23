# Unbiased Piecewise-Chebyshev BER RTL Baseline

이 패키지는 proposed engine과 비교하기 위한 정상적인 **양방향 Chebyshev
baseline**이다. 기존 conservative 버전에서 구간별 constant coefficient `c0`에
더했던 one-sided upward bias만 제거했다. Chebyshev fitting, 구간 수, 차수,
고정소수점 형식, RTL datapath 및 controller는 유지했다. Minimax fitting이나
coefficient local optimization은 사용하지 않았다.

## 최종 합성 top

```text
per_qam_bitloading_pipeline_top_chebyshev_q24
```

Quartus 또는 standard-cell 합성에는 `chebyshev_files.f`의 다섯 RTL 파일과
`engine_100mhz.sdc`를 사용한다. Proposed 및 기존 결과와 동일한 library,
100-MHz constraint, hierarchy/flattening, ROM mapping 및 activity 조건을 적용해야
공정한 area/power 비교가 된다.

## 구현 구조

- 근사 함수: `h(z) = erfc(sqrt(z))`
- 유효 범위: `1.25 <= z < 12.25`
- 입력 SNR: Q16
- coefficient: Q30
- BER 출력: Q24
- 44개 균일 구간, 구간 폭 0.25
- 구간별 degree-4 Chebyshev fit
- 각 구간의 4,001개 실수 sample에 `numpy.polynomial.chebyshev.chebfit` 적용
- Chebyshev-basis coefficient를 local power basis로 변환한 뒤 Q30 양자화
- 네 단계 Horner pipeline
- coefficient bank: `44 x 5 x 32 = 7,040 bit = 880 byte`
- 전체 datapath latency: 7 clocks
- initiation interval: 1 tone/clock
- one-sided bias: **없음**
- minimax post-optimization: **없음**

원래 conservative ROM과 직접 대조한 결과, 새 coefficient는 bias 전 원본
`chebfit` coefficient와 전부 동일하다. 변경된 것은 44개 `c0`에서 각각
137–2,320 Q30 code의 upward bias를 제거한 것뿐이며 `c1`–`c4`는 비트 단위로
동일하다.

## 측정 결과

### 수치 오차

전체 720,896개 Q16 `z` code를 검사한 `h(z)` 오차:

```text
minimum signed error = -3.99891960795e-8
maximum signed error = +3.75073039433e-8
maximum absolute error = 3.99891960795e-8
RMSE = 2.06555233899e-9
negative codes = 363,139
positive codes = 357,757
```

양수와 음수 오차가 모두 존재하므로 이 baseline은 one-sided upper bound가
아니다.

BER `5e-5 <= BER <= 2e-4`에서 exact-erfc 대비 최대 상대오차:

| QAM | 최대 underestimate | 최대 overestimate | False-safe buckets | False-reject buckets |
|---:|---:|---:|---:|---:|
| 4 | 0.059453% | 0.059836% | 0 | 9 |
| 16 | 0.060461% | 0.059750% | 0 | 9 |
| 64 | 0.061089% | 0.058923% | 0 | 8 |
| 256 | 0.063436% | 0.056797% | 0 | 6 |

`false-safe=0`은 검사한 Q16 domain과 `BER=1e-4` crossing에서 얻은 exhaustive
결과일 뿐, one-sided 성질을 뜻하지 않는다.

### RTL 검증

- Directed/random continuous inputs: 4,116개, mismatch 0
- 전체 Q16-z/QAM inputs: 2,883,584개, mismatch 0
- datapath latency: 7 clocks
- II: 1
- Full hierarchy `proc; opt_clean; check`: 0 problems

### 전체 controller/profile 측정 @ 100 MHz

| Profile | Cycles | Latency | Bits | Rate | Runtime BER | Offline exact BER | Violation |
|---|---:|---:|---:|---:|---:|---:|---:|
| channel25 | 51,109 | 511.09 us | 1,044 | 37.8261 Gbps | 9.77246e-5 | 9.77362e-5 | 0 |
| two-null | 58,103 | 581.03 us | 1,044 | 37.8261 Gbps | 9.64612e-5 | 9.64742e-5 | 0 |

두 profile의 최종 allocation은 모두 offline exact-erfc BER `1e-4`를 만족했다.
Runtime BER은 exact BER보다 channel25에서 0.01188%, two-null에서 0.01343%
낮았다. 즉 system 결과에서도 이 baseline이 upper bound가 아님을 확인할 수 있다.

## 재생성 및 검증

Coefficient/수치 audit:

```bash
python3 tools/generate_unbiased_chebyshev.py
```

Directed/random 및 exhaustive RTL reference vector:

```bash
python3 tools/gen_rtl_vectors.py
python3 tools/gen_exhaustive_rtl_vectors.py
```

ModelSim channel latency:

```text
do run_modelsim_latency.do
```

## 논문 표기

권장 표기:

```text
high-accuracy unbiased 44-segment degree-4 piecewise-Chebyshev RTL baseline
```

이 baseline에는 `conservative`, `one-sided`, `minimax`, `exact-erfc RTL`이라는
표현을 사용하지 않는다. Exact-erfc는 software oracle로만 표기한다.

## Area/power 재합성 주의

이 환경에는 사용자가 기존 결과에 사용한 Quartus/standard-cell library와
activity setup이 없으므로 논문용 area/power는 새로 측정하지 않았다. 구조와
bit width는 동일하지만 coefficient bit pattern 변화로 constant optimization이
달라질 수 있으므로, 과거 Chebyshev 수치(50,833.080286 cell area, 2.5061 mW)를
자동으로 재사용하지 말고 이 패키지의 top으로 동일 프로젝트에서 재합성해야 한다.
