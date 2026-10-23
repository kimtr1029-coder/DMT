이 폴더는 내가 진행하던 Electronics Letters용 DMT adaptive bit-loading engine
논문의 원고, MATLAB, Verilog RTL, unbiased Chebyshev 비교군, 채널 입력,
검증 자료와 그림을 모은 인계 패키지다. 논문을 더 발전시키기 전에 현재
구현과 주장을 정확하게 파악해 줘.

먼저 `00_START_HERE.md`, `AGENTS.md`, `RESEARCH_CONTEXT_KO.md`,
`RECOVERY_STATUS_KO.md`, `RUN_GUIDE_KO.md`를 읽어 줘.

이후 아래 실제 파일을 읽어 줘.

1. `01_manuscripts/current`의 최신 한글·영문 원고. Markdown은 검색용이고
   수식·그림은 원본 DOCX로 확인해 줘.
2. `02_proposed_engine/rtl`의 세 RTL과
   `06_figures/pseudocode/algorithm1-per-qam-margin-search.tex`.
3. `03_chebyshev_baseline/unbiased`의 README, RTL, coefficient 생성기,
   검증 보고서와 results.
4. `04_matlab`의 Channel-25/two-null/random 최신 MATLAB과 채널 입력.
5. `05_verification`의 K/C 전수검증, DP oracle 기록, proposed TB.
6. 필요한 그림과 참고논문. `08_system_context`와 `09_history`는
   이전 구현 맥락으로 구분해서 읽어 줘.

읽은 뒤 파일 근거와 함께 한국어로 정리해 줘.

- 연구 목표·차별점, BER식·fixed-point 구현과 controller 동작.
- 원고·RTL·MATLAB·수도코드의 일치 여부와 불일치.
- 기존 기록, 실제 재실행한 결과, 원시 로그가 없는 주장의 구분.
- 논문을 발전시키는 데 효과적인 후속 실험·분석의 우선순위.

최종 Proposed는 conservative Q24이고, hardware 비교군만 **unbiased
piecewise-Chebyshev**다. erfc 기반 DP oracle은 software 성능 기준이다.
1100 bit 고정, 과거 alpha-scan/validator/swap, minimax/rational baseline을
현재 최종 구현으로 섞지 마.

파일 이름에 final/ready가 있어도 빈칸·검증되지 않은 주장을 짚어 줘.
원본을 덮어쓰지 말고 현재 상태를 근거로 설명한 다음 개선 작업을 이어가 줘.

