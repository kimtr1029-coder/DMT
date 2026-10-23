# DMT 논문 Codex 인계 자료

2026-10-23 정리. 기존에 남아 있던 **원본 99개**와 압축 안의 코드를 회수했다.
원고와 코드를 새로 재현한 자료가 아니다. 이번에 추가한 것은 안내 문서,
원고 Markdown 변환본, 결과 요약표, 파일 목록과 무결성 기록이다.

## 바로 시작하기

1. 압축을 풀고 `DMT_Codex_Handoff_20261023` 폴더를 Codex 작업 폴더로 연다.
2. `00_CODEX_PROMPT.md`의 지시문을 Codex에 붙여 넣는다.
3. 원고 → Proposed RTL → Chebyshev → MATLAB → 검증 자료 순서로 읽게 한다.

| 목적 | 위치 |
|---|---|
| 가장 최근 회수된 한글 원고 | `01_manuscripts/current/Electronics_Letters_한글_검토본_투고조건반영.docx` |
| 대응 영문 원고 | `01_manuscripts/current/Electronics_Letters_English_Submission_Ready.docx` |
| Codex용 본문·수식 텍스트 | 위 두 파일과 같은 이름의 `.md` |
| 최종 Proposed Engine RTL 3개 | `02_proposed_engine/rtl/` |
| 최종 unbiased Chebyshev 전체 코드 | `03_chebyshev_baseline/unbiased/` |
| Channel-25, two-null, random MATLAB | `04_matlab/`의 세 채널 폴더 |
| K/C 생성·전수검증, oracle 검증과 TB | `05_verification/` |
| 수도코드, 그림 PDF/SVG·편집 소스 | `06_figures/` |
| 참고논문·Word 템플릿 | `07_references/` |
| 이전 TRX system 검증 맥락 | `08_system_context/` |
| 이전 baseline·MATLAB·지연 측정 | `09_history/` |
| 연구 요약·수치 출처 | `RESEARCH_CONTEXT_KO.md`, `10_recorded_results.csv` |
| 실행 방법 | `RUN_GUIDE_KO.md` |
| 확보 범위·남은 확인 사항 | `RECOVERY_STATUS_KO.md` |
| 원본 이름·수정일·SHA-256 | `FILE_INVENTORY.csv` |

최신 한글·영문 원고의 기록된 수정일은 **2026-08-24**다. 수도코드는
2026-10-12, 그림 자료는 2026-10-11까지 별도로 남아 있다. 최근 그림이
이전 원고에 모두 삽입됐다고 가정하지 않는다.

한글 원고의 실제 확장자는 **DOCX**다. Current 원고는 원본 그대로 보존했으며,
저자·구현 조건 등에 빈칸이 있어 제출 완료본으로 취급하지 않는다.

**Proposed는 conservative Q24, 비교군은 unbiased Chebyshev**다.
이 둘을 바꾸어 읽지 않는다. erfc 기반 DP oracle은 offline software 기준이다.
이전 TRX/alpha/ablation 코드를 현재 최종 engine에 합쳐 compile하지 않는다.

여기서 확인할 수 없는 노트북의 이후 수정본까지 포함됐다고 보장할 수는 없다.

