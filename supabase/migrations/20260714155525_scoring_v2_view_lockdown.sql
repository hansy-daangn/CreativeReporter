-- Migration: scoring_v2_view_lockdown
-- Purpose : sr_scoring_v2 뷰 접근 잠금 — 분석(SQL/BI) 전용 피드로 한정.
-- Why     : Supabase 기본권한이 public 스키마 신규 객체에 anon/authenticated SELECT를
--           자동 부여하고, 뷰는 기본적으로 소유자 권한으로 실행되어 원본 테이블
--           (sr_weekly_creative_stats)의 RLS(사이트 비밀번호 게이트)를 우회할 수 있다.
--           둘 다 잠가 사이트의 기존 접근 통제(RPC 게이트, PR #102)를 유지한다.
-- Applied : 2026-07-14 remote version 20260714155525.
-- 프론트는 기존 RPC 경로 유지(03 결정 로그 D7). API 노출이 필요해지면 별도 마이그레이션으로:
--   grant select on public.sr_scoring_v2 to authenticated;

alter view public.sr_scoring_v2 set (security_invoker = true);
revoke all on public.sr_scoring_v2 from anon, authenticated;
