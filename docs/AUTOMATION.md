# 주간 자동 동기화 설계 (매주 월요일)

수퍼셋/구글애즈에서 CSV를 손으로 받아 드롭하는 흐름을, 매주 월요일 자동으로 돌리기 위한 설계.
Claude Code(CCR)의 예약 Routine이 데이터를 읽어 Supabase에 직접 쓰는 구조다 — 사이트 코드 변경 없음.

## 네트워크 사실관계 (2026-07-28 검증)

- `superset.kr.wekarrot.net` · `bigquery-mcp.kr.wekarrot.net` · `superset-mcp.kr.wekarrot.net` 전부 **공개 DNS에 없음(NXDOMAIN) = 사내망 전용**. 사내 MCP 번들(karrotbigquery/karrotsuperset.mcpb)은 이 주소로 붙는 원격 프록시라, **클라우드 세션·Routine·claude.ai 커스텀 커넥터 어디서도 접근 불가**. 오직 사내망(사무실/VPN)의 데스크톱에서만 동작한다.
- 저장 쪽(Supabase)은 공개라 어디서든 가능 — 병목은 데이터 읽기뿐.

## 실행 경로 두 가지

**경로 A — 데스크톱 예약 작업 (지금 바로 가능)**
1. 회사 노트북 Claude 데스크톱 앱 → 설정 → 확장(Extensions) → `karrotbigquery.mcpb`(필요시 `karrotsuperset.mcpb`) 열어 설치 → 첫 사용 때 Okta 로그인.
2. Supabase 커넥터도 같은 계정에 연결돼 있으면, 데스크톱의 **예약 작업**(매주 월요일)에 아래 '주간 동기화 프롬프트'를 등록.
3. 노트북이 사내망에 있는 월요일 아침에 실행됨 — 실패 시 다음 접속 때 수동 1회 실행으로 보충.

**경로 B — 클라우드 Routine (완전 무인, 권한 협의 필요)**
데이터가치화팀에 요청해 마케팅 데이터셋에 대한 **직접 BigQuery 접근**(개인 IAM 또는 서비스 계정)을 받으면, BQ API(googleapis.com)는 공개망이라 공식 "Google Cloud BigQuery" 커넥터 + 매주 월요일 CCR Routine으로 사람 개입 0의 파이프라인이 된다. 사내 MCP를 못 쓰는 환경(클라우드 자동화)이 사유.

## 주간 동기화 프롬프트 (경로 A 예약 작업용)

> CreativeReporter 주간 동기화. ① 직전 완결 주(지난 월요일~일요일)의 주 시작일을 계산해라. ② BigQuery MCP로 수퍼셋 대시보드 2075의 세 차트 원천을 그 주만 조회해라: 몰로코 크리에이티브별 성과+소재 미리보기, 메타 광고소재별 성과 V2, 구글 광고그룹별 성과 V2 (각 차트의 View query SQL 참고). ③ Supabase(newoydegfbnnqujgiips)에 기록: 몰로코/메타 행은 sr_weekly_creative_stats에 channel/week_start/ad_name/payload로 INSERT … ON CONFLICT (channel,week_start,ad_name) DO NOTHING, 비용 1500 미만 제외. 구글 광고그룹은 sr_kv 'gwstat'에 {광고그룹ID:{주:[비용,노출,클릭,어트리뷰션,활성,신규재활성]}}로 주 단위 병합(adset_name→ID는 sr_kv 'gmap'의 adgroup 역변환). ④ 삽입 전후 주간 합계(비용·노출)를 소스와 대조하고 결과(신규 N행·스킵 M행·gwstat K그룹 또는 실패 사유)를 보고해라. 진행 중인 주는 절대 넣지 마라.

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
