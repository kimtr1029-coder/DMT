# Q24 one-sided K/C 자동 생성 및 전수검증

이 폴더는 채널별 curve fitting 결과가 아니다. 최종 RTL의 정수 연산을 그대로 대상으로 하여 네 QAM tier의 `K_Q16`, `C_Q16`을 자동 생성하고, 설계 구간의 모든 Q16 선형 SNR 입력 코드를 검증한다.

## 실행

MATLAB에서 이 폴더를 current folder로 설정한 뒤 다음을 실행한다.

```matlab
results = generate_conservative_KC_Q24;
```

이 명령은 `K=0:65535` 전체를 탐색하고 다음 파일을 생성한다.

- `KC_Q24_generated_results.mat`
- `KC_Q24_generated_results.csv`
- `KC_Q24_generated_constants.vh`
- `KC_Q24_generated_report.txt`

독립 검증만 다시 실행하려면 다음을 사용한다.

```matlab
report = verify_conservative_KC_Q24_exhaustive;
```

위 기본 모드는 모든 Q16 코드를 RTL 계단함수의 서로 겹치지 않는 구간으로 정확히 분할하여 검증한다. 실제 정수 코드 134,915,306개를 하나씩 직접 열거하는 추가 확인도 제공한다.

```matlab
report = verify_conservative_KC_Q24_exhaustive([], [], 'literal');
% 또는 두 방법의 최솟값/최댓값까지 상호 대조
report = verify_conservative_KC_Q24_exhaustive([], [], 'both');
```

`literal`/`both`는 1억 개가 넘는 `erfc` 계산을 수행하므로 실행 시간이 길다. 논리적으로는 기본 `interval` 모드도 표본검사가 아니라 완전한 전수증명이다.

## 정확히 무엇을 최적화하는가

RTL에서 선형 SNR 입력 코드 (x\)에 대해

\[
n=\left\lfloor\frac{K_{Q16}x}{2^{27}}\right\rfloor,
\quad s=\left\lfloor\frac{n}{32}\right\rfloor,
\quad a=n\bmod 32
\]

이고, 출력은

\[
\widehat P_{Q24}
=\left\lfloor
\frac{C_{Q16}L[a]}{2^{8+s}}
\right\rfloor
\]

이다. 동일한 (n)을 갖는 모든 입력에서 RTL 출력은 완전히 같다. 그 입력 구간은

\[
I_n=\left[
\left\lceil\frac{n2^{27}}{K_{Q16}}\right\rceil,
\left\lceil\frac{(n+1)2^{27}}{K_{Q16}}\right\rceil-1
\right]
\]

이다. exact-erfc BER은 SNR에 대해 단조감소하므로 각 구간의 왼쪽 끝만 확인하면 그 구간 전체의 one-sided 조건을 증명할 수 있다. 오른쪽 끝에서는 해당 구간의 가장 큰 과대평가 비율을 얻는다.

각 (K)에 필요한 최소 (C)는 다음 정수식으로 직접 계산한다.

\[
C(K)=\max_n\left\lceil
\frac{\left\lceil P_{\mathrm{exact}}(x_{n,L})2^{24}\right\rceil
2^{8+s_n}}{L[a_n]}
\right\rceil.
\]

`C(K)>65535`이면 그 (K)는 RTL에 넣을 수 없으므로 제외한다. 남은 후보에서

\[
J(K)=\max_n
\frac{\widehat P(x_{n,R};K,C(K))}{P_{\mathrm{exact}}(x_{n,R})}
\]

를 최소화한다. 동률이면 작은 `C`, 그다음 작은 `K`를 선택한다.

## 검증 구간

각 QAM tier가 처음 할당될 수 있는 base threshold부터 exact BER이 (2^{-20}) 이상인 마지막 Q16 SNR 코드까지다.

| QAM | 시작 | 마지막 | 입력 코드 수 |
|---:|---:|---:|---:|
| 4 | 6 dB, code 260904 | 13.557612297 dB, code 1486761 | 1,225,858 |
| 16 | 12 dB, code 1038676 | 20.440229567 dB, code 7252753 | 6,214,078 |
| 64 | 18 dB, code 4135042 | 26.577049407 dB, code 29797846 | 25,662,805 |
| 256 | 24 dB, code 16461899 | 32.564110543 dB, code 118274463 | 101,812,565 |

시작보다 낮은 SNR에서는 해당 QAM tier가 base threshold 조건을 만족하지 않아 할당되지 않는다. 마지막 코드보다 높은 SNR에서는 exact BER이 (2^{-20})보다 작으며, 최종 controller가 global BER 비교에서 동일한 (2^{-20}) residual을 미리 차감한다. 따라서 이 범위는 특정 channel simulation에 맞춘 범위가 아니라 최종 architecture가 요구하는 전체 직접보장 구간이다.

## 전역 탐색 결과

| QAM | K_Q16 | C_Q16 | 계단 구간 | 최소 추정/정확 비율 | 최대 추정/정확 비율 |
|---:|---:|---:|---:|---:|---:|
| 4 | 50734 | 12756 | 464 | 1.000003296861 | 1.194710934171 |
| 16 | 10213 | 10206 | 473 | 1.000086956350 | 1.224691028657 |
| 64 | 2436 | 8057 | 466 | 1.000051466519 | 1.230309867429 |
| 256 | 602 | 6506 | 458 | 1.000134940559 | 1.234443529019 |

최소 비율이 모두 1보다 크므로 underestimation은 0건이다. 기존 최종 RTL에 들어 있는 상수와 자동 생성 결과가 정확히 일치하며, generator는 다르면 즉시 오류를 발생시킨다.

## 논문에서 주장할 수 있는 범위

이 결과로 주장할 수 있는 것은 “정의된 base-threshold-to-residual 구간에서, 최종 RTL의 양자화·LUT·절삭까지 포함한 estimator가 exact-erfc BER을 절대 과소평가하지 않는다”는 것이다. 모든 채널에서 bit-loading 결과가 exact-erfc와 같거나 항상 최적이라는 뜻은 아니다. 채널 통계와 rate gap은 별도의 3번 실험으로 입증해야 한다.
