// Build self-contained UI proposal pages from ../index.html.
// Each proposal = the real app + a theme override layer + a demo-data bootstrap
// (loads synthetic sample data so the page is viewable without the password gate)
// + a floating switcher to compare 시안 A / B and jump back to the real tool.
//
//   node proposals/build.mjs         (run from repo root)
//
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, '..');

const CONFIGS = [
  { id:'a', out:'a-editorial.html', theme:'theme-editorial.css', cls:'theme-editorial',
    title:'소재분석 · 시안 A 편집형 리포트', label:'A · 편집형 리포트' },
  { id:'b', out:'b-console.html', theme:'theme-console.css', cls:'theme-console',
    title:'소재분석 · 시안 B 대시보드 콘솔', label:'B · 대시보드 콘솔' },
];

const base = readFileSync(join(repo, 'index.html'), 'utf8');
const csv = readFileSync(join(here, 'demo-data.csv'), 'utf8');
if (csv.includes('`') || csv.includes('${')) throw new Error('demo CSV unsafe for template literal');

// ---- shared demo bootstrap (data auto-load, no login) ----
const bootstrap = `<script>/* 시안 데모 부트스트랩 — 로그인 없이 합성 샘플 데이터로 UI를 바로 미리보기 */
(function(){
  var CSV = \`${csv}\`;
  function hideLanding(){var l=document.getElementById('landing'); if(l){l.classList.add('hidden'); l.style.display='none';}}
  var booted=false;
  function boot(){
    if(typeof window.handleFiles!=='function'){return setTimeout(boot,50);}
    if(booted) return; booted=true;
    try{ window.toast=function(){}; }catch(_){}          /* 데모에선 안내 토스트 숨김 */
    hideLanding();
    try{ window.handleFiles([new File([CSV],'샘플_소재성과_데모.csv',{type:'text/csv'})]); }
    catch(e){ console.error('demo data load failed', e); }
    setTimeout(hideLanding,400); setTimeout(hideLanding,1200);
  }
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',boot); else boot();
})();
<\/script>`;

// ---- shared chrome (switcher bar) styles ----
const chromeCSS = `<style id="proposal-chrome">
  #proposalBar{position:fixed;left:50%;bottom:18px;transform:translateX(-50%);z-index:9000;
    display:flex;align-items:center;gap:6px;padding:6px 6px 6px 14px;border-radius:999px;
    background:rgba(28,26,20,.92);color:#F3F0E8;backdrop-filter:blur(8px);-webkit-backdrop-filter:blur(8px);
    box-shadow:0 12px 40px -10px rgba(0,0,0,.5),0 0 0 1px rgba(255,255,255,.07) inset;
    font-size:12.5px;font-weight:600;letter-spacing:-.01em;max-width:calc(100vw - 28px)}
  #proposalBar .pb-tag{display:inline-flex;align-items:center;gap:7px;color:#B7B2A5;font-size:11.5px;white-space:nowrap;padding-right:2px}
  #proposalBar .pb-tag b{color:#FF8A3D;font-weight:800}
  #proposalBar .pb-dot{width:6px;height:6px;border-radius:50%;background:#FF8A3D;box-shadow:0 0 0 3px rgba(255,138,61,.22)}
  #proposalBar a{display:inline-flex;align-items:center;gap:5px;text-decoration:none;color:#DEDACF;
    padding:7px 13px;border-radius:999px;font-weight:700;transition:background .13s,color .13s;white-space:nowrap}
  #proposalBar a:hover{background:rgba(255,255,255,.10);color:#fff}
  #proposalBar a.on{background:#FF6F0F;color:#fff}
  #proposalBar a.pb-home{color:#A7A296;font-weight:650}
  #proposalBar a.pb-home:hover{color:#fff}
  #proposalBar .pb-sep{width:1px;height:20px;background:rgba(255,255,255,.12);margin:0 2px}
  #proposalBar a:focus-visible{outline:2px solid #FF8A3D;outline-offset:2px}
  @media(max-width:620px){#proposalBar{bottom:10px;padding:5px;font-size:12px}#proposalBar .pb-tag{display:none}}
  @media (prefers-reduced-motion: reduce){#proposalBar{backdrop-filter:none}}
</style>`;

function barHTML(cur){
  const opt=(c)=>`<a href="${c.out}" class="pb-opt${c.id===cur.id?' on':''}"${c.id===cur.id?' aria-current="page"':''}>${c.label}</a>`;
  return `<div id="proposalBar" role="navigation" aria-label="UI 개선 시안 전환">
  <span class="pb-tag"><span class="pb-dot"></span><b>UI 시안</b> · 샘플 데이터</span>
  ${CONFIGS.map(opt).join('\n  ')}
  <span class="pb-sep"></span>
  <a href="../index.html" class="pb-home" title="비밀번호로 접속하는 실제 도구">실제 도구 →</a>
</div>`;
}

for (const cfg of CONFIGS) {
  const theme = readFileSync(join(here, cfg.theme), 'utf8');
  const themeTag = `<style id="proposal-theme">\n${theme}\n</style>`;
  let html = base;
  // mark <html> with theme class for optional scoping
  html = html.replace('<html lang="ko">', `<html lang="ko" class="${cfg.cls} proposal-demo">`);
  // fix relative asset paths (page now lives one dir deeper)
  html = html.replace(/href="favicon\.svg"/g, 'href="../favicon.svg"');
  // title
  html = html.replace(/<title>[^<]*<\/title>/, `<title>${cfg.title}</title>`);
  // inject theme + chrome just before </head>
  html = html.replace('</head>', `${themeTag}\n${chromeCSS}\n</head>`);
  // inject switcher + bootstrap just before </body>
  html = html.replace('</body>', `${barHTML(cfg)}\n${bootstrap}\n</body>`);
  writeFileSync(join(repo, 'proposals', cfg.out), html);
  console.log('built proposals/' + cfg.out + ' (' + html.length + ' bytes)');
}
console.log('done.');
