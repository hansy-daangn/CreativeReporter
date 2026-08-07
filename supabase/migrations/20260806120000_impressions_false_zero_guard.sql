-- 노출 '거짓 0' 차단 — 클릭이 있는데 노출이 0인 행은 물리적으로 불가능하다(2026-07-27 몰로코 사고:
-- 대시보드 쿼리의 IFNULL 폴백이 콘솔 미적재 주에 AF 값으로 떨어지며 노출 0이 기록됨).
-- 값을 지어내지 않고 거짓 키만 걷어낸다. 런북·사이트가 놓쳐도 DB가 마지막 방어선.
create or replace function public._cr_strip_false_zero_impressions()
returns trigger language plpgsql as $$
declare imp numeric; clk numeric;
begin
  if new.payload ? '노출 수' then
    begin imp := (new.payload->>'노출 수')::numeric; exception when others then imp := null; end;
    begin clk := (new.payload->>'클릭 수')::numeric; exception when others then clk := null; end;
    if imp is not null and imp = 0 and clk is not null and clk > 0 then
      new.payload := new.payload - '노출 수';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists cr_strip_false_zero_impressions on public.sr_weekly_creative_stats;
create trigger cr_strip_false_zero_impressions
before insert or update on public.sr_weekly_creative_stats
for each row execute function public._cr_strip_false_zero_impressions();
