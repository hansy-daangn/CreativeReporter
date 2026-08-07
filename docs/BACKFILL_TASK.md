# CR 백필 — 데스크톱 Claude용 실행 문서 (승인: 2026-08-06)

> 회사 네트워크의 Claude 데스크톱(superset/bigquery/Supabase MCP)에 이 한 줄을 붙여넣으세요:
> **"https://raw.githubusercontent.com/hansy-daangn/CreativeReporter/main/docs/BACKFILL_TASK.md 를 읽고 그대로 수행해줘"**

> **실행 완료(2026-08-07).** A·B는 끝났고 검증 통과(A: 노출 13,076,692 복원·클릭 584,193 콘솔 잣대 · B: 92주 6,573행,
> 무작위 5주×6키 BigQuery 대조 불일치 0건). C(실증 과거 주차)는 배치 쿼리 소재 미상으로 보류.
> 이 문서는 재실행·재사용을 위해 남긴다.

## 원칙 — 백필은 '원본 이식'이다

백필 = **BigQuery에 이미 존재하는 검증된 실측값을 같은 쿼리로 계산해 과거 주차에 소급 적재**하는 것.
추정·보간·산술 채움은 절대 하지 않는다. 원천에 값이 없으면 그 키는 비워 둔다(0 금지 — 절대 규칙 5).
Supabase에는 거짓 0 차단 트리거(`_cr_strip_false_zero_impressions`)가 걸려 있어 실수해도 노출 거짓 0은 저장되지 않는다.

## A. 몰로코 2026-07-27 주 재적재 (최우선)

이 주는 콘솔 미적재 시점에 AF 폴백 값이 들어가 **노출이 없고 클릭도 AF 잣대(779,895)**다.

1. `molocoAD_daily_metrics`에 2026-07-27~08-02 데이터가 있는지 확인. 없으면 이 항목은 보류하고 알림.
2. ⚠️ **삭제하지 마라(2026-08-07 정정).** 그 146행에는 `_m_resReal`(ffprobe 실측 59행)·`_svc`·`_name`처럼
   **재현 불가능한 키**가 들어 있어 지우면 영구 손실된다. 초판의 `delete` 지시는 폐기한다.
   대신 **제자리 UPDATE**로 같은 최종 상태를 만든다 — 노출 키 추가 + 클릭을 콘솔 값으로 덮어쓰기.
3. 나머지 주차·키는 `payload = 신규키 || 기존payload` 병합으로 적재한다(기존 키 100% 보존).
4. 검증: 그 주 `SUM(노출)>0`, `클릭 ≤ 노출`, 클릭이 직전 주들(548K~564K)과 같은 잣대(콘솔)로 돌아왔는지.

## B. 원시 카운트 소급 — 몰로코·메타 전 주차

superset MCP로 대시보드 2075 몰로코 차트의 뷰 SQL을 받아, **내부 `virtual_table`에 주(week)·creative 필터를 걸고
원시 컬럼을 SELECT**한다(차트가 내보내는 비율 말고 분자·분모 원본):

| virtual_table 컬럼 | payload 키 |
|---|---|
| video_play_25 / 50 / 75 / 100 | `_v25` / `_v50` / `_v75` / `_v100` |
| ret_d1_base / ret_d1_users | `_q_retD1Base` / `_q_retD1Users` |
| ret_d7_base / ret_d7_users | `_q_retD7Base` / `_q_retD7Users` |
| cohort_revenue_krw_d0 / d7 | `_q_revD0` / `_q_revD7` |
| af_installs / re_attributions / re_engagements | `_q_afInstalls` / `_q_reAtt` / `_q_reEng` |
| moloco_installs | `_m_installs` |
| asset_url (video_url 우선) | `_m_url` — NATIVE_VIDEO 미리보기가 영상으로 열리게 |

적재는 **행 삭제 없이 병합**한다(있는 키는 보존, 새 키만 추가):

```sql
update sr_weekly_creative_stats
set payload = payload || jsonb_build_object('_v25', $v25, '_v50', $v50, ...)  -- 값이 있는 키만
where channel = $ch and week_start = $wk and ad_name = $nm;
```

- 값이 NULL인 컬럼은 jsonb_build_object에 **넣지 않는다**(0·null로 채우지 말 것).
- 주차 범위: `sr_weekly_creative_stats`에 있는 몰로코·메타 전 주차. 한 주씩 처리하고 주별로 행 수를 로그.
- 검증: 무작위 3주를 골라 `_v25` 합이 BigQuery 합과 일치하는지 대조.

## C. 실증(umetrics) 과거 주차 — 조사 후 2단계

`sr_kv.umetrics`의 `trend_new_users`(현재 4주)·`weeks`(1주)를 과거로 늘리는 건이다.
이 배치의 원 쿼리는 이 저장소에 없으므로 **지어내지 말 것**.

2026-08-07 조사에서 확인된 단서:
- 적재 주체 `sr_kv.umetrics.updated_by = claude-umetrics` (최종 2026-08-05 17:05)
- 정의(basis): `maugrowth 설치·소재 도달 distinct(hoian), nu>=100. 몰로코 maugrowth 신규 없음(재관여 전담)`
- `sr_kv.syncspec.spec` 단계에 **`trend_new_users` 단계가 없다** — 문서화 자체가 안 된 배치다
- 유력 원천 후보: `karrotmarket.team_marketing.appsflyer_hoian_user_id_mapping` + karrotmetrics MCP

**필요 조치**: `claude-umetrics` 배치를 돌린 데스크톱 세션의 프롬프트/쿼리를 찾아
`syncspec.spec`에 `[2d] 실증 주간 갱신` 단계로 문서화해야 재현 가능해진다. 그전까지 과거 주차 확장은 불가.

## 마무리

Slack DM: `[CR] 백필 완료 ✅ A: {…} / B: {N주 M행} / C: {…}` (실패·보류 항목 명시)
