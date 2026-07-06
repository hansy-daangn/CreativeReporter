# CreativeReporter 완전제작 프롬프트

> 아무것도 없는 상태에서 이 시스템 전체(사이트 + Supabase 백엔드 + 배포)를 재구축하기 위한 문서.
> 아래 "프롬프트 본문" 전체를 AI 어시스턴트(또는 개발자)에게 그대로 전달하면 된다.
> `docs/ARCHITECTURE.md`와 함께 사용하면 판단 근거까지 완전하다.

**준비물**: ① Supabase 프로젝트 1개(무료 플랜 가능) ② GitHub 저장소 + Pages 활성화 ③ 비밀번호로 쓸 문자열.
**교체할 값**: 아래 본문의 `<SUPABASE_URL>` `<PUBLISHABLE_KEY>` `<PASSWORD>` 를 본인 값으로 바꾼다. (publishable key는 공개되어도 되는 키다. 실제 게이트는 비밀번호다.)

---

## 프롬프트 본문 (여기서부터 복사)

너는 최상급 프론트엔드/데이터 엔지니어다. 아래 명세대로 "퍼포먼스 광고 소재 성과분석 대시보드"를 처음부터 끝까지 만들어라. 결과물은 ① 단일 `index.html` ② Supabase SQL 마이그레이션 ③ GitHub Pages 배포 워크플로우다. 외부 라이브러리·프레임워크·번들러 금지(바닐라 JS/CSS/SVG). 모든 집계·채점·차트는 브라우저에서 계산한다.

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

-- RLS 전면 차단: 접근은 오직 SECURITY DEFINER RPC로만
alter table weekly_creative_stats enable row level security;
alter table cr_kv enable row level security;

-- 비밀번호 게이트
create or replace function _cr_check_pw(pw text) returns void
language plpgsql security definer set search_path to 'public' as $$
begin
  if pw is distinct from '<PASSWORD>' then
    raise exception 'invalid password' using errcode = '28000';
  end if;
end $$;

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
2. **몰로코 크리에이티브 리포트**: `creative_preview` 있거나 `ad_name`+`creative_type`. `creative_preview`의 href/URL→`_m_url`, `creative_type`→`_m_ctype`, `resolution`→`_m_res`, `creative_group_name`→`_m_group`(레벨이 아니라 소재의 속성으로 취급, 분석은 소재 단위).
3. **일반 성과 CSV(메타 등)**: `date`+`ad_name`(+지표들). `thumbnail_url/image_url/creative_preview/미리보기/썸네일` 컬럼이 있으면 `_m_url`로 연결.
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

`displayNameOf`: 그룹 행 → `_` 분절형(`중고거래·shortform·2601`, maugrowth 생략, 그 앞 접두만 유지, 서비스 사전: fleamarket|중고|declutter→중고거래 · realty|rentkarrot|lifedaangn→부동산 · jobs|알바→알바 · localbiz|동네→동네업체 · branding→브랜딩) → `gmap.asset[항목ID]`(공식) → `ocr[항목ID]`(OCR 마크 부착) → `ytt[유튜브ID]` → 원문. 내부 키·저장·정렬은 항상 원문. 유튜브 제목은 로드 1.2초 후 전 소재 자동 조회(noembed.com, 동시 4, localStorage+kv `ytt` 공유).

### 6. UI 명세

- 좌측 다크 사이드바(248px): 매체 세그(소재 수 많은 순, 기간 반영 카운트) / 기간(최근 1달=4주·최근 3달=13주·전체·직접 설정 "최근 [N][주|달]", 달≈4.345주) / 요약 KPI(총 광고비·설치·eCPI·활성·eCPA + 지난주 증감) / ☁️ 저장소 줄("소재 N개 · 주간 기록 M건 · W주 · 클릭=새로고침", 툴팁에 업로더 분포) / 용어·CSV 버튼. ≤900px: 매체·기간 2분할, 나머지는 '요약' 토글(기본 접힘), 표의 소재 이름 숨김(미리보기만).
- 본문: 세그먼트 탭(분석/전체 목록/AB테스트 — AB 그룹 0개면 탭 숨김), 카드 없이 흰 배경 풀폭, sticky 탭, 푸터는 캔버스색+64px 간격.
- 분석: 요약 타일 3개, 효율 지도(축 선택 산점도+범위 슬라이더, 상위 광고비 라벨 · '보기' 세그먼트: 소재(기본)/포맷/사이즈/형태/지면/서비스 — 유형 선택 시 typeAggRows(상하 10% 트림 합산)로 유형당 1점 집계·전 지점 라벨·클릭 없음·툴팁에 포함 소재 수, 값 2개 이상인 차원만 노출. 보기/가로/세로 모두 세그먼트 컨트롤), 주차별 추세(선택 기간 전체, 라벨 ≤13 자동 솎기, 광고비 면적+효율선 이중축). 별도 '유형별 비교' 그래프는 없음(지도에 흡수).
- 전체 목록: 컬럼 계층 — 대표(점수|노출|eCPI|eCPA|CTR|완주율|ROAS)만 기본, 헤더 `+`로 그룹 세부(노출→광고비·CPM / eCPI→설치·설치(몰로코) / eCPA→활성·신규+재활성·신규 eCPA / CTR→클릭·CPC / ROAS→전환류 전체) 펼침, 정렬과 독립. 필터: Live(기본 ON, 스코프 최신 집행 주 비용>0, 그룹은 멤버 기준) · GroupView(광고그룹 집계, Video/Image와 상호 배타) · Video/Image · 이름 아래 칩 클릭 필터(서비스·포맷·사이즈·네이티브·그룹, 그룹 행은 접두·날짜·수식어 칩, ✕ 배지 해제). 60행 페이지네이션. 셀은 컬럼 분포 5분위 색상. 매체 전환 시 페이지 1로 리셋.
- 이름 옆 뱃지: `Live`(초록 점, 최신 집행 주 광고비>0 — 그룹은 멤버 기준, 전 매체) · `경고`(구글 ginfo 정책 제한만, 사유 툴팁) · `학습중`(2주 미만 or 전환 30건 미만). 운영중·일시중지는 뱃지 없음(일시중지는 그룹 상세 메타 텍스트로만).
- 상세(행 클릭 아코디언): 구조 = `.isle-row3` 단일 grid(areas "media mid cmp"): [ir-media(프레임+원본링크, 열폭 ar-v 232/ar-s 280/ar-h 400px, ≤1200에서 260/320) | ir-mid(주차별 추이 ispark 위 + '지표별 계정 내 위치' .sb 1열 아래) | ir-cmp(같은 그룹/시리즈 비교, minmax(0,1.25fr))]. 점수·진단·구분선·내비 버튼 없음. 비교 목록: table-layout:fixed(수치 열 90/82/62px)+한 줄 ellipsis, prefixTrimmer(공통 접두 토큰 경계(≥10자)에서 '…' 접기, tr title=풀네임). 모바일(≤860): areas "media"/"cmp"/"mid" 1열(중요도 순), 프레임 max-width 320(가로 420)px 중앙. 이미지 실패·비율 판정(isleAr)·키보드 ←/→·Esc·딥링크 해시는 유지.
- AB테스트: 접미 변형 자동 인식 — 확장자·해상도(1080x1920)·화면비(16x9) 제거 후, 문자 변형(구분자+[Vv|ver|시안]?+A~F, 어간 영숫자≥4 또는 한글≥2), 숫자 변형 1~5만(v접두/제로패딩 01~05/회차 ep·part·pt·편·화·회차+숫자/문자 직결 숫자, 맨숫자 "_2"는 제외, 숫자 계열은 변형 '1' 필수). 목록(이름+🥇🥈🥉 미니 썸네일)→펼침: 변형=열 비교표, 스프레드 ≥5% 지표만 최고 초록·최저 빨강, 대표(최고 점수) 미디어 크게, '대표 소재 상세' 버튼.
- 공통: 비밀번호 화면(자동 포커스), 자동 재접속 시 랜딩 대신 "저장소 불러오는 중" 대형 미니멀 로딩(비밀번호 무효 시에만 입력 화면+저장값 폐기), `/아이디`+Enter 서명·`/logout` 해제·서명 시 Hi 토스트(탭당 1회), 토스트 알림, 용어 사전, 점수 방법론 푸터.

### 7. 배포 — .github/workflows/pages.yml

main 푸시 시 Pages 배포. `actions/upload-pages-artifact` + `actions/deploy-pages`. **배포 스텝은 `continue-on-error` + 실패 시 90초 대기 후 2차, 다시 실패 시 5분 대기 후 3차 재시도** (GitHub Pages의 간헐적 "Deployment failed, try again later" 대응).

### 8. 오프라인 이름 보강 배치 (선택, 별도 환경에서)

- PaddleOCR(lang="korean", paddlepaddle 2.6.x + paddleocr 2.8.x)로 구글 이미지 애셋 텍스트 추출 → kv `ocr`. 필수 설정: `OMP_THREAD_LIMIT=1`, 이미지 1100px 그레이 리사이즈, 숫자 포함 라인은 conf 0.55까지 수용, 박스 좌표로 위→아래·좌→우 정렬, 후처리(허용문자 정제, 선두 단독 '당근'·로고 오인 접두 제거, 48자 컷).
- dHash(9×8, 해밍 ≤6, 종횡비 ±12%)로 몰로코 IMAGE 소재와 동일 이미지 매칭 → 몰로코 실명을 `gmap.asset`에.

### 9. 완성 검증 체크리스트

로그인(카운트 문구) / 3매체 CSV 드롭 누적·중복 0 / 월간 파일 임시 분석 배너 / 기간 전환 시 카운트·추세 갱신 / Live·GroupView·칩 필터 / 상세 코호트·점수 구성 / AB 인식(오인 케이스: name_2 미인식, kkak01=1) / 광고그룹 보고서 확인창(변경 시에만) / 새로고침 무깜빡임 / 모바일(2분할·요약 접힘·이름 숨김) / 페이지 콘솔 에러 0.

## 프롬프트 본문 끝
