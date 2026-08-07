# CreativeReporter 주간 동기화 — 데스크톱 예약 작업 런북

이 문서는 **회사 네트워크에 연결된 컴퓨터의 Claude 데스크톱 앱**에서 매주 실행되는 에이전트를 위한 완전한 지시서다. 이 문서만 읽고 처음부터 끝까지 수행할 수 있어야 한다.

> **2026-08-07 전면 개정.** 2026-07-27주 몰로코 노출 0 사고의 원인을 전수조사로 확정하고, 그 결과를 반영해 실행 시각·조회 절차·검증을 다시 짰다. 개정 근거는 [§A 적재 타임라인](#a-적재-타임라인--왜-11시인가)과 [§B 폴백 구조](#b-폴백-구조--왜-비용-검증으로는-못-잡는가)에 있다.

---

## 🔧 먼저 할 일 — 예약 작업 4개 교체 (사람이 데스크톱 앱에서 직접)

**기존 `월 09:30` 슬롯은 구조적으로 불가능하다.** 그 시각엔 필요한 원천 두 개가 모두 비어 있다(§A). 아래대로 교체한다.

1. Claude 데스크톱 앱 → **설정 → 예약 작업**
2. 기존 CR 주간 동기화 작업(월 09:30 · 12:30 · 16:30 · 화 09:30) **4개 모두 삭제**
3. 아래 **같은 프롬프트**로 새 작업 **4개** 생성

   | # | 요일·시각 (KST) | 역할 |
   |---|---|---|
   | 1 | **월 11:00** | 본 실행 |
   | 2 | **월 14:00** | 1차 재시도 |
   | 3 | **월 17:00** | 2차 재시도 |
   | 4 | **화 10:00** | 최종 재시도 |

   ```
   https://raw.githubusercontent.com/hansy-daangn/CreativeReporter/main/docs/WEEKLY_SYNC_TASK.md 를 읽고 그대로 수행해줘
   ```

4. 저장 후 첫 월요일에 Slack DM이 오는지 확인

> 데스크톱 예약 작업은 "2시간 뒤 다시"를 스스로 기다릴 수 없다. **같은 작업을 여러 슬롯에 걸고, 0) 멱등 체크가 이미 들어간 채널을 건너뛰게 하는 것**이 올바른 재시도 방식이다. 몇 번을 돌아도 안전하다.

---

## 전제 (설치 1회)

- Claude 데스크톱 앱에 확장 설치: `karrotsuperset.mcpb`, `karrotbigquery.mcpb` (설정 → 확장 → 파일 열기, 첫 사용 시 Okta 로그인)
- claude.ai 커넥터: **Supabase**, **Slack** 연결
- Supabase project: `newoydegfbnnqujgiips`

---

## A. 적재 타임라인 — 왜 11시인가

2026-08-07 전수조사(최근 5주 35개 파티션 `last_modified_time` 전수, 결측·재기록 0건)로 확정된 사실이다. **다시 조사하지 말고 전제로 삼아라.**

| 원천 | 주기 | 적재 시각 (KST) | 비고 |
|---|---|---|---|
| `maugrowth_marketing_appsflyer_report` | 매일 | **10:00** | D+1 |
| `molocoAD_daily_metrics` (콘솔) | 매일 | **10:01** | D+1 · 관측 최댓값 **10:08** |
| `moloco_creative_video_metrics` | 매일 | 11:00 | D+1 · CR 미사용(콘솔과 동일 4분위) |
| `p_ads_AdBasicStats_6496421123` (Google Ads DT) | 매일 | 11:01 | D+1 · **현재 CR 미사용** (§H) |
| `maugrowth_marketing_ad_report` / `adset_report` | **주** | **월 10:15** | 비파티션 **전면 재작성** — 이때 직전 완결 주 행이 **처음 생긴다** |
| `appsflyer.cohort_unified` | 매일 | — | **D+2** |

```
월요일
09:00 ─────────────────────────────────────────────
10:00 │ appsflyer_report (D+1)
10:01 │ molocoAD_daily_metrics ── 일요일치가 이때 들어옴 (최댓값 10:08)
10:15 │ ad_report 전면 재작성 ── 직전 완결 주 행이 처음 생김
11:00 │ ◀ 본 실행 (마진 45분)
14:00 │ ◀ 재시도 1
17:00 │ ◀ 재시도 2
화 10:00 ◀ 재시도 3
```

- **구 09:30 슬롯이 왜 불가능한가**: 그 시각엔 ① 콘솔에 대상 주의 마지막 날(일요일)이 없고 ② `ad_report`에는 대상 주 행 자체가 없다. 이 상태에서 대시보드를 조회하면 §B의 폴백이 발화한다.
- **'몰로코만 화요일 분리'는 불필요** — 콘솔·AF 모두 월 10:15면 완비된다.

---

## B. 폴백 구조 — 왜 '비용 검증'으로는 못 잡는가

대시보드 2075 몰로코 차트(데이터셋 20737)의 뷰 SQL 실물에서 `IFNULL(콘솔, AF)`이 걸린 컬럼은 **정확히 2개뿐**이다.

```sql
CASE WHEN media_source='moloco_int' THEN IFNULL(p.imp, r.imp_af) ELSE r.imp_af END AS impressions
CASE WHEN media_source='moloco_int' THEN IFNULL(p.clk, r.clk_af) ELSE r.clk_af END AS clicks
```

그 외 콘솔 유래 컬럼(`moloco_installs`, `moloco_spend_usd`, `moloco_revenue_usd`, `video_play_25~100`)은 **폴백 없이 그냥 NULL**이 된다.

```
콘솔 미적재 주에 벌어지는 일
┌────────────────────────────────────────────────┐
│ ad_report(비용) ──────────────┐                │
│                               ├─→ 행수·비용합 검증 ✅ 통과 │
│ 콘솔(노출·클릭) ─── 없음 ─────┘                │
│        ↓ IFNULL 폴백                            │
│   노출 = AF 노출(몰로코는 0) · 클릭 = AF 잣대(+34%) │
│   _v25~_v100 · _m_installs = 전부 NULL          │
└────────────────────────────────────────────────┘
비용은 ad_report 유래라 멀쩡하다 → 기존 '행수·비용합' 검증은 이 장애를 절대 못 잡는다.
```

**사고 실측(2026-07-27주)**: 노출 0(거짓 0 트리거가 키 제거) · 클릭 779,895(AF) — 직전 3주 콘솔 클릭 548K~564K 대비 +38%. 복구 후 실제값은 노출 13,076,692 · 클릭 584,193이었다.

> **원칙: 검증 지표는 장애 지점과 다른 원천에서 와야 한다.** 그래서 §3의 검증은 `_afImp`(AF 잣대)를 교차 잣대로 쓴다.

---

## 절대 규칙

1. **진행 중인 주는 절대 기록하지 않는다** — 대상은 항상 "직전 완결 주"(지난 월요일~일요일) 하나.
2. **검증 불일치 시 기록하지 않는다** — §3의 차단 조건 P1~P6 중 하나라도 걸리면 그 채널은 보류.
3. **재실행은 언제나 안전** — 멱등 체크와 저장 규칙이 중복을 막는다.
4. 마지막에 **반드시 Slack DM 알림** — 성공이든 실패든.
5. **`0`은 '없음'이 아니다.** 값을 못 받았으면 **그 키를 아예 넣지 마라.** 0을 채우면 "0이었다"는 거짓 사실이 기록돼 CTR·CPM이 0이 되거나 분모가 사라진다. 사이트는 키가 없으면 '데이터 없음'으로 안전하게 처리하지만, 0은 참값으로 믿는다.
   - 근거(기존 데이터에서 역추출): `_v25` 4,846행 중 값 0 = **0건**, `_q_revD0`·`_q_retD1Base`도 0건. 반면 `_m_installs`는 5,898행 중 **347건이 0** → **이 키만 0 허용**. 신규 적재를 다른 규약으로 넣으면 주차 간 추이가 왜곡된다.
6. **삭제 후 재삽입 금지.** 재적재는 **제자리 UPDATE** 또는 **`payload = 신규키 || 기존payload` 병합**으로 한다.
   - 이유: `_m_resReal`(ffprobe 실측)·`_svc`·`_name` 등 **재현 불가능한 키**가 payload에 들어 있다. 2026-07-27주 몰로코 146행 중 59행이 `_m_resReal` 보유 — 삭제했으면 영구 손실이었다.
7. **소재명 조인은 반드시 NFC 정규화** — §4.

---

## 수행 절차

### 0) 사전 점검

- 오늘 날짜(Asia/Seoul) 기준 **대상 주 시작일 W** = 직전 완결 주의 월요일(오늘이 월요일이면 7일 전).
- 사내 MCP(superset/bigquery) 도구가 응답하는지 가벼운 호출로 확인. 응답 없으면 → 실패 알림("회사 네트워크 아님 또는 Okta 만료") 후 종료.
- **멱등 체크**: Supabase(project `newoydegfbnnqujgiips`)에서

  ```sql
  select channel, count(*) from sr_weekly_creative_stats
  where week_start='W' and channel in ('Moloco','Meta','Google') group by channel;
  ```
  와 `select count(*) from sr_kv, jsonb_each(v) g where k='gwstat' and g.value ? 'W';`

  — 넷 다 이미 있으면 종료. DM(`[CR] 이미 최신이에요 ✅ (W주)`)은 **그날 첫 실행에서만** 보낸다. 재시도 슬롯으로 하루 여러 번 돌 때 같은 알림이 반복되면 소음이다(당일 두 번째 이후 실행은 조용히 종료).

---

### 1) 데이터 조회 (대시보드 2075의 세 차트, 대상 주만)

차트: **[MAU Marketing] 몰로코 크리에이티브별 성과 + 소재 미리보기**(40622) / **[MAU Marketing] 메타 광고소재별 성과 V2**(40615) / **[MAU Marketing] 구글 광고그룹별 성과 V2**(40617)

#### 1-a. ⚠️ 조회 직전에 캐시를 강제로 비운다 (필수)

```
superset MCP: force_refresh_chart_cache(chart_id=40622)
                                        (40615)
                                        (40617)
```

**이유**: 이른 슬롯이 폴백 상태의 결과를 캐시에 채워 두면, 나중에 실행해도 그 캐시를 그대로 받을 수 있다. 실제로 2026-07-27주는 삽입 시각이 월 20:57·화 11:55로 **업스트림 준비 후였는데도** 폴백 값이 들어갔다 — 남은 가장 유력한 경로가 캐시다. **캐시 강제 갱신을 건너뛰지 마라.**

#### 1-b. 조회 경로

- **1순위**: superset MCP로 각 차트의 데이터를 주(week)=W 필터로 조회.
- **2순위**(차트 데이터 조회가 안 되거나, 아래 원시 컬럼이 필요할 때): superset MCP로 데이터셋 20737의 SQL을 받아 bigquery MCP로 `virtual_table` 내부 컬럼을 직접 SELECT.

컬럼은 수동 CSV와 동일해야 한다(몰로코: `date,ad_name,creative_type,creative_preview,…지표`, 메타: `date,ad_name,…어트리뷰션/활성/신규+재활성 지표`, 구글: `date,adset_name,비용,노출 수,CPM,클릭 수,CPC,어트리뷰션 수,eCPI,활성 유저 수,활성 유저 eCPA,신규+재활성 유저 수,신규+재활성 유저 eCPA`). 다르면 중단·실패 알림(컬럼 목록 포함).

#### 1-c. 몰로코 — `impressions_af` / `clicks_af`를 반드시 함께 가져온다

차트가 기본으로 안 내보내므로 **2순위 SQL 경로에서 `virtual_table`의 `impressions_af`·`clicks_af`를 직접 SELECT**한다.

| 쿼리 컬럼 | payload 키 | 용도 |
|---|---|---|
| `impressions_af` | `_afImp` | **폴백 감지 전용** |
| `clicks_af` | `_afClk` | **폴백 감지 전용** |

> ⚠️ **`노출 수`·`클릭 수`와 절대 합산하지 마라.** 같은 대상의 **다른 잣대**(몰로코 콘솔 vs AppsFlyer)다. 오직 §3의 P1 판정에만 쓴다.

#### 1-d. 몰로코 — 기왕 가져올 때 원시 카운트까지

차트 CSV는 비율(완주율·리텐션)만 내보내 분자·분모를 복원할 수 없다. **2순위 SQL 경로에서 `virtual_table` 내부의 원시 컬럼을 함께 SELECT**해 payload에 그대로 실어라 — 사이트 화면(유저 질·영상 시청 탭)이 이 키들을 이미 렌더한다.

| 쿼리 컬럼 | payload 키 | 화면 |
|---|---|---|
| `video_play_25/50/75/100` | `_v25`/`_v50`/`_v75`/`_v100` | 영상 시청(구간별 유지) |
| `ret_d1_base`/`ret_d1_users` | `_q_retD1Base`/`_q_retD1Users` | 유저 질(D1 잔존) |
| `ret_d7_base`/`ret_d7_users` | `_q_retD7Base`/`_q_retD7Users` | 유저 질(D7 잔존) |
| `cohort_revenue_krw_d0/d7` | `_q_revD0`/`_q_revD7` | 유저 질(코호트 매출·ROAS D7) |
| `af_installs` / `re_attributions` / `re_engagements` | `_q_afInstalls` / `_q_reAtt` / `_q_reEng` | 유저 질(유입 구성) |
| `moloco_installs` | `_m_installs` | 참고 지표 (**0 허용 키**) |
| `creative_group_name` / `creative_type` / `resolution` | `_m_group` / `_m_ctype` / `_m_resName` | 그룹·유형·해상도 |
| `asset_url` | `_m_url` | 미리보기 — **NATIVE_VIDEO는 `creative_preview`가 이미지 썸네일이어도 영상이다. `video_url`이 풀린 `asset_url`을 넣어야 미리보기가 영상으로 열린다** |

#### 1-e. 몰로코 — 이번에 추가하는 payload 키 (중복 집계 위험 필독)

| payload 키 | 원천 컬럼 | ⚠️ 중복 집계 위험 |
|---|---|---|
| `_afImp` / `_afClk` | `impressions_af` / `clicks_af` | **`노출 수`·`클릭 수`와 합산 금지.** 같은 대상의 다른 잣대. 폴백 감지 전용 |
| `_m_spendUsd` / `_m_revUsd` | `moloco_spend_usd` / `moloco_revenue_usd` | **통화 혼용 금지.** `비용`은 KRW, 이건 USD. 환율 시점 미상 → ROAS는 USD끼리만 |
| `_m_engViews` | 콘솔 `Engaged_Views` | `_v25`와 **정의가 다르다**(플랫폼 정의 미공개). 완주율 계산에 섞지 말 것 |
| `_q_retD0Base` | `ret_install_base` | `_q_retD1Base`와 **분모가 다르다**(D1은 '어제 이전 설치'만 셈). 리텐션 분모로 바꿔 쓰면 값이 뛴다 |

---

### 2) 기록 (Supabase MCP)

#### 2-a. 몰로코 / 메타 → `sr_weekly_creative_stats`

행 단위 INSERT. 규칙(서버 `cr_save`와 동일):

- `channel`='Moloco'|'Meta', `week_start`=W(각 행의 date를 주 시작 월요일로 정규화), `ad_name`=소재 식별자, `payload`=그 행의 모든 지표를 JSONB로(수동 CSV의 컬럼명 그대로 키로), `uploaded_by`='auto-weekly'
- `on conflict (channel, week_start, ad_name) do nothing` · `(payload->>'비용')::numeric >= 1500`인 행만
- 통합 키도 함께: `_name`(=`ad_name`), `_svc`. 몰로코는 `_res`·`_ar`와 함께 `_m_resReal`(ffprobe 실측)·`_m_resName`(파일명 표기)을 넣는다 — 실측이 있으면 `_res`=실측값. **몰로코가 업로드본을 트랜스코딩해 실측이 640 계열로 나오는 것은 정상이니 1080으로 보정하지 말 것.** 메타는 해상도 데이터가 없으므로 `_res`를 만들어 넣지 않는다.

**되채움(매 실행)** — 최근 4주 중 `노출 수` 키가 없거나 P1(폴백)에 걸렸던 (채널, 주)가 있으면 소스를 재조회한다. 이제 콘솔 값이 있으면 **삭제하지 말고 제자리 UPDATE**로 채운다(절대 규칙 6):

```sql
-- 값이 있는 키만. 기존 키는 보존, 새 키만 추가:
update sr_weekly_creative_stats
   set payload = jsonb_build_object('_v25', $v25, '_q_retD1Base', $r1b /* … */) || payload
 where channel = $ch and week_start = $wk
   and substr(md5(normalize(ad_name, NFC)),1,8) = $h;

-- 이미 있는 키를 '올바른 값으로 교체'해야 할 때만(폴백 값 → 콘솔 값 등):
update sr_weekly_creative_stats
   set payload = payload || jsonb_build_object('노출 수', $imp, '클릭 수', $clk)
 where channel = $ch and week_start = $wk
   and substr(md5(normalize(ad_name, NFC)),1,8) = $h;
```

> `a || b`는 **b가 이긴다.** 보존하려면 `신규 || payload`, 덮어쓰려면 `payload || 신규`. 헷갈리면 §5 체크리스트를 보라.

#### 2-b. 구글 광고그룹 → `sr_kv` `k='gwstat'` 병합

- `adset_name`→광고그룹 ID: `sr_kv k='gmap'`의 `v->'adgroup'`(ID→이름)을 역변환. 매칭 실패는 `name:<이름>` 키로.
- 값 `{ID:{"W":[비용,노출,클릭,어트리뷰션,활성,신규재활성]}}` — 비용 1500 미만 행 제외.
- 병합은 그룹 키 안에서 주 키만 추가/덮어쓰기: `v = v || jsonb_set(...)` 방식으로 **다른 그룹·다른 주를 보존**할 것.

#### 2-c. 구글 소재(확장 소재) → `sr_weekly_creative_stats` (channel='Google')

⚠️ **아래 형태를 정확히 지켜야 사이트가 AEO/ACE 매체로 나눠 보여준다** (2026-08-03 첫 실행분이 이 규칙과 달라 '유형 미상 구글' 유령 매체가 생겨 수리했음).

- 소스: `AEO_weekly`·`ACE_weekly` 시트(주×광고그룹×애셋 지표) + 애셋 스프레드시트 7종(실적·방향·애셋 이름 — `항목 ID`/`애셋 ID`로 결합). 대상 주 W 행만. Drive 폴더 `18DV6jIpAH0mOyJVAdTKT1tAGDZ6DlywP`.
- **애셋 유형이 YouTube 동영상/이미지인 것만** — 광고 제목·설명(텍스트 애셋)은 넣지 않는다(그건 gwstat '정확 소스' 몫).
- **`ad_name` = `확장 소재` URL 그대로**(애셋 제목 아님). **ACE 캠페인 행만 URL 끝에 zero-width space(U+200B) 1개**를 붙인다(같은 소재가 AEO·ACE 양쪽에 있을 때 UNIQUE 충돌 방지 — 사이트 저장 경로와 동일 규칙). 그 외 어떤 경우에도 U+200B를 임의로 덧붙이지 않는다. **이 U+200B는 의도된 마커다 — §4의 제로폭 진단 대상에서 제외.**
- 같은 (URL×캠페인 유형)이 여러 광고그룹에 있으면 **숫자 지표는 합산**, 문자열은 비용 최대 행 기준 하나로.
- payload 필수 키: `_g_campaignId`(캠페인 ID — **절대 누락 금지**, 매체 분리 기준), `_g_adGroupId`, `비용`, `노출 수`, `클릭 수`, `어트리뷰션 수`(=설치), `활성 유저 수`(=인앱 액션), `신규+재활성 유저 수`(=조회연결 전환), `_g_conversions`, `_g_allConv`, `_g_convValue`, `_g_url`, `_g_assetId`, `_g_assetName`, `_g_assetType`, `_g_assetStatus`, `_g_status`, `_g_perfLabel`(실적), `_g_orientation`(방향). 소스에 있으면 `_g_firstOpen`·`_g_home`·`_g_interactions`·`_g_trueViews`도.
  - **`_g_campaignId`를 못 채웠을 때의 복구**: `sr_kv.ginfo`의 `[광고그룹ID].cpId`가 결정적 매핑을 갖고 있다. 추정하지 말고 이 값을 쓴다.
- payload 권장 키(사이트 화면이 읽는다 · 소스에 있으면 반드시 채울 것):
  - `_name` — **표시용 소재 이름**. 영상=영상 제목, 이미지=원본 파일명. ⚠️ 확장소재 URL을 그대로 넣지 말 것 (`ad_name`은 조인 키라 URL 그대로 유지).
  - `_res`(`"1080x1920"`)·`_ar`(`"9:16"`)·`_g_resSrc` — 애셋 이름에 규격이 박혀 있으면 `asset_name`, 보고서 '방향' 열 기반이면 `orientation`(가로 모드=1920x1080 / 정사각형=1080x1080 / 세로=1080x1920).
  - `_g_assetInstalls`·`_g_inAppActions`·`_g_viewThroughConv`·`_g_assetState` — 뒤 둘은 **이벤트 수**이므로 유저 수 컬럼과 섞지 말 것.
  - `_svc` — 서비스 분류.
- 합산 후 비용 1500 미만 제외 · `on conflict (channel, week_start, ad_name) do nothing` · `uploaded_by='auto-weekly'`.

---

### 3) 검증 — 교차 잣대 원칙

> **검증 지표는 장애 지점과 다른 원천에서 와야 한다.** 비용은 `ad_report` 유래라 콘솔 장애에 무반응이다.

#### 3-a. 합계 대조 (유지)

기록 후 재조회해 대상 주의 (몰로코 행수·비용합), (메타 행수·비용합), (gwstat 그룹수·비용합)이 1)에서 조회한 원본 합계와 일치(±1원, 1500 미만 제외분 감안)하는지 확인.

#### 3-b. 차단 조건 P1~P6 (신설 · **하나라도 걸리면 그 채널은 기록하지 않고 보류**)

| # | 조건 | 의미 |
|---|---|---|
| **P1** | 몰로코 `SUM(노출 수)` == `SUM(_afImp)` | **폴백 발화.** 콘솔 미적재로 판정 |
| **P2** | 몰로코 `SUM(노출 수)` == 0 | 콘솔 미적재 |
| **P3** | 어떤 행이든 `클릭 수 > 노출 수` | 물리적 불가 |
| **P4** | 콘솔 유래 키(`_v25`~`_v100`, `_m_installs`)가 그 주 **전 행에서 전부 비어 있음** | 콘솔 미적재의 2차 지문 |
| **P5** | 직전 주 대비 노출 합계 **90% 이상 급감** | 이상 감소 |
| **P6** | 필수 키(`비용`·`노출 수`·`클릭 수`, 몰로코·메타는 `어트리뷰션 수`) 보유율 **< 99%** | 지표 통째 누락 |

```sql
-- 대상 주 W. 결과가 0행이어야 정상.
with cur as (select * from sr_weekly_creative_stats where week_start='W')
select 'P1 폴백 발화(노출==_afImp)' issue, channel, count(*) n
from cur where channel='Moloco' and payload ? '_afImp'
group by 2 having sum((payload->>'노출 수')::numeric) = sum((payload->>'_afImp')::numeric)
union all
select 'P2 노출 합계 0', channel, count(*) from cur where channel='Moloco'
group by 2 having coalesce(sum((payload->>'노출 수')::numeric),0) = 0
union all
select 'P3 클릭>노출', channel, count(*) from cur
where payload ? '노출 수' and (payload->>'클릭 수')::numeric > (payload->>'노출 수')::numeric
group by 2
union all
select 'P4 콘솔 유래 키 전멸', channel, count(*) from cur where channel='Moloco'
group by 2 having count(*) filter (where payload ? '_v25' or payload ? '_m_installs') = 0
union all
select 'P5 노출 90% 이상 급감', c.channel, count(*) from cur c
group by 2 having sum((c.payload->>'노출 수')::numeric)
  < 0.1 * coalesce((select sum((p.payload->>'노출 수')::numeric) from sr_weekly_creative_stats p
                    where p.channel=c.channel and p.week_start=(date 'W' - 7)), 0)
union all
select 'P6 필수 키 보유율<99%', channel, count(*) from cur
group by 2 having count(*) filter (where payload ? '비용' and payload ? '노출 수' and payload ? '클릭 수')
                 < 0.99 * count(*);
```

**보류 처리**: 걸린 채널만 건너뛰고 **나머지 채널은 정상 기록**한다. 이미 기록했다면 그 (채널, 주)의 오염된 키만 제거한다(행 삭제 금지 — 절대 규칙 6).

Slack: `[CR] {채널} 보류 ⚠️ {M/D}주 — {P번호} {사유}. 다음 슬롯에서 재시도`

#### 3-c. 거짓 0 트리거는 1차 방어가 아니다

Supabase에는 `cr_strip_false_zero_impressions` 트리거가 있다(클릭>0인데 노출=0이면 노출 키 제거). **이건 마지막 방어선이지 1차 방어가 아니다** — 트리거가 걸렸다는 건 이미 3-b에서 잡았어야 한다는 뜻이다. 트리거 발화 흔적(비용>0인데 `노출 수` 키 없음)을 발견하면 P2 보류로 처리하라.

---

### 4) NFC 정규화 의무화

**BigQuery `Creative_Title` 한글의 7.9%가 NFD(분해형)다** — 2,288개 제목 중 181개, 1,321,573행 중 56,051행. Supabase는 NFC라 **이름으로 조인하면 무경고로 0건 매치**가 난다(실제 1차 백필에서 464행 누락).

```
BigQuery : ᄌ ᅮ ᄇ ᅡ ᆼ _1080x1080.mp4   NFD  e1848c e185ae e18487 e185a1 e186bc …
Supabase : 주 방 _1080x1080.mp4         NFC  eca3bc ebb0a9 …
           ↑ 화면상 완전히 동일. 조인은 0건.
```

**소재명으로 조인·대조·백필하는 모든 지점에 정규화를 건다.**

```sql
-- BigQuery
NORMALIZE(Creative_Title, NFC)
SUBSTR(TO_HEX(MD5(NORMALIZE(Creative_Title, NFC))), 1, 8)   -- 해시 조인 키

-- Postgres
normalize(ad_name, NFC)
substr(md5(normalize(ad_name, NFC)), 1, 8)
```

#### 진단 절차 — "이름이 분명 있는데 0건 매치"일 때

1. 양쪽에서 **hex를 찍어 본다**
   - BigQuery: `TO_HEX(CAST(Creative_Title AS BYTES))`
   - Postgres: `encode(convert_to(ad_name,'UTF8'),'hex')`
2. 무엇을 의심하나
   - **NFC/NFD** — 한글이 `e18…`로 시작하는 자모 나열이면 NFD (macOS 업로드 파일명이 흔한 원인)
   - **제로폭 `U+200B`** (`e2808b`) — 구글 ACE 마커는 **의도된 것**이니 예외
   - **NBSP `U+00A0`** (`c2a0`) — 일반 공백(`20`)과 다름
3. BigQuery 내부 조인은 양쪽 다 NFD라 **정상 작동한다** → 대시보드는 멀쩡하다. **시스템 경계를 넘는 순간에만** 터진다는 점을 기억하라.

---

### 5) 병합 방향 체크리스트

| 하려는 일 | 올바른 식 |
|---|---|
| 없는 키만 추가, 기존 값 보존 | `payload = 신규 \|\| payload` |
| 기존 값을 올바른 값으로 교체 | `payload = payload \|\| 신규` |
| 오염된 키만 제거 | `payload = payload - '키이름'` |
| 행 자체를 지우기 | **금지** (절대 규칙 6) |

- NULL·0인 값은 애초에 `jsonb_build_object`에 **넣지 않는다**(절대 규칙 5). 예외: `_m_installs`는 0 허용.

---

### 6) Slack DM 알림 (본인에게)

- 성공: `[CR] 수퍼셋 최신화 완료! ✅ {M/D}주 · 몰로코 +N행 · 메타 +M행 · 구글그룹 K개 (중복 스킵 S)`
- 이미 최신: `[CR] 이미 최신이에요 ✅ ({M/D}주) — 할 일 없음` (**그날 첫 실행에서만**)
- 실패: `[CR] 수퍼셋 최신화 실패 ❌ — 다시 실행해 주세요: {한 줄 사유}`
- 부분 성공: `[CR] 수퍼셋 최신화 부분 완료 ⚠️ — 성공: {…} / 실패: {…} · 다시 실행하면 빠진 것만 채워져요`
- **차단 조건 보류(3-b)**: `[CR] {채널} 보류 ⚠️ {M/D}주 — {P번호} {사유}. 다음 슬롯에서 재시도`
- **지표 누락(3-b P6)**: `[CR] 지표 누락 ⚠️ {M/D}주 {채널} {지표명} — 0으로 채우지 않고 키를 비웠어요. 소스 확인 필요: {한 줄 사유}`

---

## C. 하지 말 것

- **추정·보간·산술 채움** — 원천에 없으면 키를 비운다
- **이벤트 수와 유저 수를 한 지표로 섞기** — `_v*`·`_q_reEng`·조회연결 전환은 이벤트 수, `_q_ret*`는 유저 수
- **매체 횡단 합산** — CTR·CPM 같은 비율까지만 허용(귀속 단위가 매체마다 다르다)
- **광고그룹 단위 값을 소재 행에 내려 쓰기** — 예: `sr_kv.ginfo`의 v25~v100(%)는 광고그룹 단위다. 소재 행에 쓰면 귀속 단위 불일치
- **`_afImp`·`_afClk`를 `노출 수`·`클릭 수`와 합산**
- **행 삭제 후 재삽입**
- **사이트 코드(`index.html`) 수정** — 이 런북은 데이터 적재만 다룬다

---

## D. 참조 금지 — 사문화된 테이블

| 테이블 | 상태 |
|---|---|
| `maugrowth_weekly_creative_summary` | **2026-02-19 이후 정지** (최신 데이터 2026-02-09, 179일 경과) |
| `maugrowth_weekly_adgroup_summary` | **2026-02-19 이후 정지** |

이름이 그럴듯해 오인하기 쉽다. **쓰지 마라.** 주간 집계는 `maugrowth_marketing_ad_report`/`adset_report`(time_grain='week')에서 온다.

---

## E. 전환 검토 항목 (이번 재작성 범위 밖)

`p_ads_AdBasicStats_6496421123` — **Google Ads Data Transfer가 살아 있다.** AEO(22794864858)·ACE(22932296047) 캠페인이 **매일 D+1 11:01**로 BigQuery에 적재되는데 CR이 쓰지 않는다.

- 받을 수 있는 것: **광고(ad) 단위** 비용·노출·클릭·전환·전환가치·조회연결전환·상호작용·기기·네트워크
- 받을 수 없는 것: **애셋(asset) 단위 분해**, **영상 재생 4분위**
- → 구글 광고그룹 지표를 주 1회 수기 시트에서 매일 자동으로 전환할 여지가 있다. 다만 **애셋 단위는 여전히 시트가 필요**하므로 이번 재작성에서는 구현하지 않는다.

---

## 최초 1회 검증(드라이런) — 사람이 직접 붙여넣기

데스크톱 Claude에 아래를 붙여넣어 파이프라인을 검증한다(기록 없음):

> https://raw.githubusercontent.com/hansy-daangn/CreativeReporter/main/docs/WEEKLY_SYNC_TASK.md 를 읽고 **드라이런**으로 수행해줘 — 2)기록 단계는 건너뛰고, 0)·1)·3)의 조회·컬럼검증·합계·차단조건 P1~P6만 확인한 뒤 결과를 "[CR] 드라이런 결과 …" 포맷으로 Slack DM 보내줘.

드라이런 성공 → 예약 작업 등록(문서 상단 참조).

참고: 클라우드 쪽에도 매주 월요일 20:00(KST) 감시가 있어, 그때까지 데이터가 안 들어오면 `[CR] 이번 주 최신화가 아직 안 됐어요 ⏰` 푸시 알림이 자동 발송된다(Routine 세션은 Slack 미보유 — 클라우드 감시는 푸시, 데스크톱 작업은 Slack DM).

---

## 개정 이력

| 날짜 | 변경 |
|---|---|
| 2026-08-07 | 전수조사 반영 전면 개정 — 실행 시각 월 09:30 → **월 11:00·14:00·17:00 + 화 10:00** / `force_refresh_chart_cache` 선행 의무화 / 검증에 차단 조건 **P1~P6** 신설(교차 잣대) / **NFC 정규화 의무화** + hex 진단 절차 / `_afImp`·`_afClk`·`_m_spendUsd`·`_m_revUsd`·`_m_engViews`·`_q_retD0Base` 추가 / **행 삭제 금지**(절대 규칙 6) / 사문화 테이블·미사용 자산 표기 |
| 2026-08-06 | 지표 온전성 검사(3-b) 추가, 몰로코 IFNULL 폴백 경고 |
