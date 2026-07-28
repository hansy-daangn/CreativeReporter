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

## 수행 절차

### 0) 사전 점검
- 오늘 날짜(Asia/Seoul) 기준 **대상 주 시작일 W** = 직전 완결 주의 월요일(오늘이 월요일이면 7일 전).
- 사내 MCP(superset/bigquery) 도구가 응답하는지 가벼운 호출로 확인. 응답 없으면 → 실패 알림("회사 네트워크 아님 또는 Okta 만료") 후 종료.
- **멱등 체크**: Supabase(project `newoydegfbnnqujgiips`)에서
  `select channel,count(*) from sr_weekly_creative_stats where week_start='W' and channel in ('Moloco','Meta') group by channel;`
  와 `select count(*) from sr_kv, jsonb_each(v) g where k='gwstat' and g.value ? 'W';`
  — 셋 다 이미 있으면 "[CR] 이미 최신이에요 ✅ (W주)" DM 후 종료.

### 1) 데이터 조회 (Superset 대시보드 2075의 세 차트, 대상 주만)
- 차트: **[MAU Marketing] 몰로코 크리에이티브별 성과 + 소재 미리보기** / **[MAU Marketing] 메타 광고소재별 성과 V2** / **[MAU Marketing] 구글 광고그룹별 성과 V2**
- 1순위: superset MCP로 각 차트의 데이터를 주(week)=W 필터로 조회.
- 2순위(차트 데이터 조회가 안 되면): superset MCP로 각 차트의 SQL을 얻어 bigquery MCP `execute_sql`로 W 조건을 걸어 실행.
- 컬럼은 수동 CSV와 동일해야 한다(몰로코: `date,ad_name,creative_type,creative_preview,…지표`, 메타: `date,ad_name,…어트리뷰션/활성/신규+재활성 지표`, 구글: `date,adset_name,비용,노출 수,CPM,클릭 수,CPC,어트리뷰션 수,eCPI,활성 유저 수,활성 유저 eCPA,신규+재활성 유저 수,신규+재활성 유저 eCPA`). 다르면 중단·실패 알림(컬럼 목록 포함).

### 2) 기록 (Supabase MCP)
- **몰로코/메타** → `sr_weekly_creative_stats`에 행 단위 INSERT. 규칙(서버 cr_save와 동일):
  - `channel`='Moloco'|'Meta', `week_start`=W(각 행의 date를 주 시작 월요일로 정규화), `ad_name`=소재 식별자, `payload`=그 행의 모든 지표를 JSONB로(수동 CSV의 컬럼명 그대로 키로), `uploaded_by`='auto-weekly'
  - `on conflict (channel, week_start, ad_name) do nothing` · `(payload->>'비용')::numeric >= 1500`인 행만
- **구글 광고그룹** → `sr_kv` `k='gwstat'` 병합:
  - `adset_name`→광고그룹 ID: `sr_kv k='gmap'`의 `v->'adgroup'`(ID→이름)을 역변환. 매칭 실패는 `name:<이름>` 키로.
  - 값 `{ID:{"W":[비용,노출,클릭,어트리뷰션,활성,신규재활성]}}` — 비용 1500 미만 행 제외.
  - 병합은 그룹 키 안에서 주 키만 추가/덮어쓰기: `v = v || jsonb_set(...)` 방식으로 **다른 그룹·다른 주를 보존**할 것.

### 3) 검증
- 기록 후 재조회해 대상 주의 (몰로코 행수·비용합), (메타 행수·비용합), (gwstat 그룹수·비용합)이 1)에서 조회한 원본 합계와 일치(±1원, 1500 미만 제외분 감안)하는지 확인.

### 4) Slack DM 알림 (본인에게)
- 성공: `[CR] 수퍼셋 최신화 완료! ✅ {M/D}주 · 몰로코 +N행 · 메타 +M행 · 구글그룹 K개 (중복 스킵 S)`
- 이미 최신: `[CR] 이미 최신이에요 ✅ ({M/D}주) — 할 일 없음`
- 실패: `[CR] 수퍼셋 최신화 실패 ❌ — 다시 실행해 주세요: {한 줄 사유}`
- 부분 성공(일부 소스만 기록됨): `[CR] 수퍼셋 최신화 부분 완료 ⚠️ — 성공: {…} / 실패: {…} · 다시 실행하면 빠진 것만 채워져요`

## 최초 1회 검증(드라이런) — 사람이 직접 붙여넣기

데스크톱 Claude에 아래를 붙여넣어 파이프라인을 검증한다(기록 없음):

> https://raw.githubusercontent.com/hansy-daangn/CreativeReporter/main/docs/WEEKLY_SYNC_TASK.md 를 읽고 **드라이런**으로 수행해줘 — 2)기록 단계는 건너뛰고, 0)·1)·3)의 조회·컬럼검증·합계만 확인한 뒤 결과를 "[CR] 드라이런 결과 …" 포맷으로 Slack DM 보내줘.

드라이런 성공 → 예약 작업 등록(위 전제 참고). 참고: 클라우드 쪽에도 매주 월요일 20:00(KST) 감시가 있어, 그때까지 데이터가 안 들어오면 "[CR] 이번 주 최신화가 아직 안 됐어요 ⏰" DM이 자동 발송된다.
