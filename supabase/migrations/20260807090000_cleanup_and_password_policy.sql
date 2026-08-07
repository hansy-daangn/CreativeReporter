-- 2026-08-07 · 미사용 객체 정리 + 비밀번호 정책
-- Supabase에는 MCP로 이미 적용됨. 이 파일은 형상 기록용(재현 가능하도록 동일 내용).

-- ── 1. 미사용 객체 정리 ────────────────────────────────────────────────
-- sr_kv['ocr'] · sr_kv['ytt'] : OCR·유튜브 제목 이름 경로가 2026-08-06에 은퇴하면서
--   index.html이 더 이상 읽지 않는다(부팅 왕복 2개도 함께 사라짐). 남겨둘 이유가 없다.
delete from public.sr_kv where k in ('ocr','ytt');

-- sr_google_backfill : 2026-08-04 구글 백필·주차별 대사에 쓴 스테이징(7,486행).
--   백필과 검증이 끝났고 사이트·자동화 어디서도 참조하지 않는다. 필요하면 BigQuery에서 재추출된다.
--   RLS가 꺼진 채 anon 키에 전량 노출돼 있던 테이블이기도 해서, 드롭이 RLS를 켜는 것보다 확실하다.
--   CASCADE를 쓰지 않는다 — 숨은 의존성이 있으면 조용히 지우는 대신 실패해야 한다.
drop table if exists public.sr_google_backfill;

-- cr_idempotency_check() : 1회성 점검용 임시 함수. 트리거·사이트·문서 어디서도 호출하지 않는다.
drop function if exists public.cr_idempotency_check();

-- 남겨둔 것 (지우지 마라)
--   _cr_strip_false_zero_impressions() · sr_nfc_ad_name() : 트리거 3개가 물려 있다.
--   creative_names · figma_namer_titles · namer_*() : CR 미사용이나 타 앱 소유 가능성(2026-07-11 판단 유지).
--   sr_kv['mediameta'] : ffprobe 실측 해상도의 출처·근거가 담긴 재현 불가 데이터.

-- ── 2. 비밀번호 정책 — 6자 이상 + 단순 비밀번호 차단 ────────────────────
-- cr_register / cr_admin_create / cr_admin_setpw 세 경로가 모두 이 함수를 통과한다.
-- 로그인(cr_login·_cr_check_pw)은 해시 대조만 하고 이 함수를 부르지 않으므로
-- **이미 가입된 계정은 규칙이 조여져도 그대로 로그인된다.** 기존 행은 건드리지 않는다.
create or replace function public._cr_pwok(p text)
returns boolean
language plpgsql
immutable
set search_path to 'public'
as $function$
declare
  s text; n int; i int;
  up boolean := true; down boolean := true;
begin
  s := coalesce(p, '');
  n := length(s);

  -- 1) 최소 6자
  if n < 6 then return false; end if;

  -- 2) 같은 글자만 반복 (111111, aaaaaa)
  if s ~ '^(.)\1*$' then return false; end if;

  -- 3) 통째로 연속 증가·감소 (123456, 654321, abcdef)
  for i in 1..n-1 loop
    if ascii(substr(s,i+1,1)) <> ascii(substr(s,i,1)) + 1 then up := false; end if;
    if ascii(substr(s,i+1,1)) <> ascii(substr(s,i,1)) - 1 then down := false; end if;
  end loop;
  if up or down then return false; end if;

  -- 4) 흔한 비밀번호
  if lower(s) = any (array[
    'password','passw0rd','p@ssword','qwerty','qwerty123','qwertyui','asdfgh','asdfasdf',
    'zxcvbn','zxcvbnm','1q2w3e','1q2w3e4r','qwer1234','asdf1234','q1w2e3r4','1qaz2wsx',
    'abc123','abcd1234','123123','121212','112233','123321','1234qwer','iloveyou',
    'letmein','welcome','admin','admin123','administrator','root123','test123','guest123',
    'dragon','monkey','sunshine','princess','football','baseball','trustno1','master',
    'daangn','karrot','danggn','daangn123','karrot123','creative','report','creativereport'
  ]) then return false; end if;

  return true;
end
$function$;
