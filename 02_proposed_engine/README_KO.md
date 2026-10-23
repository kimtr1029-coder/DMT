# 현재 Proposed Engine

`rtl`의 세 파일이 최종 Q24/refinement 구현이다. Module 이름에 맞춰 파일명만
정리했으며 원본과 byte-identical이다. 기존 balanced(2).v 및 REFINE 이름의
원본은 `originals`에 있다.

합성 top은 `per_qam_bitloading_pipeline_top_balanced`.
`proposed_files.f`는 이 폴더를 current directory로 사용한다.
기능 검증 경로는 `../05_verification/same_function_ablation`이다.
그곳의 baseline은 ablation이며 주 비교군은 `../03_chebyshev_baseline/unbiased`다.

