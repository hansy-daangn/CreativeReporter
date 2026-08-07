# CreativeReporter 주간 동기화 — 데스크톱 예약 작업 런북

이 문서는 **회사 네트워크에 연결된 컴퓨터의 Claude 데스크톱 앱**에서 매주 월요일 실행되는 에이전트를 위한 완전한 지시서다. 이 문서만 읽고 처음부터 끝까지 수행할 수 있어야 한다.

## 전제 (설치 1회)

- Claude 데스크톱 앱에 확장 설치: `karrotsuperset.mcpb`, `karrotbigquery.mcpb` (설정 → 확장 → 파일 열기, 첫 사용 시 Okta 로그인)
- claude.ai 커넥터: **Supabase**, **Slack** 연결(이미 연결돼 있으면 그대로)
- 예약 작업 프롬프트(매주 월요일 09:30 권장):
  > https://raw.githubusercontent.com/hansy-daangn/CreativeReporter/main/docs/WEEKLY_SYNC_TASK.md 를 읽고 그대로 수행해줘

## 절대 규칙

1. **진행 중인 주는 절대 기록하지 않는다** — 대상은 항상 "직전 완결 주"(지난 월요일~일요일) 하나.
2. **검증 불일치 시 기록하지 않는다** — 조회 합계와 기록 예정 합계가 다르면 중단하고 실패 알림.
3. **재실행은 언제나 안전** — 저장 규칙이 중복을 막아준다(아래). 같은 주를 두 번 돌려도 부작용 없음.
4. 마지막에 **반드시 Slack DM 알림**(아래 포맷)을 보낸다 — 성공이든 실패든.
5. **`0`은 '없음'이 아니다.** 어떤 지표든 값을 못 받았으면 **그 키를 아예 넣지 마라.** 0을 채우면 "0이었다"는 거짓 사실이 기록돼 CTR·CPM이 0이 되거나 분모가 사라진다. 사이트는 키가 없으면 '데이터 없음'으로 안전하게 처리하지만, 0은 참값으로 믿는다.

## 수행 절차

### 0) 사전 점검
- 오늘 날짜(Asia/Seoul) 기준 **대상 주 시작일 W** = 직전 완결 주의 월요일(오늘이 월요일이면 7일 전).
- 사내 MCP(superset/bigquery) 도구가 응답하는지 가벼운 호출로 확인. 응답 없으면 → 실패 알림("회사 네트워크 아님 또는 Okta 만료") 후 종료.
- **멱등 체크**: Supabase(project `newoydegfbnnqujgiips`)에서
  `select channel,count(*) from sr_weekly_creative_stats where week_start='W' and channel in ('Moloco','Meta','Google') group by channel;`
  와 `select count(*) from sr_kv, jsonb_each(v) g where k='gwstat' and g.value ? 'W';`
  — 넷 다 이미 있으면 "[CR] 이미 최신이에요 ✅ (W주)" DM 후 종료.

### 1) 데이터 조회 (Superset 대시보드 2075의 세 차트, 대상 주만)
- 차트: **[MAU Marketing] 몰로코 크리에이티브별 성과 + 소재 미리보기** / **[MAU Marketing] 메타 광고소재별 성과 V2** / **[MAU Marketing] 구글 광고그룹별 성과 V2**
- 1순위: superset MCP로 각 차트의 데이터를 주(week)=W 필터로 조회.
- 2순위(차트 데이터 조회가 안 되면): superset MCP로 각 차트의 SQL을 얻어 bigquery MCP `execute_sql`로 W 조건을 걸어 실행.
- 컬럼은 수동 CSV와 동일해야 한다(몰로코: `date,ad_name,creative_type,creative_preview,…지표`, 메타: `date,ad_name,…어트리뷰션/활성/신규+재활성 지표`, 구글: `date,adset_name,비용,노출 수,CPM,클릭 수,CPC,어트리뷰션 수,eCPI,활성 유저 수,활성 유저 eCPA,신규+재활성 유저 수,신규+재활성 유저 eCPA`). 다르면 중단·실패 알림(컬럼 목록 포함).

#### ⚠️ 몰로코 노출 수는 AppsFlyer가 아니라 몰로코 콘솔에서 가져와야 한다

**원칙(2026-07 확정): 몰로코 노출·VTR은 콘솔(`molocoAD_daily_metrics`), 비용·클릭·기여는 AppsFlyer(`adset_report`). 혼용 금지.**

`adset_report`에는 노출 컬럼이 있지만 **값이 항상 0**이다. 이걸 그대로 쓰면 `노출 수 = 0`이 기록되고, 클릭은 정상이라 **클릭 > 노출**이라는 물리적으로 불가능한 행이 만들어진다(2026-07-27 실측: 146행 전부, 클릭 779,895 · 노출 0 · 광고비 3,527만원).

- 몰로코 차트가 `adset_report`만 준다면 **`molocoAD_daily_metrics`를 조인해 노출을 채워라.**
- 조인이 불가능하면 **`노출 수` 키를 아예 넣지 마라.** `0`으로 채우지 말 것 — 아래 '절대 규칙 5' 참고.

> 이 사고의 전말: 46주(2025-09-08~2026-07-20)는 사람이 몰로코 콘솔 내보내기로 올려 노출이 정상이었고, 자동화 첫 주(2026-07-27)에 소스가 Superset 차트로 바뀌면서 노출만 0이 됐다. **같은 실행의 구글 154행·메타 19행은 노출이 정상**이라 자동화 전체 문제가 아니라 몰로코 소스 문제임이 확정된다.

### 2) 기록 (Supabase MCP)
- **몰로코/메타** → `sr_weekly_creative_stats`에 행 단위 INSERT. 규칙(서버 cr_save와 동일):
  - `channel`='Moloco'|'Meta', `week_start`=W(각 행의 date를 주 시작 월요일로 정규화), `ad_name`=소재 식별자, `payload`=그 행의 모든 지표를 JSONB로(수동 CSV의 컬럼명 그대로 키로), `uploaded_by`='auto-weekly'
  - `on conflict (channel, week_start, ad_name) do nothing` · `(payload->>'비용')::numeric >= 1500`인 행만
  - 통합 키도 함께: `_name`(=`ad_name`), `_svc`. 몰로코는 `_res`·`_ar`와 함께 `_m_resReal`(ffprobe 실측)·`_m_resName`(파일명 표기)을 넣는다 — 실측이 있으면 `_res`=실측값. **몰로코가 업로드본을 트랜스코딩해 실측이 640 계열로 나오는 것은 정상이니 1080으로 보정하지 말 것.** 메타는 해상도 데이터가 없으므로 `_res`를 만들어 넣지 않는다(사이트도 표시하지 않는다).
- **구글 광고그룹** → `sr_kv` `k='gwstat'` 병합:
  - `adset_name`→광고그룹 ID: `sr_kv k='gmap'`의 `v->'adgroup'`(ID→이름)을 역변환. 매칭 실패는 `name:<이름>` 키로.
  - 값 `{ID:{"W":[비용,노출,클릭,어트리뷰션,활성,신규재활성]}}` — 비용 1500 미만 행 제외.
  - 병합은 그룹 키 안에서 주 키만 추가/덮어쓰기: `v = v || jsonb_set(...)` 방식으로 **다른 그룹·다른 주를 보존**할 것.
- **구글 소재(확장 소재)** → `sr_weekly_creative_stats`(channel='Google') — ⚠️ **아래 형태를 정확히 지켜야 사이트가 AEO/ACE 매체로 나눠 보여준다** (2026-08-03 첫 실행분이 이 규칙과 달라 '유형 미상 구글' 유령 매체가 생겨 수리했음):
  - 소스: `AEO_weekly`·`ACE_weekly` 시트(주×광고그룹×애셋 지표) + 애셋 스프레드시트 7종(실적·방향·애셋 이름 — `항목 ID`/`애셋 ID`로 결합). 대상 주 W 행만.
  - **애셋 유형이 YouTube 동영상/이미지인 것만** — 광고 제목·설명(텍스트 애셋)은 넣지 않는다(그건 gwstat '정확 소스' 몫).
  - **`ad_name` = `확장 소재` URL 그대로**(애셋 제목 아님 — 제목은 중복되고, 과거 주와 이름이 이어져야 소재별 추이가 붙는다). **ACE 캠페인 행만 URL 끝에 zero-width space(U+200B) 1개**를 붙인다(같은 소재가 AEO·ACE 양쪽에 있을 때 UNIQUE 충돌 방지 — 사이트 저장 경로와 동일 규칙). 그 외 어떤 경우에도 U+200B를 임의로 덧붙이지 않는다.
  - 같은 (URL×캠페인 유형)이 여러 광고그룹에 있으면 **숫자 지표는 합산**, 문자열은 비용 최대 행 기준 하나로.
  - payload 필수 키: `_g_campaignId`(캠페인 ID — **절대 누락 금지**, 매체 분리 기준), `_g_adGroupId`, `비용`, `노출 수`, `클릭 수`, `어트리뷰션 수`(=설치), `활성 유저 수`(=인앱 액션), `신규+재활성 유저 수`(=조회연결 전환), `_g_conversions`(전환수), `_g_allConv`(모든 전환), `_g_convValue`(전환 가치), `_g_url`, `_g_assetId`, `_g_assetName`, `_g_assetType`, `_g_assetStatus`, `_g_status`, `_g_perfLabel`(실적), `_g_orientation`(방향). 소스에 있으면 `_g_firstOpen`(first_open)·`_g_home`(home)·`_g_interactions`(상호작용 수)·`_g_trueViews`(TrueView 조회수)도 — AEO 신규 단가 등 채점에 쓰인다.
  - payload 권장 키(사이트 화면이 읽는다 · 소스에 있으면 반드시 채울 것):
    - `_name` — **표시용 소재 이름**. 영상=영상 제목, 이미지=원본 파일명(네이밍 룰셋 준수). ⚠️ 확장소재 URL을 그대로 넣지 말 것 — 사이트는 URL이면 이름으로 취급하지 않는다. (`ad_name`은 조인 키라 URL 그대로 유지)
    - `_res`(`"1080x1920"` 형식)·`_ar`(`"9:16"`)·`_g_resSrc` — 해상도와 그 출처. 애셋 이름에 규격이 박혀 있으면 `asset_name`, 보고서 '방향' 열 기반이면 `orientation`(가로 모드=1920x1080 / 정사각형=1080x1080 / 세로=1080x1920).
    - `_g_assetInstalls`(설치)·`_g_inAppActions`(인앱 액션)·`_g_viewThroughConv`(조회연결 전환)·`_g_assetState`(애셋 상태) — 뒤 둘은 **이벤트 수**이므로 유저 수 컬럼과 섞지 말 것.
    - `_svc` — 서비스 분류(서비스별 7일 지표가 이 값으로 주지표를 고른다).
  - 합산 후 비용 1500 미만 제외 · `on conflict (channel, week_start, ad_name) do nothing` · `uploaded_by='auto-weekly'`.

### 3) 검증

**(a) 합계 대조** — 기록 후 재조회해 대상 주의 (몰로코 행수·비용합), (메타 행수·비용합), (gwstat 그룹수·비용합)이 1)에서 조회한 원본 합계와 일치(±1원, 1500 미만 제외분 감안)하는지 확인.

**(b) 지표 온전성 검사 (필수 · 2026-08-06 추가)** — 합계 대조만으로는 **광고비 말고 다른 지표가 통째로 빠져도 통과한다**. 실제로 몰로코 노출이 전부 0이 된 주가 행수·비용합 검증을 그대로 통과했다. 아래를 Supabase에서 실행해 **한 줄이라도 나오면 기록을 되돌리고(해당 키 삭제) 부분 완료 알림**을 보낼 것.

```sql
-- 대상 주 W. 결과가 0행이어야 정상.
select channel, '노출 없음' issue, count(*) n
from sr_weekly_creative_stats
where week_start='W' and (payload->>'비용')::numeric>0
  and (not payload ? '노출 수' or (payload->>'노출 수')::numeric=0)
group by 1
union all
select channel, '클릭>노출(물리적 불가)', count(*)
from sr_weekly_creative_stats
where week_start='W' and payload ? '노출 수'
  and (payload->>'클릭 수')::numeric > (payload->>'노출 수')::numeric
group by 1
union all
select channel, '직전 주 대비 노출 90% 이상 급감', count(*)
from sr_weekly_creative_stats t
where week_start='W' and payload ? '노출 수'
  and (select sum((payload->>'노출 수')::numeric) from sr_weekly_creative_stats p
       where p.channel=t.channel and p.week_start=(date 'W' - 7)) > 0
  and (select sum((payload->>'노출 수')::numeric) from sr_weekly_creative_stats c
       where c.channel=t.channel and c.week_start='W')
      < 0.1 * (select sum((payload->>'노출 수')::numeric) from sr_weekly_creative_stats p
       where p.channel=t.channel and p.week_start=(date 'W' - 7))
group by 1;
```

**(c) 필수 키 보유율** — 채널별로 `비용·클릭 수·노출 수`(메타·몰로코는 `어트리뷰션 수`도)가 **99% 이상의 행에 존재**해야 한다. 미달이면 그 지표 이름을 넣어 부분 완료 알림.

### 4) Slack DM 알림 (본인에게)
- 성공: `[CR] 수퍼셋 최신화 완료! ✅ {M/D}주 · 몰로코 +N행 · 메타 +M행 · 구글그룹 K개 (중복 스킵 S)`
- 이미 최신: `[CR] 이미 최신이에요 ✅ ({M/D}주) — 할 일 없음`
- 실패: `[CR] 수퍼셋 최신화 실패 ❌ — 다시 실행해 주세요: {한 줄 사유}`
- 부분 성공(일부 소스만 기록됨): `[CR] 수퍼셋 최신화 부분 완료 ⚠️ — 성공: {…} / 실패: {…} · 다시 실행하면 빠진 것만 채워져요`
- **지표 누락(3-b/3-c 위반)**: `[CR] 지표 누락 ⚠️ {M/D}주 {채널} {지표명} — 0으로 채우지 않고 키를 비웠어요. 소스 확인 필요: {한 줄 사유}`

> ⚠️ 재적재 주의: 저장이 `on conflict do nothing`이라 **이미 들어간 주는 다시 돌려도 갱신되지 않는다.** 소스를 고친 뒤 값을 채우려면 그 (채널, 주) 행을 지우고 다시 넣어야 한다.
> 예: `delete from sr_weekly_creative_stats where channel='Moloco' and week_start='2026-07-27';`

## 최초 1회 검증(드라이런) — 사람이 직접 붙여넣기

데스크톱 Claude에 아래를 붙여넣어 파이프라인을 검증한다(기록 없음):

> https://raw.githubusercontent.com/hansy-daangn/CreativeReporter/main/docs/WEEKLY_SYNC_TASK.md 를 읽고 **드라이런**으로 수행해줘 — 2)기록 단계는 건너뛰고, 0)·1)·3)의 조회·컬럼검증·합계만 확인한 뒤 결과를 "[CR] 드라이런 결과 …" 포맷으로 Slack DM 보내줘.

드라이런 성공 → 예약 작업 등록(위 전제 참고). 참고: 클라우드 쪽에도 매주 월요일 20:00(KST) 감시가 있어, 그때까지 데이터가 안 들어오면 "[CR] 이번 주 최신화가 아직 안 됐어요 ⏰" 푸시 알림이 자동 발송된다(Routine 세션은 Slack 미보유 — 클라우드 감시는 푸시, 데스크톱 작업은 Slack DM).
