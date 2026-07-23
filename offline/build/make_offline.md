# 오프라인 완전판을 다시 만드는 방법 (재현 파이프라인)

인터넷이 차단된 환경에서 CreativeReporter를 **온라인과 100% 동일**하게 구동하기 위한
오프라인 패키지 빌드 절차입니다. 사이트가 Supabase(RPC)에 의존하는 모든 지점을
로컬 스냅샷/자산으로 대체합니다. 네트워크 요청은 0건이 됩니다.

> ⚠️ 결과물(`data.js`, `assets/`, `fonts/`, 완성 `index.html`)에는 실제 성과 데이터와
> 계정 비밀번호 해시가 들어갑니다. **이 공개 저장소에 커밋하지 마세요.** (`.gitignore` 참고)
> 로컬 zip으로만 배포합니다.

## 사이트가 쓰는 네트워크 지점 (전부 대체 대상)

| 지점 | 온라인 | 오프라인 대체 |
|---|---|---|
| Supabase RPC (`cr_load`/`cr_login`/`cr_status`/`cr_kv_get`/`cr_marks_load`/쓰기류) | `sbRpc()` → REST | `offline_shim.js`의 로컬 디스패처(`__offlineRpc`) + `data.js` 스냅샷 |
| 로그인 비밀번호 검증 | 서버 `sha256(pw)` | `sha256.js`로 브라우저에서 동일 검증(무염 sha256 hex) |
| 소재 미리보기 이미지/영상 | adsmoloco·googlesyndication CDN | `assets/`에 다운로드 후 `imgSrc`/`__vsrc`가 로컬 경로로 매핑 |
| YouTube 소재 | iframe 임베드(스트리밍) | 로컬 썸네일 포스터 + ▶ 표시 (오프라인 저장 불가) |
| YouTube 제목 | noembed.com | `kv:ytt` 스냅샷(이미 포함) |
| Pretendard 폰트 | jsdelivr | `fonts/`에 로컬 번들 |
| 이미지 프록시(wsrv.nl) | 차단 CDN 우회용 | 불필요(전부 로컬) — 무력화 |

## 절차

원본 `index.html`이 있는 저장소 루트에서, 빈 작업 폴더를 만들어 진행합니다.
Supabase는 레거시 뷰어 비밀번호 `0715`로 읽기가 되므로(`_cr_check_pw`), 데이터는
사이트가 쓰는 것과 동일한 RPC로 그대로 덤프합니다.

```bash
SB_URL="https://newoydegfbnnqujgiips.supabase.co"
SB_KEY="<publishable key (index.html의 SB_KEY와 동일)>"
mkdir -p _raw

# 1) 데이터 스냅샷 (사이트와 동일한 RPC 형태로 그대로 저장)
curl -s "$SB_URL/rest/v1/rpc/cr_load"   -H "apikey: $SB_KEY" -H "Authorization: Bearer $SB_KEY" \
     -H "Content-Type: application/json" -d '{"pw":"0715"}' -o _raw/weekly.json
for k in gmap ginfo ocr ytt nameovr svcovr; do
  curl -s "$SB_URL/rest/v1/rpc/cr_kv_get" -H "apikey: $SB_KEY" -H "Authorization: Bearer $SB_KEY" \
       -H "Content-Type: application/json" -d "{\"pw\":\"0715\",\"key\":\"$k\"}" -o "_raw/kv_$k.json"
done
curl -s "$SB_URL/rest/v1/rpc/cr_status" ... -d '{"pw":"0715"}' -o _raw/status.json
# _raw/users.json (daangn_name,status,role,pw_hash) 와 _raw/marks.json ([{c,a,n,k}]) 은
# 서버 RPC로 노출되지 않으므로 DB에서 직접 덤프해 넣는다(관리자 권한 필요).

# 2) 미리보기 URL 추출 → 자산 다운로드 (build 스크립트 참고)
#    weekly.json의 payload._m_url/_g_url 를 도메인·유형별로 분류 → dl.py 로 병렬 다운로드
#    + YouTube ID별 썸네일(img.youtube.com/vi/<id>/hqdefault.jpg)
python3 build/dl.py dl_moloco_img.tsv 16
python3 build/dl.py dl_moloco_vid.tsv 8
python3 build/dl.py dl_gsyn.tsv 10
python3 build/dl.py dl_yt_thumb.tsv 16

# 3) data.js 생성 (weekly+kv+users+marks+status 임베드)
python3 build/build_data.py

# 4) 폰트 로컬화
bash build/fetch_fonts.sh fonts

# 5) index.html 오프라인 패치 (원본을 복사한 뒤 실행)
cp ../index.html ./index.html
python3 build/patch_html.py    # sbRpc→로컬, imgSrc/__vsrc→로컬, YouTube→포스터, 폰트/noembed/wsrv 제거

# 6) 자산 맵 manifest.js 생성 (원본 URL → 로컬 경로) 후 zip
```

## 검증

헤드리스 브라우저에서 **모든 비-`file://` 요청을 차단**한 채 열어, 외부 요청 0건·콘솔
에러 0건으로 데이터가 로드되고 표·상세·차트·미리보기가 뜨는지 확인한다. (`0715` 로그인)

## 런타임 파일 역할

- `offline_shim.js` — 모든 RPC를 로컬 스냅샷으로 처리(로그인/데이터/kv/마크/쓰기). 미디어 URL→로컬 매핑 헬퍼.
- `sha256.js` — 서버와 동일한 비밀번호 해시(로그인 검증). Postgres `digest(pw,'sha256')` 와 바이트 단위로 일치.
- `fetch_assets.py` — 라이트판 사용자용: `assets_manifest.tsv`를 읽어 미리보기 자산을 로컬로 내려받음.
