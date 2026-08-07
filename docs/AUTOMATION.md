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

## 주간 동기화 실행 (경로 A — 확정)

상세 절차·알림 포맷·드라이런 방법은 **[docs/WEEKLY_SYNC_TASK.md](WEEKLY_SYNC_TASK.md)** (예약 작업이 매주 읽는 런북). 예약 작업 프롬프트는 런북 raw URL을 읽고 수행하라는 한 줄이라, 절차 개선은 저장소 커밋만으로 반영된다.

### 실행 시각 (2026-08-07 개정)

**월 11:00 · 14:00 · 17:00 + 화 10:00** — 같은 프롬프트 4개(재시도 스케줄). 구 `월 09:30·12:30·16:30 + 화 09:30`은 폐기했다.

원천 적재 타임라인(KST, 5주 파티션 전수 확인):

| 원천 | 주기 | 적재 시각 |
|---|---|---|
| `maugrowth_marketing_appsflyer_report` | 매일 | 10:00 (D+1) |
| `molocoAD_daily_metrics` (몰로코 콘솔) | 매일 | **10:01** (D+1, 관측 최댓값 10:08) |
| `maugrowth_marketing_ad_report` / `adset_report` | **주** | **월 10:15** (비파티션 전면 재작성 — 직전 완결 주 행이 이때 처음 생김) |
| `appsflyer.cohort_unified` | 매일 | D+2 |

**왜 09:30이 불가능했나**: 그 시각엔 ① 콘솔에 대상 주의 마지막 날(일요일)이 없고 ② `ad_report`에 대상 주 행 자체가 없다. 이 상태로 대시보드 2075를 조회하면 몰로코 노출·클릭에 걸린 `IFNULL(콘솔, AF)` 폴백이 발화해 **노출 0 · 클릭 AF 잣대**가 기록된다(2026-07-27주 사고). 11:00은 최대 관측치 10:15 + 45분 마진이다.

'몰로코만 화요일 분리'는 불필요 — 콘솔·AF 모두 월 10:15면 완비된다.

**감시 장치(클라우드, 설정 완료)**: 매주 월요일 20:00 KST에 CCR Routine이 Supabase를 검사해 직전 완결 주 데이터(몰로코·메타 행, gwstat 주)가 비어 있으면 `[CR] 이번 주 최신화가 아직 안 됐어요 ⏰` 푸시 알림을 보낸다(검사는 뷰어 게이트 RPC `cr_sync_status`를 curl로 — Routine 세션은 MCP 커넥터 미보유). 정상일 땐 침묵. 데스크톱이 꺼져 작업이 아예 안 돈 경우까지 잡는 안전망.

## 파이프라인 (Routine이 매주 월요일 수행)

대상 주 = **마지막 완결 주**(직전 월요일 시작 ~ 일요일 마감). 진행 중인 주는 절대 넣지 않는다(부분 데이터가 중복 방지 규칙에 굳는 것 방지).

| # | 수퍼셋 차트 (대시보드 2075) | 목적지 | 규칙 |
|---|---|---|---|
| 1 | [MAU Marketing] 몰로코 크리에이티브별 성과 + 소재 미리보기 | `sr_weekly_creative_stats` (channel=Moloco) | 행=주×소재, payload=지표 전부. 중복은 `(channel,week_start,ad_name)` UNIQUE로 자동 스킵, 비용 ₩1,500 미만 제외 — `cr_save`와 동일 규칙 |
| 2 | [MAU Marketing] 메타 광고소재별 성과 V2 | `sr_weekly_creative_stats` (channel=Meta) | 〃 |
| 3 | [MAU Marketing] 구글 광고그룹별 성과 V2 | `sr_kv` `gwstat` | `adset_name`→광고그룹 ID(gmap 역변환), `{id:{주:[비용,노출,클릭,어트리뷰션,활성,신규재활성]}}` 주 단위 병합(같은 주 재실행 시 덮어쓰기 = 재산정 수용) — 사이트 `parseGroupWeekly`와 동일 |

- **payload 컬럼 매핑은 활성화 시 확정**: 사이트에 지금 드롭하는 CSV와 컬럼이 완전히 같아야 한다(#1·#2는 클라이언트 파서가 넣는 키 그대로). BQ 스키마와 최근 수동 CSV 1부씩을 대조해 고정한다.
- 검증: 삽입 전 주간 합계(비용·노출) 체크섬을 소스 쿼리와 대조, 불일치 시 중단·알림. **단, 합계 대조만으로는 부족하다** — 비용은 `ad_report` 유래라 콘솔 장애에 무반응이므로, 런북 3-b의 차단 조건 **P1~P6**(교차 잣대)을 반드시 함께 돌린다.
- 결과 통지: Routine 완료 알림(신규 N행·스킵 M행·gwstat K그룹 / 실패 사유).

### 주의 — 알려진 함정 (2026-08-07 전수조사)

| # | 함정 | 대응 |
|---|---|---|
| 1 | **몰로코 IFNULL 폴백** — 대시보드 2075에서 `impressions`·`clicks` **2개 컬럼만** 콘솔→AF로 조용히 대체된다. 나머지 콘솔 유래 컬럼은 NULL이 될 뿐이라 비용 검증을 그대로 통과 | `_afImp`·`_afClk`를 함께 적재하고 `노출 수 == _afImp`를 차단 조건 P1로 판정 |
| 2 | **Superset 차트 캐시** — 이른 슬롯이 폴백 상태 결과를 캐시에 채우면 나중 실행도 그 값을 받는다 | 조회 직전 `force_refresh_chart_cache` 호출 |
| 3 | **NFD 한글** — BigQuery `Creative_Title`의 7.9%가 분해형. Supabase(NFC)와 이름 조인이 무경고로 0건 매치 | 모든 이름 조인에 `NORMALIZE(x, NFC)` / `normalize(x, NFC)` |
| 4 | **행 삭제 후 재삽입** — `_m_resReal`(ffprobe 실측)·`_svc`·`_name`은 소스에서 재현 불가 | 제자리 UPDATE 또는 payload 병합만 사용 |
| 5 | **사문화 테이블** — `maugrowth_weekly_creative_summary`·`maugrowth_weekly_adgroup_summary`는 2026-02-19 이후 정지 | 참조 금지 |

## 남는 수동 작업

- **구글애즈 소재 보고서**(확장 소재 연결 보고서)는 구글애즈 API 권한이 별도라 이 파이프라인 밖 — 종전대로 '세그먼트 → 주 단위' 포함해 내보내 드롭(2단계 과제).
- 새 캠페인/광고그룹 생성 시 이름 매핑 CSV 1회 드롭(gmap 갱신 — #3의 이름→ID 역변환에 필요).

## 대안 경로 (BQ 권한이 안 나올 때)

Superset **Alerts & Reports**로 세 차트를 매주 월요일 이메일(CSV 첨부) 발송 → Gmail 커넥터를 쥔 Routine이 첨부를 읽어 같은 파이프라인 수행. Gmail MCP의 첨부 추출 가능 여부를 먼저 검증해야 하며, BQ 경로가 우선.
