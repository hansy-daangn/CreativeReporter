-- Migration: creative_reporter_scoring_v2_view
-- Purpose : CreativeReporter 개편(2026-07 미팅) — 정제 채점 피드.
--           과집계 지표(홈방문 _g_home ≈427x first_open, ACE 전환 CPA)를 제외하고
--           효율=신규+재활성 eCPA, 규모=신규+재활성(AUU) 기준으로 노출.
-- Safety  : 기존 테이블/데이터 무변경. CREATE OR REPLACE VIEW (부가만).
-- Verified: 뷰 본문 SELECT를 Supabase(newoydegfbnnqujgiips)에서 읽기전용 실행해 정상 확인.
--           (2026-06~ 가중 eCPA: Google ₩30 / Moloco ₩684 / Meta ₩2,365 — 02 P2 교차검증 결과와 일치)
-- Applied : 2026-07-14 remote version 20260714155424 (권한 잠금은 다음 마이그레이션 20260714155525).
-- 근거    : Obsidian 「CreativeReporter_개편_202607」 03 결정 로그 D1·D2 / 02 P2 교차검증 결과.

create or replace view public.sr_scoring_v2 as
select
  s.id,
  s.channel,
  s.week_start,
  s.ad_name,

  -- 신뢰 지표(실측)
  s.cost_krw,
  s.impressions,
  s.clicks,
  nullif(s.payload->>'신규+재활성 유저 수','')::numeric as nr_users, -- 규모(AUU)

  -- 효율: 신규+재활성 eCPA (유입 유저당 단가)
  round(s.cost_krw / nullif(nullif(s.payload->>'신규+재활성 유저 수','')::numeric, 0)) as ecpa_nr,

  -- 참고 지표
  round(1000.0 * s.cost_krw / nullif(s.impressions, 0)) as cpm,
  round(100.0 * s.clicks / nullif(s.impressions, 0), 2) as ctr_pct,

  -- 보조: 잔존율
  round(100.0 * nullif(s.payload->>'_q_retD1Users','')::numeric
        / nullif(nullif(s.payload->>'_q_retD1Base','')::numeric, 0), 2) as ret_d1_pct,
  round(100.0 * nullif(s.payload->>'_q_retD7Users','')::numeric
        / nullif(nullif(s.payload->>'_q_retD7Base','')::numeric, 0), 2) as ret_d7_pct,

  -- Google 그룹뷰 키 (그룹 내 상대평가용)
  s.payload->>'_g_adGroupId'  as g_adgroup_id,
  s.payload->>'_g_campaignId' as g_campaign_id,
  s.payload->>'_g_assetType'  as g_asset_type,

  -- 과집계 원본(참고·채점 제외 대상): 신뢰하지 말 것
  nullif(s.payload->>'_g_home','')::numeric      as g_home_overcounted,
  nullif(s.payload->>'_g_firstOpen','')::numeric as g_first_open
from public.sr_weekly_creative_stats s;

comment on view public.sr_scoring_v2 is
  'CreativeReporter 개편 v2 채점 피드: 과집계(홈방문·전환CPA) 제외, 신규+재활성 eCPA(효율)·규모(AUU)·D7 기준. 2026-07 미팅 근거.';
