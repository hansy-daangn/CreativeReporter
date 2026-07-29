# CreativeReporter

퍼포먼스 소재 성과분석 대시보드입니다.<br/>
https://hansy-daangn.github.io/CreativeReporter/

## 🎨 화면 테마 4종

사이드바 하단에서 **테마를 고르면 화면이 바뀝니다**(기기 단위 설정 · 데이터·점수에는 영향 없음).
아래 링크는 **비밀번호 없이 합성 샘플 데이터로** 각 테마를 바로 볼 수 있는 미리보기이고, 화면 하단 바에서 4종을 즉시 전환해 비교할 수 있습니다.

| 테마 | 성격 | 언제 쓰나 | 미리보기 |
|---|---|---|---|
| **당근** (기본) | SEED 계열 중성 회색 + 브랜드 오렌지를 활성 지점에만 | 평소 · 당근 제품군과 같은 결 | [▶ 열기](https://raw.githack.com/hansy-daangn/CreativeReporter/claude/design-themes/proposals/t-karrot.html) |
| **정밀** | 저채도 중성 회색 · 행 높이를 줄여 한 화면에 더 많은 행 · 각진 칩 | 표를 오래 들여다보며 분석할 때 | [▶ 열기](https://raw.githack.com/hansy-daangn/CreativeReporter/claude/design-themes/proposals/t-precision.html) |
| **차분** | 따뜻한 종이 · 넉넉한 여백 · 알약 칩 · 큰 소재 이름 | 훑어보기 · 공유 · 발표 | [▶ 열기](https://raw.githack.com/hansy-daangn/CreativeReporter/claude/design-themes/proposals/t-calm.html) |
| **야간** | 어두운 지면에서 숫자가 떠오름 | 장시간 분석 · 어두운 환경 | [▶ 열기](https://raw.githack.com/hansy-daangn/CreativeReporter/claude/design-themes/proposals/t-night.html) |

> 위 링크는 [raw.githack.com](https://raw.githack.com)이 브랜치 파일을 그대로 렌더링해 **병합 없이 클릭 즉시** 열립니다. 병합 후에는 GitHub Pages 주소로도 열립니다 → [당근](https://hansy-daangn.github.io/CreativeReporter/proposals/t-karrot.html) · [정밀](https://hansy-daangn.github.io/CreativeReporter/proposals/t-precision.html) · [차분](https://hansy-daangn.github.io/CreativeReporter/proposals/t-calm.html) · [야간](https://hansy-daangn.github.io/CreativeReporter/proposals/t-night.html)

테마는 **색 역할값과 밀도·모서리만** 바꾸고 구조·정보 위계·성과 5단계의 의미는 공유합니다. 색·글자·간격의 규칙은 **[docs/DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md)** 에 정리돼 있습니다(현황 실측 근거 포함 — 하드코딩 색 112종·글자 크기 22종·여백 128종이 문제였습니다).

**본 사이트(`index.html`)에 이미 반영된 개선**
- 표 툴바 등급 범례 제거 · **제목행을 툴바 바로 아래에 고정**(뷰포트 sticky, 스크롤바 1개, 이음새 없음) · 클릭 정렬·`+` 세부지표.
- **소재 이름 한 줄 말줄임 + 칩 한 줄 + 모든 행 높이 동일** · **'소재 N' 실시간 개수**를 제목행에 표시(필터 반영) · 본문 폭 확대(좌우 여백 축소).
- 툴바 한 줄 유지 · 사이드바 액센트 회색 · 리사이즈 렉 개선 · 밀도형 타이포.
- 재발 방지: `scroll-padding-top`으로 모든 이동이 고정 헤더 아래 안착 · 새로고침 시 최상단 시작 · 제목행 sticky를 메인 표에만 한정.
- 접근성: 정렬 상태 강조, 키보드(Enter/Space)·`aria-sort`·`focus-visible`.

*미리보기 페이지는 `node proposals/build.mjs`로 생성합니다 — 본 앱(`index.html`)에 데모 부트스트랩만 주입하고 `data-theme`을 지정하므로, 테마의 단일 소스는 언제나 `index.html`입니다.*

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
