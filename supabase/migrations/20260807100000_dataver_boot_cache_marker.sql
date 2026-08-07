-- 2026-08-07 · 데이터 버전 마커 — 부팅 캐시가 payload 내부 수정을 못 알아채던 문제
-- Supabase에는 MCP로 이미 적용됨. 이 파일은 형상 기록용.
--
-- 증상: 2026-08-06 몰로코 거짓 노출 0을 지운 뒤에도 화면엔 '⚠ 노출 미수집 1주' 배지가 그대로 남았다.
-- 원인: cr_status가 돌려주는 시그니처가 (행수, max(uploaded_at))뿐인데, payload 안의 키만 고치는
--       제자리 UPDATE는 행수도 uploaded_at도 바꾸지 않는다. 그래서 브라우저 IndexedDB 캐시는
--       "서버가 그대로다"라고 판단하고 옛 데이터를 계속 렌더했다. DB는 처음부터 정상이었다.
-- 해결: 데이터가 어떤 식으로든 바뀌면 올라가는 마커(sr_kv['dataver'])를 두고 cr_status가 함께 반환.
--       사이트의 bootSigOf/bootSigSame이 이 값을 시그니처에 포함한다.

create or replace function public._cr_bump_dataver()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  insert into public.sr_kv(k, v, updated_at, updated_by)
  values ('dataver', to_jsonb(clock_timestamp()::text), now(), 'trigger')
  on conflict (k) do update
    set v = excluded.v, updated_at = excluded.updated_at, updated_by = excluded.updated_by;
  return null;
end
$function$;

-- 문장 단위 — 146행을 한 번에 고쳐도 마커는 한 번만 올라간다(행 단위면 146번 쓴다).
drop trigger if exists cr_bump_dataver on public.sr_weekly_creative_stats;
create trigger cr_bump_dataver
after insert or update or delete on public.sr_weekly_creative_stats
for each statement execute function public._cr_bump_dataver();

insert into public.sr_kv(k, v, updated_at, updated_by)
values ('dataver', to_jsonb(clock_timestamp()::text), now(), 'seed')
on conflict (k) do update
  set v = excluded.v, updated_at = excluded.updated_at, updated_by = excluded.updated_by;

-- cr_status에 dataver 추가. 기존 키는 그대로 두어 옛 사이트 코드도 계속 동작한다.
create or replace function public.cr_status(pw text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare res jsonb;
begin
  perform _cr_check_pw(pw);
  select jsonb_build_object(
    'rows', count(*),
    'ads', count(distinct ad_name),
    'weeks', count(distinct week_start),
    'channels', coalesce(jsonb_agg(distinct channel),'[]'::jsonb),
    'first_week', min(week_start),
    'last_week', max(week_start),
    'unsigned_rows', count(*) filter (where uploaded_by is null or uploaded_by in ('','unknown')),
    'uploaders', (select coalesce(jsonb_object_agg(u, c), '{}'::jsonb) from (select uploaded_by u, count(*) c from sr_weekly_creative_stats group by 1) t),
    'last_upload', max(uploaded_at),
    'dataver', (select v #>> '{}' from sr_kv where k = 'dataver'))
  into res from sr_weekly_creative_stats;
  return res;
end
$function$;
