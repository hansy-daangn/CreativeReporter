# CreativeReporter

퍼포먼스 소재 성과분석 대시보드입니다.<br/>
CSV를 화면에 끌어다 놓으면 즉시 분석됩니다.<br/><br/>
https://hansy-daangn.github.io/CreativeReporter/

## 사용법

- 첫 화면에서 비밀번호 입력 → 클라우드(Supabase)에 쌓인 주간 성과 로드
- 파일명이 `meta_` · `moloco_` · `google_` 로 시작하는 **주간** 리포트만 저장소에 누적 (월간·일간·매체 미상은 임시 분석만)
- 아무 곳에서나 `/hansy` + Enter → 이 기기의 업로드에 서명 (`/logout` 해제)

## 지원 리포트

- **Moloco 크리에이티브 리포트** — `creative_preview`·`creative_type` 자동 감지, 이미지/영상 미리보기
- **Google Ads 확장 소재 연결 보고서** — `주` 컬럼 주간 리포트, ROAS·전환 지표
- **일반 ad_name CSV(메타 등)** — `thumbnail_url`·`image_url`·`creative_preview`·`미리보기` 컬럼이 있으면 썸네일 자동 연동
- **구글 이름 매핑 CSV** — `광고그룹 ID`+`광고그룹`(또는 캠페인 쌍, `항목 ID`+`애셋` 쌍) 컬럼이 있는 파일을 드롭하면 ID/URL 대신 실제 이름 표시 (클라우드에 누적 저장)
  - 내보내기: Google Ads → 보고서 편집기에서 위 열만 담아 CSV 다운로드 → 그대로 드롭
