# CreativeReporter 완전제작 프롬프트

> 아무것도 없는 상태에서 이 시스템 전체(사이트 + Supabase 백엔드 + 배포)를 재구축하기 위한 문서.
> 아래 "프롬프트 본문" 전체를 AI 어시스턴트(또는 개발자)에게 그대로 전달하면 된다.
> `docs/ARCHITECTURE.md`와 함께 사용하면 판단 근거까지 완전하다.

**준비물**: ① Supabase 프로젝트 1개(무료 플랜 가능, pgcrypto 확장 사용) ② GitHub 저장소 + Pages 활성화 ③ 레거시/부트스트랩 비밀번호 문자열 ④ 사용자 비번과 분리된 관리자 비밀번호.
**교체할 값**: 아래 본문의 `<SUPABASE_URL>` `<PUBLISHABLE_KEY>` `<PASSWORD>` 를 본인 값으로 바꾼다. (publishable key는 공개되어도 되는 키다. 실제 게이트는 비밀번호다.)

---

## 프롬프트 본문 (여기서부터 복사)

너는 최상급 프론트엔드/데이터 엔지니어다. 아래 명세대로 "퍼포먼스 광고 소재 성과분석 대시보드"를 처음부터 끝까지 만들어라. 결과물은 ① 단일 `index.html` ② 관리자 페이지 `admin.html` ③ Supabase SQL 마이그레이션(계정·승인 포함) ④ GitHub Pages 배포 워크플로우다. 외부 라이브러리·프레임워크·번들러 금지(바닐라 JS/CSS/SVG). 모든 집계·채점·차트는 브라우저에서 계산한다.

### 1. Supabase 백엔드 — 이 SQL을 그대로 적용

```sql
-- 주간 성과 원본
create table weekly_creative_stats (
  id bigint generated always as identity primary key,
  channel text not null,
  week_start date not null,
  ad_name text not null,
  payload jsonb not null default '{}'::jsonb,
  uploaded_by text default 'unknown',
  uploaded_at timestamptz default now(),
  unique (channel, week_start, ad_name)
);
-- 콘솔 조회용 파생 컬럼 (쓰기 경로와 무관)
alter table weekly_creative_stats
  add column cost_krw     numeric generated always as (nullif(payload->>'비용','')::numeric) stored,
  add column impressions  numeric generated always as (nullif(payload->>'노출 수','')::numeric) stored,
  add column clicks       numeric generated always as (nullif(payload->>'클릭 수','')::numeric) stored,
  add column installs     numeric generated always as (nullif(payload->>'어트리뷰션 수','')::numeric) stored,
  add column active_users numeric generated always as (nullif(payload->>'활성 유저 수','')::numeric) stored;

-- 보조 저장소 (이름 매핑·그룹 정보·OCR·유튜브 제목)
create table cr_kv (
  k text primary key,
  v jsonb not null,
  updated_at timestamptz default now(),
  updated_by text default 'unknown'
);

-- 사용자 계정 + 승인 워크플로 (신청함/승인됨/거절됨). 비번은 sha256 해시만 저장.
create table cr_users (
  id bigint generated always as identity primary key,
  daangn_name text not null,
  name_lower  text generated always as (lower(daangn_name)) stored,
  pw_hash     text not null,
  status      text not null default '신청함' check (status in ('신청함','승인됨','거절됨')),
  created_at  timestamptz not null default now(),
  reviewed_at timestamptz, reviewed_by text);
create unique index cr_users_name_uq   on cr_users(name_lower);   -- 대소문자 무관 유일(사칭 방지)
create unique index cr_users_pwhash_uq on cr_users(pw_hash);      -- 비번만으로 로그인 → 전역 유일
-- pgcrypto의 digest는 extensions 스키마 → 항상 extensions.digest(...)로 스키마 명시 호출

-- RLS 전면 차단: 접근은 오직 SECURITY DEFINER RPC로만
alter table weekly_creative_stats enable row level security;
alter table cr_kv enable row level security;
alter table cr_users enable row level security;

-- 권한 컬럼: cr_users.role text default 'viewer' check (role in ('viewer','editor','admin'))
--   admin = 에디터 상위(에디터 권한 포함) + 소재 이름 수동 변경. 현재 admin은 hansy만.
-- 읽기 게이트: 레거시 '<PASSWORD>' 또는 '승인됨' 사용자의 비번이면 통과
create or replace function _cr_check_pw(pw text) returns void
language plpgsql security definer set search_path to 'public' as $$
begin
  if pw = '<PASSWORD>' then return; end if;
  if exists (select 1 from cr_users where status='승인됨'
             and pw_hash = encode(extensions.digest(pw,'sha256'),'hex')) then return; end if;
  raise exception 'invalid password' using errcode = '28000';
end $$;
-- 쓰기 게이트: 승인됨 + role=editor 만 통과 ('<PASSWORD>'·뷰어 거부). cr_save/cr_kv_merge가 perform _cr_check_editor(pw).
create or replace function _cr_check_editor(pw text) returns void
language plpgsql security definer set search_path to 'public' as $$
begin
  if pw = '<PASSWORD>' then raise exception 'viewer cannot edit' using errcode='28000'; end if;
  if exists (select 1 from cr_users where status='승인됨' and role='editor'
             and pw_hash = encode(extensions.digest(pw,'sha256'),'hex')) then return; end if;
  raise exception 'not editor' using errcode='28000';
end $$;

-- 비밀번호 열람/관리: cr_users.pw_enc bytea(pgcrypto pgp_sym로 암호화, 키는 함수 본문). 가입·생성·변경 시 hash와 함께 저장.
--   cr_admin_list가 pgp_sym_decrypt로 복호화해 pw 반환(관리자만). cr_admin_create(이름·비번·권한→승인됨 생성)·cr_admin_setpw(hash·enc 동시 갱신).
-- 관리자 게이트(_cr_check_admin, 별도 시크릿) + cr_register/cr_login/cr_admin_list/cr_admin_set.
-- 비번 규칙 _cr_pwok(p): length(p) >= 4 (복잡도 없음). register·admin_create·setpw 공통. 중복은 pw_taken, 예약 0715 별도 거부.
-- cr_pending_count(pw): perform _cr_check_pw(pw) 후 신청함 수 반환(admin.html 알림용).
-- cr_admin_set에 p_name(이름 변경) 추가. 관리자 로그인 계정 admin/7132(editor) 시드(정책 우회 직접 insert).
-- 즐겨찾기/내 소재: cr_user_marks(user_name,channel,ad_name,kind in (fav,mine), unique 4개조). RLS deny-all.
--   _cr_uname(pw): 승인 계정 비번→이름(0715/미존재 null). cr_mark_set(pw,ch,ad,kind,on): 도출 이름으로 upsert/delete(0715 거부).
--   cr_marks_load(pw): mine 전체(등록자 이름 n 포함, 공개) + fav 본인 것만. anon grant.
--   cr_mark_set_many(pw,p_channel,p_ads jsonb,p_kind,p_on): 그룹 일괄 토글 — ad 배열을 한 번에 upsert(ON CONFLICT DO NOTHING)/delete. anon grant.
-- 소재 이름 수동 변경(관리자 전용):
--   _cr_is_admin(pw) boolean: 승인됨 + role=admin + 비번 해시 일치.
--   cr_names_merge(pw,p_map jsonb): _cr_is_admin 아니면 예외. kv 'nameovr'에 얕은 병합(값 ''/null=키 삭제). 키는 클라이언트가 매체+원본명으로 생성. anon grant. 읽기는 cr_kv_get(pw,'nameovr').
--   cr_svc_merge(pw,p_map jsonb): 동일 게이트/형식으로 kv 'svcovr'(서비스 분류 오버라이드) 병합. 읽기 cr_kv_get(pw,'svcovr').
--   cr_admin_mark_set(pw,p_channel,p_ad,p_user,p_kind default 'mine',p_on default true): _cr_is_admin 게이트. 특정인 p_user 이름으로 cr_user_marks 행 upsert/delete → 관리자가 제작자(내 소재) 칩을 대신 붙이거나 뗀다.
-- cr_admin_set: p_role 허용값에 'admin' 추가. **이름(p_name) 변경 시 옛 이름을 쓰는 cr_user_marks.user_name·weekly_creative_stats.uploaded_by까지 새 이름으로 UPDATE**(본 페이지 닉네임·본인 마크 매칭 유지).
-- cr_register: 이름 ^[A-Za-z][A-Za-z0-9]{1,23}$·_cr_pwok 통과·예약비번 '<PASSWORD>' 금지·이름/해시 중복 거부(같은 비번 계정 금지) → 신청함·viewer.
-- cr_login(p_pw): '<PASSWORD>'=이름없는 뷰어 {found,viewer:true,role:viewer,status:승인됨}. 그 외는 해시 조회 → {found,name,status,role,viewer:false}.
-- cr_admin_list(admin_pw): 신청함 먼저·role 포함. cr_admin_set(admin_pw,p_id,p_status default null,reviewer,p_role default null): status·role 각각 nullable(하나만 변경 가능).
-- 시드 없음('<PASSWORD>'가 하드코딩 뷰어). 소유자는 가입 후 admin.html에서 자신을 editor로 승인. RPC는 anon,authenticated에 grant execute.
-- 관리자 비번은 admin.html에 넣지 말 것(공개 파일) — 런타임 입력만.

-- 전체 로드 (단일 jsonb — PostgREST 1,000행 제한 우회)
create or replace function cr_load(pw text) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare res jsonb;
begin
  perform _cr_check_pw(pw);
  select coalesce(jsonb_agg(
    jsonb_build_object('channel',w.channel,'week_start',w.week_start,'ad_name',w.ad_name,'payload',w.payload)
    order by w.week_start, w.channel, w.ad_name),'[]'::jsonb)
  into res from weekly_creative_stats w;
  return res;
end $$;

-- 벌크 저장: 채널 공백/'기타' 거부, 이름 필수, 비용 1500 미만 거부, 중복 무시, 업로더 기록
create or replace function cr_save(pw text, rows jsonb, uploader text default 'unknown') returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare n_inserted int; up text;
begin
  perform _cr_check_pw(pw);
  up := coalesce(nullif(trim(uploader),''),'unknown');
  if length(up) > 40 then up := left(up,40); end if;
  with ins as (
    insert into weekly_creative_stats (channel, week_start, ad_name, payload, uploaded_by)
    select r->>'channel', (r->>'week_start')::date, r->>'ad_name', coalesce(r->'payload','{}'::jsonb), up
    from jsonb_array_elements(rows) r
    where coalesce(r->>'channel','') not in ('','기타')
      and coalesce(r->>'ad_name','') <> ''
      and (r->>'week_start') is not null
      and coalesce((r->'payload'->>'비용')::numeric, 0) >= 1500
    on conflict (channel, week_start, ad_name) do nothing
    returning 1
  )
  select count(*) into n_inserted from ins;
  return jsonb_build_object('inserted', n_inserted, 'total', jsonb_array_length(rows));
end $$;

-- 상태 요약 (업로더 감사 포함)
create or replace function cr_status(pw text) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare res jsonb;
begin
  perform _cr_check_pw(pw);
  select jsonb_build_object(
    'rows', count(*), 'ads', count(distinct ad_name), 'weeks', count(distinct week_start),
    'channels', coalesce(jsonb_agg(distinct channel),'[]'::jsonb),
    'first_week', min(week_start), 'last_week', max(week_start),
    'unsigned_rows', count(*) filter (where uploaded_by is null or uploaded_by in ('','unknown')),
    'uploaders', (select coalesce(jsonb_object_agg(u, c), '{}'::jsonb)
                  from (select uploaded_by u, count(*) c from weekly_creative_stats group by 1) t),
    'last_upload', max(uploaded_at))
  into res from weekly_creative_stats;
  return res;
end $$;

-- 보조 저장소 get / merge(최상위 키별 얕은 병합 + 갱신자 기록)
create or replace function cr_kv_get(pw text, key text) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare res jsonb;
begin
  perform _cr_check_pw(pw);
  select v into res from cr_kv where k = key;
  return coalesce(res, 'null'::jsonb);
end $$;

create or replace function cr_kv_merge(pw text, key text, val jsonb, uploader text default 'unknown') returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare cur jsonb; merged jsonb; topk text;
begin
  perform _cr_check_pw(pw);
  select v into cur from cr_kv where k = key;
  if cur is null then merged := val;
  else
    merged := cur;
    for topk in select jsonb_object_keys(val) loop
      if jsonb_typeof(cur->topk)='object' and jsonb_typeof(val->topk)='object' then
        merged := jsonb_set(merged, array[topk], (cur->topk) || (val->topk));
      else
        merged := jsonb_set(merged, array[topk], val->topk);
      end if;
    end loop;
  end if;
  insert into cr_kv(k, v, updated_at, updated_by) values(key, merged, now(), coalesce(nullif(uploader,''),'unknown'))
  on conflict (k) do update set v = excluded.v, updated_at = now(), updated_by = excluded.updated_by;
  return merged;
end $$;
```

### 2. 클라이언트 상수

```js
const SB_URL = "<SUPABASE_URL>";                 // 예: https://xxxx.supabase.co
const SB_KEY = "<PUBLISHABLE_KEY>";              // anon/publishable key (공개 가능)
// RPC 호출: fetch(`${SB_URL}/rest/v1/rpc/${fn}`, {method:"POST", headers:{apikey:SB_KEY,"content-type":"application/json"}, body:JSON.stringify(body)})
```

### 3. 지원 파일과 인식 규칙 (드래그&드롭, 복수 파일)

분류 순서와 판별 조건:
1. **구글 확장 소재 연결 보고서**: 헤더 줄에 `애셋 상태`와 `확장 소재` 포함(제목 2줄 뒤). 컬럼 매핑 — `주`→date(월요일 시작), `확장 소재`→ad_name(URL), `비용/노출수/클릭수/설치/인앱 액션/조회연결 전환/상호작용 수/TrueView 조회수/전환수/항목 ID/광고그룹 ID/캠페인 ID/모든 전환(전환 시간별)/모든 전환 가치(전환 시간별)` → 내부 키(`비용, 노출 수, 클릭 수, 어트리뷰션 수, 활성 유저 수, 신규+재활성 유저 수, _g_interactions, _g_trueViews, _g_conversions, _g_assetId, _g_adGroupId, _g_campaignId, _g_allConv, _g_convValue`) + `애셋 상태/애셋 유형/상태/수준`→`_g_assetStatus/_g_assetType/_g_status/_g_level`, URL→`_g_url`.
2. **몰로코 크리에이티브 리포트**: `creative_preview` 있거나 `ad_name`+`creative_type`. `creative_preview`의 href/URL→`_m_url`, `creative_type`→`_m_ctype`, `resolution`→`_m_res`, `creative_group_name`→`_m_group`(레벨이 아니라 소재의 속성으로 취급, 분석은 소재 단위), `영상 완주율`>0이면 `_vcrNum=완주율×노출 / _vcrDen=노출`. **네이티브 영상 오등록 보정**(집계 시): 완주율이 존재하는 데이터에서 ctype VIDEO인데 첨부가 이미지 파일(.png/.jpg/.gif/.webp)이고 완주율이 전 기간 없으면 이미지로 재분류(`_foFix` 마크, 칩 `이미지*`+사유 툴팁, 유형 표기 '이미지(영상 등록)' 🖼️). 완주율이 찍혀 있으면 미리보기만 썸네일인 진짜 영상이라 유지, 리포트에 완주율 컬럼이 아예 없으면 판단 보류.
3. **일반 성과 CSV(메타 등)**: `date`+`ad_name`(+지표들). `thumbnail_url/image_url/creative_preview/미리보기/썸네일` 컬럼이 있으면 `_m_url`로 연결. `동영상|video` 포함 + `25/50/75/95/100%` 재생수 컬럼(율·평균·시간·비용류 헤더 제외)이 있으면 `_v25~_v100`으로 자동 인식·주간 합산 — 상세 '영상 시청' 탭 곡선 데이터, 저장 payload에도 포함.
4. **광고그룹 보고서**: 헤더에 `광고그룹 상태`+`광고그룹 ID`. 그룹별 {이름, 캠페인(ID·이름), 상태·상태 이유, 타겟 CPA, 비용·노출수·클릭수·CTR·상호작용 발생률·참여율, 동영상 25/50/75/100% 재생, 평균 시청 시간/노출수, 전환수·전환율·전환당비용, first_open, home, 보고 기간} → kv `ginfo`(광고그룹 ID 키), 이름들 → kv `gmap.adgroup/campaign`. '전체:' 요약 줄 제외.
5. **이름 매핑 CSV**: (`광고그룹 ID`+`광고그룹`) / (`캠페인 ID`+`캠페인`) / (`항목 ID`|`애셋 ID`+`애셋`|`애셋 이름`) 쌍. 제목 줄 프리앰블 허용.

**매체 판별 우선순위**: 형식 자동 감지 → 미리보기 URL 도메인(adsmoloco→Moloco, googlesyndication|youtube→Google, fbcdn→Meta) → 드롭 위치(화면 하단 3분할) → 파일명 접두(meta_/moloco_/google_). 판별 실패·주간 아님(일간/월간/기간합산)·유효 행 0 → **임시 분석 모드**(상단 배너, 저장 안 함, 복귀 버튼).

**저장·병합 규칙**: (주차,소재) 병합 그레인 합산 광고비 ₩1,500 미만 제외(분석·저장 모두). 뷰 누적은 기존 (주차,소재) 유지·신규만 추가. 저장은 800행 청크로 cr_save. **확인창**: 광고그룹 보고서·이름 매핑이 기존 저장값과 달라지는 항목을 포함하면 변경 예시와 함께 confirm(확인=ID 기준 갱신/취소=미반영), 신규뿐이면 무확인 반영. 파일 input은 처리 후 value 초기화(같은 파일 재드롭 허용).

### 4. 채점 명세 (정확히 이 공식)

```
원점수 = 100 × (0.75·E + 0.20·R + 0.05·C)
E: 지표별 g′의 가중평균. g = 해당 지표의 광고비 가중 백분위(모수: 값 보유 전체 소재, 가중치 max(비용,1))
   g′ = 0.5 + (g − 0.5)·n/(n+n₀). n = 지표 표본(전환류=전환수, 클릭류=클릭수, 노출류=노출수), n₀ = 50/100/2000
   방향: 비용류(-1)는 1−백분위. CTR·CPM·CPC·완주율·상호작용률류는 같은 포맷(영상/이미지) 코호트 ≥8개일 때 코호트 분포로.
R: 노출 수의 단순 백분위. C: min(1, ln(1+전환)/ln(1+30)).
가중치 — ad: eCPI .26, 활성 eCPA .20, CTR .16, 신규 eCPA .12, CPM .10, 완주율 .08(영상만), CPC .08
       google(_g_assetType 존재 시): ROAS .35, 전환당 비용 .20, 전환율 .15, CTR .15, CPM .15
       adset: 활성 eCPA .35, eCPI .25, CTR .20, CPM .15, CPC .05 · cg: CTR .50, CPC .30, CPM .20
지표 결측 시 가중치 재정규화. 가용도(값 보유 비율) 10% 미만 지표는 스펙·표에서 제외.
파생 규칙: 분모가 있으면 0도 유효값 (예: ROAS = 비용>0 ? (전환가치||0)/비용 : null. 전환당 비용은 전환 0이면 null).
eligibility: 비용 ≥ 15퍼센타일 && 가중 .15 이상 핵심 지표 모두 보유. 탈락 시 점수 '–'.
표시 점수: elig ≥ 8이면 원점수를 선형 재배치 — lin(v) = 12 + (v−q05)/(q95−q05)×80 (q05·q95 = elig 원점수 분위),
  양 끝 점근 압축 soft(v) = v>92 ? 92+(v−92)·7/((v−92)+7) : v<12 ? 12−(12−v)·10/((12−v)+10) : v,
  최종 = round(clamp(soft(lin(v)), 2, 99.4)×10)/10 (소수점 1자리, 순위 보존). elig < 8이면 원점수 그대로.
표시: 모든 점수는 소수점 1자리(fmtScore). 상세 '점수 구성'은 재배치 점수와 지표별 백분위 막대만 — 원점수·가중치·계산식 노출 금지(산정 방식은 푸터로). 전체 목록 점수 칸은 십의 자리별 10단계 색(sd0~sd9). 무점수(score null) 소재는 기본 숨김('비활성·점수없음도 보기' 체크로 표시, 채점 없는 소규모 데이터셋은 예외).
tier: 적격자 점수 5분위(g2/g1/m/w1/w2) + dom '독보적'(1위가 2위와 압도적 격차 && 비용 ≥ 중앙값).
학습중 배지: 비용>0 && (집행 주 <2 || 전환 <30).
그룹 집계 행도 동일 스펙으로 채점.
```

### 5. 표시 이름 우선순위

`displayNameOf`: **관리자 수동 이름(kv `nameovr`, 편집 중이면 미저장분 우선, ''=기본명 복원) — 최상위** → 그룹 행 `_` 분절형(`중고거래·shortform·2601`, maugrowth 생략, 그 앞 접두만 유지, 서비스 사전: fleamarket|중고|declutter→중고거래 · realty|rentkarrot|lifedaangn→부동산 · jobs|알바→알바 · localbiz|동네→동네업체 · branding→브랜딩) → `gmap.asset[항목ID]`(공식) → `ocr[항목ID]`(OCR 마크 부착) → `ytt[유튜브ID]` → 원문. 내부 키·저장·정렬은 항상 원문. 수동 이름 키 = `markKey(매체, 원문명)`. 유튜브 제목은 로드 1.2초 후 전 소재 자동 조회(noembed.com, 동시 4, localStorage+kv `ytt` 공유).

### 6. UI 명세

- 좌측 다크 사이드바(248px): 매체 세그(소재 수 많은 순, 기간 반영 카운트) / 기간(최근 1달=4주·최근 3달=13주·전체·직접 설정 "최근 [N][주|달]", 달≈4.345주) / 요약 KPI(총 광고비·설치·eCPI·활성·eCPA + 지난주 증감) / ☁️ 저장소 줄("소재 N개 · 주간 기록 M건 · W주 · 클릭=새로고침", 툴팁에 업로더 분포) / 용어·CSV 버튼. ≤900px: 매체·기간 2분할, 나머지는 '요약' 토글(기본 접힘), 표의 소재 이름 숨김(미리보기만).
- 본문: 세그먼트 탭(분석/전체 목록/AB테스트 — AB 그룹 0개면 탭 숨김), 카드 없이 흰 배경 풀폭, sticky 탭, 푸터는 캔버스색+64px 간격.
- 분석: 요약 타일 3개, 효율 지도(축 선택 산점도+범위 슬라이더, 상위 광고비 라벨 · '보기' 세그먼트: 소재(기본)/포맷/사이즈/형태/지면/서비스 — 유형 선택 시 typeAggRows(상하 10% 트림 합산)로 유형당 1점 집계·전 지점 라벨·클릭 없음·툴팁에 포함 소재 수, 값 2개 이상인 차원만 노출. 보기/가로/세로 모두 세그먼트 컨트롤), 주차별 추세(선택 기간 전체, 라벨 ≤13 자동 솎기, 광고비 면적+효율선 이중축). 별도 '유형별 비교' 그래프는 없음(지도에 흡수).
- 전체 목록: 컬럼 계층 — 대표(점수|노출|eCPI|eCPA|CTR|완주율|ROAS)만 기본, 헤더 `+`로 그룹 세부(노출→광고비·CPM / eCPI→설치·설치(몰로코) / eCPA→활성·신규+재활성·신규 eCPA / CTR→클릭·CPC / ROAS→전환류 전체) 펼침, 정렬과 독립. 필터: Live(기본 ON, 스코프 최신 집행 주 비용>0, 그룹은 멤버 기준) · GroupView(광고그룹 집계, Video/Image와 상호 배타) · Video/Image · 이름 아래 칩 클릭 필터(서비스·포맷·사이즈·네이티브·그룹, 그룹 행은 접두·날짜·수식어 칩, ✕ 배지 해제). 60행 페이지네이션. 셀은 컬럼 분포 5분위 색상. 매체 전환 시 페이지 1로 리셋.
- 이름 옆 뱃지: `Live`(초록 점, 최신 집행 주 광고비>0 — 그룹은 멤버 기준, 전 매체) · `경고`(구글 ginfo 정책 제한만, 사유 툴팁) · `학습중`(2주 미만 or 전환 30건 미만). 운영중·일시중지는 뱃지 없음(일시중지는 그룹 상세 메타 텍스트로만).
- 상세(행 클릭 아코디언): 구조 = `.isle-row3` 단일 grid(areas "media mid cmp"): [ir-media(프레임+원본링크, 열폭 ar-v 232/ar-s 280/ar-h 400px, ≤1200에서 260/320) | ir-mid(그래프 탭) | ir-cmp(같은 그룹/시리즈 비교, minmax(0,1.25fr))]. ir-mid는 세그먼트 탭(.dtog) 3종 — **주차별 추이**(ispark, 폭·높이 캡 없이 컬럼 폭 비례 스케일. 매 막대 아래 2줄 라벨: MM/DD + 그 주 점수 — weeklyScoresOf(ds,e): 주별 rows→aggregate→computeScores(그룹 상세는 buildAdGroupAgg까지)로 재채점, ds._wkScore/_wkScoreG에 캐시(scope()가 무효화), 티어 색 표기·부적격 주는 '–', 툴팁에도 점수) / **영상 시청**(영상 소재만): 구간별 시청 유지 곡선([노출 100]→_v25~_v100÷노출, 없으면 ginfo v25~v100 그룹 퍼널을 캡션에 '그룹 단위' 명시, 둘 다 없으면 완주율 큰 값+영상 코호트 중앙값 대비) + 완주율|TrueView 조회율 주차별 선(영상 중앙값 점선), 최대 이탈 구간 음영+−%p 라벨 / **포지셔닝**: 백분위 사분면 산점도 — 두 축 모두 계정 내 위치(광고비 가중 백분위 wPctRank, dir<0은 1−r, 0~100·표본 축소 없음), 축 지표는 가로/세로 .dtog 토글(quadMetricsFor 중 본인 값 보유+비교군 ≥6, 기본 가로 CTR류·세로 효율류, 같은 지표 선택 시 축 맞바꿈, ISLE.posX/posY 유지). 중앙(50) 십자선은 userSpaceOnUse 그라데이션(빨강 .75→#D8D6CC→초록 .85, 가로=왼→오·세로=아래→위)으로 나쁨→좋음 방향을 표시하고 선 끝 밖에 +(초록)/−(빨강) 글리프(pad 16) — 사분면 틴트·코너 문구 없음, 광고비 상위 140+본인·같은 그룹 항상 포함, 회색=타 소재·파랑=같은 그룹·주황=이 소재+링+'이 소재' 라벨, 점 크기=광고비, 점 클릭→해당 소재 상세, 헤더·툴팁에 '상위 N%'(=100−백분위) + '지표별 계정 내 위치' .sb 막대. 있는 데이터의 탭만(1개면 탭 줄 숨김), 선택 탭 ISLE.gtab로 소재 이동 간 유지. 점수·진단·구분선·내비 버튼 없음. 비교 목록: table-layout:fixed(수치 열 90/82/62px)+한 줄 ellipsis, prefixTrimmer(공통 접두 토큰 경계(≥10자)에서 '…' 접기, tr title=풀네임). 모바일(≤860): areas "media"/"cmp"/"mid" 1열(중요도 순), 프레임 max-width 320(가로 420)px 중앙. 이미지 실패·비율 판정(isleAr)·키보드 ←/→·Esc·딥링크 해시는 유지. 그룹 상세: 미디어 자리=보고서 추가 정보(퍼널 제외), 그래프 탭 동일(포지셔닝 비교군=그룹 집계 행들).
- AB테스트: 접미 변형 자동 인식 — 확장자·해상도(1080x1920)·화면비(16x9) 제거 후, 문자 변형(구분자+[Vv|ver|시안]?+A~F, 어간 영숫자≥4 또는 한글≥2), 숫자 변형 1~5만(v접두/제로패딩 01~05/회차 ep·part·pt·편·화·회차+숫자/문자 직결 숫자, 맨숫자 "_2"는 제외, 숫자 계열은 변형 '1' 필수). 목록(이름+🥇🥈🥉 미니 썸네일)→펼침: 변형=열 비교표, 스프레드 ≥5% 지표만 최고 초록·최저 빨강, 대표(최고 점수) 미디어 크게, '대표 소재 상세' 버튼.
- 랜딩(로그인/가입) — Apple 미니멀·프리미엄, 성격별 그룹, Pretendard 폰트·굵기 위계: 제목 **당근 소재분석툴**(800) · 인증 그룹(라운드렉트 비밀번호 필드[좌측 입력+우측 검은 화살표, 클릭·Enter 로그인]+회원가입 텍스트링크) · 외부도구 그룹(Google Ads·SuperSet 로고 칩 2개 나란히, 인라인 SVG 재현) · 맨 아래 `</> Dev`(→ admin.html). 지시문·힌트 없음. 로그인=`cr_login` 분기: 0715 뷰어="뷰어 권한으로 로그인했어요"(이름 없음, canEdit=false) / 에디터="NAME님 환영해요! 🥕"(canEdit=true) / 승인된 뷰어="NAME님 환영해요! · 지금은 뷰어 권한이에요" / 신청함·거절됨·미존재 각 안내·흔들기. 회원가입=뷰 전환(daangn name·비번·비번확인·가입하기·← 로그인), name 영문·숫자만, 검증 후 `cr_register`→"가입 신청을 받았어요 · 관리자 승인 후 이용할 수 있어요". 승인 사용자 이름은 crname·cr_uploader에 저장(수정 서명), 에디터 여부는 crcan에 저장(canEdit). **저장·수정 경로(cloudSaveAll·kv merge·ytt)는 canEdit 게이트** — 뷰어는 드롭 분석만 되고 저장은 건너뜀(토스트 안내).
- 관리자 페이지 `admin.html`: 별도 자기완결 파일(공개 URL, 로그인 `</> Dev`로도 진입). 관리자 비번 게이트(런타임 입력, 파일 비저장) → 표(신청함 먼저·상태·**권한 뷰어/에디터/관리자 3토글**·**비밀번호 열람**·신청일·처리자). 행별 승인/거절(**확인창 없이 즉시**)/대기(`cr_admin_set` p_status)+권한(p_role: viewer/editor/admin)+**이름 ✎수정**(p_name, 변경 시 마크·업로드 서명까지 서버에서 연쇄 갱신)+**비번변경**(`cr_admin_setpw`). 상단 **＋계정 추가**(`cr_admin_create`, 승인됨 생성). 비번 열은 평소 ●●●, **호버 시 표시**(pw_enc 복호화값, 클릭 복사) — 암호화 전 가입자는 `—`. 처리 열은 날짜만(처리자 미표기). 거절은 상태 보존(재승인 가능). **열려 있는 동안 15초 폴링** → 새 신청 시 토스트+브라우저 알림(unlock 시 Notification 권한 요청). 가입 알림은 **관리자 페이지 전용**(메인 화면엔 없음).
- **즐겨찾기 / 내 소재**(로그인 계정, 뷰어 포함·0715 제외, cr_marks_load 후): 소재 이름 우측 별 2종 — ★즐겨찾기(켜면 노랑) · 체크 인장 내 소재(켜면 하늘색), 스트로크 없음, 이름 셀 안 인라인. **켜진 별(.on)은 호버 없이 상시 노출**, 안 켜진 별은 호버 시에만 회색. **즐겨찾기는 별만**(칩·"즐겨찾기" 글자 없음) · **내 소재는 남이 등록한 것만 이름 칩**(본인 것은 켜진 별로 충분 → 칩 생략). 별은 전체 목록·**그룹 행**·상세 **"같은 그룹 내 비교" 목록**(`.cmp-mark`)에 모두. 좌측 nav "보기" 세그먼트(전체/내 소재/즐겨찾기). 개별 토글=cr_mark_set 낙관적. **그룹 마크**: 그룹 별=멤버 전원 일괄 토글(`cr_mark_set_many`), 상태는 저장 않고 멤버에서 파생(전원 표시=그룹 표시, 개별 해제 시 그룹도 자동 해제). 토글 후 표·비교목록은 전체 재렌더 없이 제자리 갱신(refreshMarksUI)해 열린 상세 유지.
- **제작자 로스터**: CREATORS=`["vin","mia","tank","hansy","marin","jace"]` 고정. 제작자 칩·필터는 항상 이 로스터에서만(직접 입력 금지). rosterCreatorsOf(e)=mineCreatorsOf∩로스터. 기존 admin 등록분은 SQL로 hansy 이관.
- **소재 편집(관리자 연필 팝오버)**: 별 오른쪽에 연필(`.mark-btn.edit`, 관리자·개별 소재만). 클릭 → body에 붙는 팝오버(anchor 아래)로 **이름·서비스·제작자** 편집. 제작자는 로스터 토글칩(복수, 텍스트 입력 없음). 저장: 이름→cr_names_merge(NAME_OVR), 서비스→cr_svc_merge(SVC_OVR, ''=자동), 제작자 로스터 diff→cr_admin_mark_set(특정인 mine). 저장 후 renderInlineRefresh(재렌더+열린 상세 재개+필터 개수 갱신). 바깥클릭·Esc 닫기.
- **자료 추출(사이드바 `내 자료 추출하기`, CSV 버튼은 아이콘화)**: 중앙 플로팅 모달 — 제작자(모두+로스터, 단일) · 매체(모두+채널, 복수 · 모두=전체) · 기간(1달/3달/전체/직접) · 비교 데이터 포함(체크박스, 제작자=모두면 비활성). 추출: adDs 복제→tmp.media=채널·periodN=선택기간→scope(tmp)로 매체별 재채점, curDS=tmp로 잠시 바꿔 displayNameOf/svcOf/rosterCreatorsOf가 채널 정확하게, 매체별 A(대상)·B(비교군) 섹션 Markdown 생성 → downloadText(Blob .md). 각 소재는 자기 행에만(혼용 금지), 매체 다르면 점수 비교 금지 명시. 끝나면 periodN·curDS 복원 + show(active).
- **소재 이름 일괄 변경(관리자 `/namechange`)**: 검색창 `/namechange`+엔터→모든 소재명 contenteditable, 다시 `/namechange`로 저장(cr_names_merge). 저장 전 이탈은 beforeunload. (연필이 개별 편집 주 경로)
- **서비스 분류**: svcOf = SVC_OVR(관리자 수동 지정) 우선 → 이름·ve태그·그룹명 키워드 6버킷(중고거래/브랜딩(브랜딩·보검)/부동산/알바/비즈니스(로컬애즈·비즈)/페이(픽업·래플)) → 기타(null). 오버라이드 시 행에 주황 서비스 칩 표시.
- **서비스·제작자 복수선택 드롭다운**(툴바): 커스텀 msel(체크박스, 선택 토글 시 팝업 유지 — 옵션 목록 시그니처가 바뀔 때만 재구성). 서비스=svcOf 버킷별 개수+기타. 제작자=로스터 6+기타(항상 노출, 기타=로스터 제작자 없는 소재). applyTFilter에서 tServices/tCreators(Set) 교집합 필터(제작자는 rosterCreatorsOf 기준, 기타=로스터 없음).
- **닉네임 반영**: 자동 재접속(restore) 시 cr_login으로 최신 이름·권한 재조회 → uploaderId·crname·crrole·isAdmin 갱신(관리자가 admin에서 daangn name/권한 바꿔도 새로고침으로 본 페이지에 반영). OCR 마크는 상세 애셋 URL 왼쪽, Live는 초록 점+글자 칩.
- 모든 사용자 대면 문구(토스트·인사·안내)는 **당근 보이스**(친근한 해요체). 공통: 자동 재접속 시 "저장소 불러오는 중" 미니멀 로딩, `/아이디`+Enter 서명·`/logout` 해제(레거시, 로그인 서명과 병존), 토스트, 용어 사전, 점수 방법론 푸터.

### 7. 배포 — .github/workflows/pages.yml

main 푸시 시 Pages 배포. `actions/upload-pages-artifact` + `actions/deploy-pages`. **배포 스텝은 `continue-on-error` + 실패 시 90초 대기 후 2차, 다시 실패 시 5분 대기 후 3차 재시도** (GitHub Pages의 간헐적 "Deployment failed, try again later" 대응).

### 8. 오프라인 이름 보강 배치 (선택, 별도 환경에서)

- PaddleOCR(lang="korean", paddlepaddle 2.6.x + paddleocr 2.8.x)로 구글 이미지 애셋 텍스트 추출 → kv `ocr`. 필수 설정: `OMP_THREAD_LIMIT=1`, 이미지 1100px 그레이 리사이즈, 숫자 포함 라인은 conf 0.55까지 수용, 박스 좌표로 위→아래·좌→우 정렬, 후처리(허용문자 정제, 선두 단독 '당근'·로고 오인 접두 제거, 48자 컷).
- dHash(9×8, 해밍 ≤6, 종횡비 ±12%)로 몰로코 IMAGE 소재와 동일 이미지 매칭 → 몰로코 실명을 `gmap.asset`에.

### 9. 완성 검증 체크리스트

로그인(카운트 문구) / 3매체 CSV 드롭 누적·중복 0 / 월간 파일 임시 분석 배너 / 기간 전환 시 카운트·추세 갱신 / Live·GroupView·칩 필터 / 상세 코호트·점수 구성 / AB 인식(오인 케이스: name_2 미인식, kkak01=1) / 광고그룹 보고서 확인창(변경 시에만) / 새로고침 무깜빡임 / 모바일(2분할·요약 접힘·이름 숨김) / 페이지 콘솔 에러 0.

## 프롬프트 본문 끝
