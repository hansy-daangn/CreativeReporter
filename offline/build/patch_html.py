import sys, io
PATH = "index.html"
src = io.open(PATH, encoding="utf-8").read()

edits = []  # (name, old, new, expected_count)

# E1: local font, drop preconnect + jsdelivr stylesheet
edits.append(("font",
'<link rel="preconnect" href="https://cdn.jsdelivr.net" crossorigin>\n'
'<link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/orioncactus/pretendard@v1.3.9/dist/web/variable/pretendardvariable-dynamic-subset.css">',
'<link rel="stylesheet" href="fonts/pretendard.css">', 1))

# E2: inject offline scripts before the single main <script>
edits.append(("inject", "<script>",
'<script src="sha256.js"></script>\n'
'<script src="data.js"></script>\n'
'<script src="assets/manifest.js"></script>\n'
'<script src="offline_shim.js"></script>\n'
'<script>', 1))

# E3: IMG_PROXY -> local map ; imgSrc -> local map
edits.append(("img_proxy",
'const IMG_PROXY=u=>"https://wsrv.nl/?url="+encodeURIComponent(u);',
'const IMG_PROXY=u=>(window.OFFLINE_ASSETS&&window.OFFLINE_ASSETS[u])||u;', 1))
edits.append(("imgSrc",
'function imgSrc(u){try{if(localStorage.getItem("crImgProxy")||sessionStorage.getItem("crImgProxy"))return IMG_PROXY(u);}catch(e){}return u;}',
'function imgSrc(u){var m=window.OFFLINE_ASSETS&&window.OFFLINE_ASSETS[u];return m?m:u;}', 1))

# E4: fetchYtTitle -> no network (titles preloaded from embedded ytt kv)
edits.append(("ytTitle",
'  try{const r=await fetch(`https://noembed.com/embed?url=${encodeURIComponent("https://www.youtube.com/watch?v="+id)}`);\n'
'    const j=await r.json();const t=j&&j.title?String(j.title):null;\n'
'    _ytTitles[id]=t;if(t){try{localStorage.setItem("ytt_"+id,t);}catch(e){}}\n'
'    return t;\n'
'  }catch(e){_ytTitles[id]=null;return null;}}',
'  _ytTitles[id]=null;return null;}', 1))

# E5: sbRpc -> local dispatch (early return; rest becomes dead code)
edits.append(("sbRpc",
'async function sbRpc(fn,body,opt){\n'
'  /* 네트워크가 멈추면(응답 없음) 무한 대기 → 부팅/조작이 영구 잠기는 것을 방지: AbortController 타임아웃 */',
'async function sbRpc(fn,body,opt){\n'
'  return window.__offlineRpc(fn,body||{});\n'
'  /* 네트워크가 멈추면(응답 없음) 무한 대기 → 부팅/조작이 영구 잠기는 것을 방지: AbortController 타임아웃 */', 1))

# E6: video src -> local (4 spots, each unique prefix)
edits.append(("vid1", '<video src="${escAttr(safeUrl(url))}',
             '<video src="${escAttr(window.__vsrc(url))}', 1))
edits.append(("vid2", '<video class="asset-vid" src="${escAttr(safeUrl(url))}',
             '<video class="asset-vid" src="${escAttr(window.__vsrc(url))}', 1))
edits.append(("vid3", '<video class="tvid" src="${escAttr(safeUrl(url))}',
             '<video class="tvid" src="${escAttr(window.__vsrc(url))}', 1))
edits.append(("vid4", '<video class="gal-vid" src="${escAttr(safeUrl(url))}',
             '<video class="gal-vid" src="${escAttr(window.__vsrc(url))}', 1))

# E7a: hover tooltip YouTube iframe -> static local poster + play glyph
edits.append(("yt_tip",
'    return `<div class="tp-ytwrap" style="background-image:url(\'${escAttr(imgSrc(hi))}\')"><iframe class="tp-yt" width="320" height="180" src="https://www.youtube.com/embed/${yt[1]}?autoplay=1&mute=1&controls=0&playsinline=1&loop=1&playlist=${yt[1]}&modestbranding=1" frameborder="0" allow="autoplay; encrypted-media"></iframe></div><div class="tp-cap">▶ ${escHtml(label||"영상")}</div>`;}',
'    return `<div class="tp-ytwrap" style="position:relative;background-image:url(\'${escAttr(imgSrc(hi))}\')"><div style="position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-size:34px;color:#fff;text-shadow:0 2px 8px rgba(0,0,0,.6)">▶</div></div><div class="tp-cap">▶ ${escHtml(label||"영상")}</div>`;}', 1))

# E7b: detail-view YouTube iframe -> local poster + badge
edits.append(("yt_detail",
'  if(yt)return `<div class="isle-frame"><iframe class="asset-yt" src="https://www.youtube.com/embed/${yt[1]}" frameborder="0" allow="encrypted-media" allowfullscreen></iframe></div>${srcLine()}`;',
'  if(yt)return `<div class="isle-frame" style="position:relative"><img class="asset-img" src="${escAttr(window.__ytThumb(yt[1]))}" alt="YouTube" style="width:100%;height:100%;object-fit:contain;background:#000"><span style="position:absolute;left:8px;bottom:8px;background:rgba(0,0,0,.62);color:#fff;font-size:11px;padding:2px 8px;border-radius:7px">▶ YouTube (오프라인 포스터)</span></div>${srcLine()}`;', 1))

# E7c: gallery hover YouTube iframe -> disabled (poster stays; YouTube can't stream offline)
edits.append(("yt_gallery",
'  host.querySelectorAll(".gal-img[data-yt]").forEach(im=>{\n'
'    const box=im.closest(".gal-media");if(!box)return;\n'
'    box.addEventListener("mouseenter",()=>{if(box.querySelector("iframe"))return;\n'
'      const id=im.dataset.yt,f=document.createElement("iframe");\n'
'      f.className="gal-yt";f.allow="autoplay; encrypted-media";f.setAttribute("frameborder","0");\n'
'      f.src=`https://www.youtube.com/embed/${id}?autoplay=1&mute=1&controls=0&playsinline=1&loop=1&playlist=${id}&modestbranding=1`;\n'
'      box.appendChild(f);});\n'
'    box.addEventListener("mouseleave",()=>{const f=box.querySelector("iframe");if(f)f.remove();});});',
'  host.querySelectorAll(".gal-img[data-yt]").forEach(im=>{ /* OFFLINE: YouTube cannot stream — static local poster only */ });', 1))

fail = False
for name, old, new, cnt in edits:
    c = src.count(old)
    if c != cnt:
        print(f"!! {name}: expected {cnt} occurrence(s), found {c}")
        fail = True
if fail:
    print("ABORTED — no changes written.")
    sys.exit(1)
for name, old, new, cnt in edits:
    src = src.replace(old, new)
io.open(PATH, "w", encoding="utf-8").write(src)
print(f"OK — applied {len(edits)} edits.")
# sanity: no live network hosts left in loadable positions
for host in ["wsrv.nl", "noembed.com", "cdn.jsdelivr.net", "youtube.com/embed", "supabase.co/rest"]:
    print(f"  remaining '{host}': {src.count(host)}")
