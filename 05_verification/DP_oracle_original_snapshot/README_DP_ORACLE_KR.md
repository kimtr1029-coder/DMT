# Exact-erfc DP oracle 적용본

## 파일

- `FINAL_Q24_DP_ORACLE_channel25_20260813.m`: `channel_25db.txt` 환경
- `FINAL_Q24_DP_ORACLE_two_null_20260813.m`: deterministic two-null 환경
- `FINAL_Q24_DP_ORACLE_random_channel_20260813.m`: 재현 가능한 random-channel 환경
- `channel_25db.txt`: channel25 코드가 읽는 pole-residue 채널 파일

세 MATLAB 파일에서 Proposed Engine의 Q16/Q24 datapath, K/C, LUT, margin update,
per-QAM refinement 및 RTL reference export는 원본 그대로 유지했다. 바뀐 부분은
논문 비교용 Exact reference이다.

## 바뀐 Exact reference

기존 `Exact-erfc + Independent Control`은 각 QAM margin을 순차적으로 조정하는
heuristic이므로 전역 최적 기준이 아니었다. 따라서 어떤 채널에서는 Proposed
Engine이 그 reference보다 더 높은 rate를 내는 현상이 가능했다.

새 Exact 쪽은 각 tone에서 다음 후보 중 하나를 선택한다.

\[
\mathcal{A}_k=\{\text{unused},4,16,64,256\text{-QAM}\}
\]

단, Proposed Engine과 공정하게 비교하기 위해 동일한 Q16 base-threshold 후보
제한을 적용한다. 각 후보의 bit 수는 \(b_m\in\{0,2,4,6,8\}\)이고, exact-erfc
weighted error cost는

\[
e_{k,m}=b_m P_b(M_m,\gamma_k)
\]

이다. DP는 정확히 \(B\) bit를 싣는 allocation 중 최소 error sum을 보존한다.

\[
E_k(B)=\min_{m\in\mathcal{A}_k}
\left[E_{k-1}(B-b_m)+e_{k,m}\right]
\]

마지막으로 아래 조건을 만족하는 가장 큰 \(B\)를 선택한다.

\[
E_N(B)\le 10^{-4}B
\]

따라서 이 결과는 **동일 QAM/base-threshold 후보 집합 안에서의 전역 최대-rate
exact-erfc allocation**이다. 총 bit 수를 1100 같은 값으로 고정하는 제약은 없다.

## 코드에서 보이는 네 비교 항목

1. `A) Exact-erfc Global-Margin Heuristic (Ablation)`
2. `B) Exact-erfc DP Oracle (Same-Candidate Global Optimum)`
3. `C) Conservative Q24 LUT + Bit-Weighted Global Margin`
4. `D) Proposed Engine: Conservative Q24 LUT + Per-QAM Refinement`

Figure 1의 왼쪽은 2번 DP oracle, 오른쪽은 4번 Proposed Engine이다. 오른쪽에는
runtime conservative-Q24 BER와 offline exact-erfc BER가 모두 표시된다.

## 실행 방법

1. 이 폴더를 MATLAB working folder로 연다.
2. 원하는 `.m` 파일 하나를 실행한다.
3. 다른 채널 코드를 실행하기 전에 필요한 결과를 저장한다. 세 코드가 생성하는
   `rx_a_*.mem`과 `rx_a_summary.txt` 이름이 같아서 다음 실행이 이전 파일을
   덮어쓴다.
4. random 환경에서는 파일 상단의 `RANDOM_CHANNEL_ID`만 바꾸면 다른 재현 가능한
   채널을 얻는다.

allocation과 controller 결과만 빨리 확인하려면 각 파일의 `RUN_E2E = false`로
바꾸면 된다. Figure 1은 optional E2E 구간보다 앞에서 생성되므로 그대로 나온다.

## 실행 중 자동 검사

코드는 다음 오류를 자동으로 검출한다.

- DP 결과가 exact BER target을 위반하는 경우
- backtracking allocation과 DP terminal cost가 불일치하는 경우
- Oracle/Proposed의 QAM-to-bit mapping 또는 후보 집합이 다른 경우
- Proposed allocation이 exact-feasible인데 DP oracle의 total bits가 더 작은 경우

`Rate gap to exact-erfc DP oracle`은

\[
R_{\mathrm{oracle}}-R_{\mathrm{proposed}}
\]

으로 출력된다. Proposed allocation의 offline exact BER가 target 이내라면 이 값과
괄호 안의 bit gap은 음수가 될 수 없다.

