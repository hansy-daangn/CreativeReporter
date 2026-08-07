# CR 백필 — 데스크톱 Claude용 실행 문서 (승인: 2026-08-06)

> 회사 네트워크의 Claude 데스크톱(superset/bigquery/Supabase MCP)에 이 한 줄을 붙여넣으세요:
> **"https://raw.githubusercontent.com/hansy-daangn/CreativeReporter/main/docs/BACKFILL_TASK.md 를 읽고 그대로 수행해줘"**

## 원칙 — 백필은 '원본 이식'이다

백필 = **BigQuery에 이미 존재하는 검증된 실측값을 같은 쿼리로 계산해 과거 주차에 소급 적재**하는 것.
추정·보간·산술 채움은 절대 하지 않는다. 원천에 값이 없으면 그 키는 비워 둔다(0 금지 — 절대 규칙 5).
Supabase에는 거짓 0 차단 트리거(`_cr_strip_false_zero_impressions`)가 걸려 있어 실수해도 노출 거짓 0은 저장되지 않는다.

### ⛔ 행 삭제 금지 (2026-08-07 추가 · WEEKLY_SYNC_TASK 절대 규칙 6)

**재적재는 `delete` 후 재삽입이 아니라 제자리 UPDATE 또는 payload 병합으로 한다.**
payload에는 `_m_resReal`(ffprobe 실측)·`_svc`·`_name` 등 **소스에서 재현할 수 없는 키**가 들어 있다.
2026-07-27주 몰로코 146행 중 59행이 `_m_resReal`을 갖고 있었다 — 삭제했으면 영구 손실이었다.

```sql
-- 없는 키만 추가(기존 값 보존)
update sr_weekly_creative_stats set payload = 신규 || payload where …;
-- 기존 값을 올바른 값으로 교체(폴백 값 → 콘솔 값 등)
update sr_weekly_creative_stats set payload = payload || 신규 where …;
```

### ⚠️ 소재명 조인은 반드시 NFC 정규화 (2026-08-07 추가)

BigQuery `Creative_Title` 한글의 **7.9%가 NFD(분해형)**다(2,288개 중 181개 · 1,321,573행 중 56,051행).
Supabase는 NFC라 그냥 조인하면 **무경고로 0건 매치**가 난다 — 실제 1차 백필에서 464행을 놓쳤다.

```sql
BigQuery : SUBSTR(TO_HEX(MD5(NORMALIZE(Creative_Title, NFC))), 1, 8)
Postgres : substr(md5(normalize(ad_name, NFC)), 1, 8)
```

"이름이 분명 있는데 0건 매치"면 **hex를 찍어** NFC/NFD·제로폭(U+200B)·NBSP를 의심하라.
(구글 ACE 행의 U+200B는 **의도된 마커**이니 예외.)

## A. 몰로코 2026-07-27 주 재적재 (최우선)

이 주는 콘솔 미적재 시점에 AF 폴백 값이 들어가 **노출이 없고 클릭도 AF 잣대(779,895)**다.

1. `molocoAD_daily_metrics`에 2026-07-27~08-02 데이터가 있는지 확인. 없으면 이 항목은 보류하고 알림.
2. 있으면 콘솔값을 소재별로 집계한다 — **NFC 정규화 필수**:
   ```sql
   SELECT SUBSTR(TO_HEX(MD5(NORMALIZE(Creative_Title, NFC))),1,8) h,
          SUM(Impressions) AS `노출 수`, SUM(Clicks) AS `클릭 수`
   FROM `karrotmarket.team_marketing.molocoAD_daily_metrics`
   WHERE Date BETWEEN '2026-07-27' AND '2026-08-02'
   GROUP BY 1
   ```
3. **행을 지우지 말고 제자리 UPDATE**로 콘솔값을 덮어쓴다(아래 B의 원시 카운트도 함께 병합):
   ```sql
   update sr_weekly_creative_stats
      set payload = payload || jsonb_build_object('노출 수', $imp, '클릭 수', $clk)
    where channel='Moloco' and week_start='2026-07-27'
      and substr(md5(normalize(ad_name, NFC)),1,8) = $h;
   ```
4. 검증: 그 주 `SUM(노출)>0`, `클릭 ≤ 노출`, 클릭이 직전 주들(548K~564K)과 같은 잣대(콘솔)로 돌아왔는지.

> **실행 완료 (2026-08-07)**: 노출 없음 → **13,076,692**(BQ 콘솔 13,077,961 − 비용<1500 제외분 1,269) · 클릭 779,895(AF) → **584,193**(콘솔) · 146/146행 노출 보유 · 클릭>노출 위반 0건.

## B. 원시 카운트 소급 — 몰로코·메타 전 주차

superset MCP로 대시보드 2075 몰로코 차트의 뷰 SQL을 받아, **내부 `virtual_table`에 주(week)·creative 필터를 걸고
원시 컬럼을 SELECT**한다(차트가 내보내는 비율 말고 분자·분모 원본):

| virtual_table 컬럼 | payload 키 |
|---|---|
| impressions_af / clicks_af | `_afImp` / `_afClk` — **폴백 감지 전용 · `노출 수`·`클릭 수`와 합산 금지** |
| video_play_25 / 50 / 75 / 100 | `_v25` / `_v50` / `_v75` / `_v100` |
| ret_d1_base / ret_d1_users | `_q_retD1Base` / `_q_retD1Users` |
| ret_d7_base / ret_d7_users | `_q_retD7Base` / `_q_retD7Users` |
| cohort_revenue_krw_d0 / d7 | `_q_revD0` / `_q_revD7` |
| af_installs / re_attributions / re_engagements | `_q_afInstalls` / `_q_reAtt` / `_q_reEng` |
| moloco_installs | `_m_installs` |
| asset_url (video_url 우선) | `_m_url` — NATIVE_VIDEO 미리보기가 영상으로 열리게 |

적재는 **행 삭제 없이 병합**한다. ⚠️ `a || b`는 **b가 이긴다** — 기존 값을 보존하려면 **신규를 왼쪽**에 둔다:

```sql
update sr_weekly_creative_stats
set payload = jsonb_build_object('_v25', $v25, '_v50', $v50, ...) || payload  -- 값이 있는 키만
where channel = $ch and week_start = $wk
  and substr(md5(normalize(ad_name, NFC)),1,8) = $h;   -- NFC 정규화 필수
```

- 값이 NULL·0인 컬럼은 jsonb_build_object에 **넣지 않는다**. 예외: `_m_installs`는 0 허용
  (기존 데이터 역추출 근거 — `_v25` 4,846행 중 0 = 0건, `_m_installs` 5,898행 중 0 = 347건).
- 주차 범위: `sr_weekly_creative_stats`에 있는 몰로코·메타 전 주차. 한 주씩 처리하고 주별로 행 수를 로그.
- 검증: 무작위 3주 이상을 골라 `_v25` 합이 BigQuery 합과 일치하는지 대조(**같은 소재 집합**으로 비교 — Supabase는 비용 1500 미만이 빠져 있다).

> **실행 완료 (2026-08-07)**: 몰로코 47주 + 메타 45주 = **92주 6,573행** 갱신
> (`_m_installs` +6,051 · `_q_reEng` +654 · `_q_retD1Base` +313 · `_q_afInstalls` +313 · `_v25` +236 · `_q_revD7` +176 · `_q_revD0` +108).
> 검증: 무작위 5주 × 6키 전 행 BigQuery 대조 **불일치 0건**.
> ⚠️ 1차 실행에서 **NFD 이름 464행을 놓쳤다** — NFC 정규화 후 재실행으로 복구. 위 규칙이 그 교훈이다.

## C. 실증(umetrics) 과거 주차 — 조사 후 2단계

`sr_kv.umetrics`의 `trend_new_users`(현재 4주)·`weeks`(1주)를 과거로 늘리는 건이다.
이 배치의 원 쿼리는 이 저장소에 없으므로 **지어내지 말 것** — 기존 주간 실증 배치(karrotmetrics 기반)가
쓰는 쿼리를 먼저 찾아 같은 정의로 과거 주차를 계산해야 한다. DATA_SURVEY_PROMPT.md 조사 결과에
그 소재가 파악되면 진행하고, 못 찾으면 "실증 배치 쿼리 위치 미상"으로 보고만 하라.

> **조사 결과 (2026-08-07) — 보류: 쿼리 위치 미상.** 지어내지 않고 보고만 한다.
>
> | 항목 | 실측 |
> |---|---|
> | 현재 상태 | `trend_new_users` 4주(06-22·06-29·07-06·07-13) · `weeks` 1주(07-20) |
> | 적재 주체 | `sr_kv.umetrics.updated_by = **claude-umetrics**` (최종 2026-08-05 17:05) |
> | 정의(basis) | `"maugrowth 설치·소재 도달 distinct(hoian), nu>=100. 몰로코 maugrowth 신규 없음(재관여 전담)"` |
> | 저장소 내 쿼리 | **없음** — `docs/` 전체 grep 결과 설명문만 존재 |
> | `sr_kv.syncspec.spec` | 단계 `[0][1][2][2b][2c][3][4][5]` 중 **`trend_new_users` 단계 없음** (`[2c]` 서비스 도달 `svc7_w*`만 정의) |
> | 유력 원천 후보 | `karrotmarket.team_marketing.appsflyer_hoian_user_id_mapping` + karrotmetrics MCP |
>
> **필요 조치**: `claude-umetrics` 배치를 돌린 데스크톱 세션의 프롬프트·쿼리를 찾아 `syncspec.spec`에 `[2d] 실증 주간 갱신` 단계로 **문서화**해야 재현 가능해진다. 그전까지 과거 주차 확장은 불가.

## 마무리

Slack DM: `[CR] 백필 완료 ✅ A: {…} / B: {N주 M행} / C: {…}` (실패·보류 항목 명시)
