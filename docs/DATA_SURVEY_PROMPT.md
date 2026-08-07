# CR 데이터 소스 전수 조사 — 데스크톱 Claude용 프롬프트

> 회사 네트워크의 Claude 데스크톱(superset/bigquery MCP 설치본)에 아래 코드블록을 그대로 붙여넣으세요.
> 목적: CR이 지금 못 쓰고 있는 소재 단위 데이터가 원천에 무엇이 있는지, 지연은 얼마인지 전수 파악.

```
CreativeReporter의 데이터 원천을 전수 조사해줘. superset MCP와 bigquery MCP를 적극적으로 써라.
결과는 마크다운 보고서 하나로 정리해서 보여줘. 추측 금지 — 전부 실제 조회로 확인해라.

[1] 테이블 인벤토리와 신선도(지연)
- karrotmarket.team_marketing 데이터셋의 테이블 목록을 뽑고, 아래 각각에 대해
  스키마(컬럼 전체)와 MAX(date)·오늘과의 차이(일)를 조회해라:
  · molocoAD_daily_metrics  (몰로코 콘솔 — 노출·클릭·설치·매출·Video_Play1q~4q·Creative_MainAssetLocation)
  · maugrowth_marketing_ad_report / adset_report (AppsFlyer)
  · maugrowth_marketing_appsflyer_report
- karrotmarket.appsflyer.cohort_unified 의 MAX(event_date)와 지연도.
- 특히 molocoAD_daily_metrics 의 "요일별 적재 패턴"을 확인해라: 최근 4주에 대해
  날짜별 행 수를 뽑아, 월요일 아침 시점에 직전 주(월~일)가 다 차 있는지 판정해라.
  → 이것이 주간 자동화(월 실행)에서 노출이 0으로 들어온 사고의 원인 검증이다.

[2] 매체별 소재 단위로 '얻을 수 있는 것' 목록
각 매체에 대해, 소재(ad_name/asset) 단위로 존재하는 지표·메타데이터를 표로 정리해라.
지금 CR payload에 없는 것에는 ★를 붙여라.
- 몰로코: 콘솔(노출·클릭·설치·매출 USD·영상 4분위 재생·실제 영상 URL·Creative_Type·그룹) + AF(비용·기여·재설치·재참여) + cohort_unified(D1/D7 리텐션 분자분모·코호트 매출 D0/D7)
- 메타: AF 계열에서 소재 단위로 가능한 것 전부. 영상 지표(3초·thruplay 등)가 BigQuery 어디에든 있는지 찾아보고, 없으면 '없음(원천 미적재)'로 명시.
- 구글: AEO_weekly/ACE_weekly 시트와 애셋 스프레드시트에서 소재 단위로 더 가져올 수 있는 컬럼(지금 CR이 안 쓰는 것) — 특히 영상 재생 4분위(v25~v100)가 애셋 단위로 존재하는지.
- **본명 커버리지**: 구글 애셋 중 '애셋 이름'이 없는(URL만 남은) 애셋 수와, 애셋 스프레드시트가 공유되지 않은 캠페인 목록을 뽑아라. 본명(_name)은 CR 이름 체계의 1순위라, 미보유분을 없애는 게 최우선 개선이다.

[3] Superset 대시보드 2075
- 세 차트 각각의 데이터셋/뷰 SQL을 받아, 차트가 '내보내는 컬럼'과 '내부 virtual_table에만 있는 원시 컬럼'을 구분해 나열해라.
- 몰로코 차트의 IFNULL(콘솔, AF) 폴백이 걸린 컬럼을 전부 짚어라(노출·클릭 외 더 있는지).

[4] CR payload 키 매핑 제안
위에서 찾은 것들을 CR payload 키로 매핑한 표를 만들어라. 기존 키:
_v25/_v50/_v75/_v100, _q_retD1Base/Users, _q_retD7Base/Users, _q_revD0/_q_revD7,
_q_afInstalls/_q_reAtt/_q_reEng, _m_installs/_m_group/_m_ctype/_m_url/_m_resName,
_name/_res/_ar/_svc. 새 키가 필요한 항목은 이름을 제안하되 '중복 집계 위험'(이벤트 수 vs 유저 수,
매체 간 귀속 단위 차이)을 반드시 표기해라.

[5] 결론
- 주간 자동화가 월요일에 안전하게 돌 수 있는 실행 시각(또는 '몰로코만 화요일' 같은 분리안)을 데이터로 제안해라.
- 백필 우선순위: 실증(umetrics) trend_new_users 과거 주차 / 몰로코 07-27 노출 / 원시 카운트(_v·_q_*) 소급 — 각각 몇 주치가 원천에 존재하는지 확인해서.
```
