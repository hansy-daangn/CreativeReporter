# CreativeReporter

퍼포먼스 소재 성과분석 대시보드입니다.<br/>
https://hansy-daangn.github.io/CreativeReporter/

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — 사이트 구조와 매커니즘 상세 설명
- **[docs/REBUILD_PROMPT.md](docs/REBUILD_PROMPT.md)** — 무에서 동일 시스템을 재구축하는 완전제작 프롬프트

## 사용법

- 첫 화면에서 비밀번호 입력 → 클라우드(Supabase)에 쌓인 주간 성과 로드
- 파일명이 `meta_` · `moloco_` · `google_` 로 시작하는 **주간** 리포트만 저장소에 누적 (월간·일간·매체 미상은 임시 분석만)

## 지원 리포트

- **Moloco 크리에이티브 리포트** — `creative_preview`·`creative_type` 자동 감지, 이미지/영상 미리보기
- **Google Ads 확장 소재 연결 보고서** — `주` 컬럼 주간 리포트, ROAS·전환 지표
- **일반 ad_name CSV(메타 등)** — `thumbnail_url`·`image_url`·`creative_preview`·`미리보기` 컬럼이 있으면 썸네일 자동 연동
- **구글 이름 매핑 CSV** — `광고그룹 ID`+`광고그룹`(또는 캠페인 쌍, `항목 ID`+`애셋` 쌍) 컬럼이 있는 파일을 드롭하면 ID/URL 대신 실제 이름 표시 (클라우드에 누적 저장)
  - 내보내기: Google Ads → 보고서 편집기에서 위 열만 담아 CSV 다운로드 → 그대로 드롭
- **구글 광고그룹 보고서** — 드롭하면 그룹 이름·캠페인·상태(운영/일시중지/정책 제한)·타겟 CPA·누적 성과·영상 재생 퍼널을 광고그룹 ID 기준으로 저장, 그룹별 보기와 그룹 상세에 표시
  - 이미 저장된 정보와 달라지는 항목이 있으면 업데이트 여부를 확인창으로 물어봄 (신규 항목뿐이면 바로 반영)
- **이미지 소재 OCR 이름** — 이름이 URL뿐인 구글 이미지 애셋은 이미지 속 텍스트를 추출해 표시(`OCR` 마크 부착, 공식 애셋 이름 등록 시 자동 대체). 별도 저장소(kv `ocr`)라 통째 삭제로 즉시 취소 가능
- 매체 판별 우선순위: 리포트 형식 자동 감지 → 미리보기 URL 도메인 → 드롭존 → 파일명
