# 주간 자동 동기화 설계 (매주 월요일)

수퍼셋/구글애즈에서 CSV를 손으로 받아 드롭하는 흐름을, 매주 월요일 자동으로 돌리기 위한 설계.
Claude Code(CCR)의 예약 Routine이 데이터를 읽어 Supabase에 직접 쓰는 구조다 — 사이트 코드 변경 없음.

## 왜 이 구조인가

- `superset.kr.wekarrot.net`은 사내망 전용이라 클라우드 세션·Routine에서 **직접 접근 불가**(검증: 프록시 502). Superset MCP도 공개 레지스트리에 없음.
- 수퍼셋 차트의 원천은 BigQuery → **공식 "Google Cloud BigQuery" MCP 커넥터**(`execute_sql` 지원)로 같은 데이터를 직접 쿼리하는 것이 정답.
- 저장은 이 저장소가 이미 쓰는 Supabase MCP로 서버 규칙과 동일하게 수행.

## 활성화 조건 (1회, 사람 작업)

1. claude.ai → 설정 → 커넥터 → **Google Cloud BigQuery** 연결 (당근 구글 계정 — 수퍼셋 차트가 읽는 BQ 데이터셋 조회 권한 필요).
2. 연결 후 Claude에게 알리면: 세 차트의 원천 테이블·컬럼을 확인(수퍼셋 각 차트 → View query로 SQL 확보가 가장 빠름)하고, 아래 파이프라인을 검증한 뒤 주간 Routine을 생성한다.

## 파이프라인 (Routine이 매주 월요일 수행)

대상 주 = **마지막 완결 주**(직전 월요일 시작 ~ 일요일 마감). 진행 중인 주는 절대 넣지 않는다(부분 데이터가 중복 방지 규칙에 굳는 것 방지).

| # | 수퍼셋 차트 (대시보드 2075) | 목적지 | 규칙 |
|---|---|---|---|
| 1 | [MAU Marketing] 몰로코 크리에이티브별 성과 + 소재 미리보기 | `sr_weekly_creative_stats` (channel=Moloco) | 행=주×소재, payload=지표 전부. 중복은 `(channel,week_start,ad_name)` UNIQUE로 자동 스킵, 비용 ₩1,500 미만 제외 — `cr_save`와 동일 규칙 |
| 2 | [MAU Marketing] 메타 광고소재별 성과 V2 | `sr_weekly_creative_stats` (channel=Meta) | 〃 |
| 3 | [MAU Marketing] 구글 광고그룹별 성과 V2 | `sr_kv` `gwstat` | `adset_name`→광고그룹 ID(gmap 역변환), `{id:{주:[비용,노출,클릭,어트리뷰션,활성,신규재활성]}}` 주 단위 병합(같은 주 재실행 시 덮어쓰기 = 재산정 수용) — 사이트 `parseGroupWeekly`와 동일 |

- **payload 컬럼 매핑은 활성화 시 확정**: 사이트에 지금 드롭하는 CSV와 컬럼이 완전히 같아야 한다(#1·#2는 클라이언트 파서가 넣는 키 그대로). BQ 스키마와 최근 수동 CSV 1부씩을 대조해 고정한다.
- 검증: 삽입 전 주간 합계(비용·노출) 체크섬을 소스 쿼리와 대조, 불일치 시 중단·알림.
- 결과 통지: Routine 완료 알림(신규 N행·스킵 M행·gwstat K그룹 / 실패 사유).

## 남는 수동 작업

- **구글애즈 소재 보고서**(확장 소재 연결 보고서)는 구글애즈 API 권한이 별도라 이 파이프라인 밖 — 종전대로 '세그먼트 → 주 단위' 포함해 내보내 드롭(2단계 과제).
- 새 캠페인/광고그룹 생성 시 이름 매핑 CSV 1회 드롭(gmap 갱신 — #3의 이름→ID 역변환에 필요).

## 대안 경로 (BQ 권한이 안 나올 때)

Superset **Alerts & Reports**로 세 차트를 매주 월요일 이메일(CSV 첨부) 발송 → Gmail 커넥터를 쥔 Routine이 첨부를 읽어 같은 파이프라인 수행. Gmail MCP의 첨부 추출 가능 여부를 먼저 검증해야 하며, BQ 경로가 우선.
