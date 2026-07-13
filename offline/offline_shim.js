/* ===== CreativeReporter OFFLINE shim =====
   Replaces all Supabase RPC network calls with a local dispatcher over the embedded
   OFFLINE_DB snapshot, and resolves media/font/YouTube references to local files.
   Loaded (with sha256.js + data.js + assets/manifest.js) BEFORE the app's main <script>.
   Password login is replicated exactly: pw_hash = sha256(pw) hex, legacy '0715' = viewer. */
(function () {
  var DB = window.OFFLINE_DB || (window.OFFLINE_DB = { weekly: [], kv: {}, users: [], marks: [], status: {} });
  var AS = window.OFFLINE_ASSETS || (window.OFFLINE_ASSETS = {});
  var YT = window.OFFLINE_YT || (window.OFFLINE_YT = {});
  window.OFFLINE = true;

  function hex(pw) { return window.sha256hex(pw == null ? "" : String(pw)); }
  function userByPw(pw) {
    if (pw == null) return null;
    var h = hex(pw);
    for (var i = 0; i < DB.users.length; i++) if (DB.users[i].pw_hash === h) return DB.users[i];
    return null;
  }
  function checkPw(pw) {
    if (pw === "0715") return true;
    var u = userByPw(pw);
    return !!(u && u.status === "승인됨");
  }
  function unameOf(pw) { var u = userByPw(pw); return (u && u.status === "승인됨") ? u.name : null; }
  function pwErr() { var e = new Error("invalid password"); e.status = 400; return e; }

  /* ---- lightweight persistence for interactive edits (marks + kv overrides) ---- */
  var LSK = "cr_offline_delta";
  function loadDelta() { try { return JSON.parse(localStorage.getItem(LSK) || "{}") || {}; } catch (e) { return {}; } }
  function saveDelta(d) { try { localStorage.setItem(LSK, JSON.stringify(d)); } catch (e) {} }
  (function applyDelta() {
    var d = loadDelta();
    if (d.marks) DB.marks = d.marks;
    if (d.kv) for (var k in d.kv) if (d.kv[k]) DB.kv[k] = d.kv[k];
  })();
  function persist() {
    saveDelta({
      marks: DB.marks,
      kv: { nameovr: DB.kv.nameovr, svcovr: DB.kv.svcovr, gmap: DB.kv.gmap, ginfo: DB.kv.ginfo, ocr: DB.kv.ocr, ytt: DB.kv.ytt }
    });
  }
  function setMark(ch, ad, user, kind, on) {
    var found = -1;
    for (var i = 0; i < DB.marks.length; i++) {
      var m = DB.marks[i];
      if (m.c === ch && m.a === ad && m.n === user && m.k === kind) { found = i; break; }
    }
    if (on) { if (found < 0) DB.marks.push({ c: ch, a: ad, n: user, k: kind }); }
    else { if (found >= 0) DB.marks.splice(found, 1); }
  }
  function mergeKv(key, val) {
    var cur = DB.kv[key];
    if (!cur || typeof cur !== "object") { cur = {}; DB.kv[key] = cur; }
    for (var k in val) cur[k] = val[k];
  }
  function mergeMapDelete(key, map) { /* '' value = delete key */
    var cur = DB.kv[key];
    if (!cur || typeof cur !== "object") { cur = {}; DB.kv[key] = cur; }
    for (var k in map) { if (map[k] === "") delete cur[k]; else cur[k] = map[k]; }
  }

  /* ---- the offline RPC dispatcher (mirrors the Supabase SECURITY DEFINER functions) ---- */
  window.__offlineRpc = function (fn, body) {
    body = body || {};
    return new Promise(function (resolve, reject) {
      try {
        switch (fn) {
          case "cr_login": {
            var pw = body.p_pw;
            if (pw === "0715") { resolve({ found: true, viewer: true, role: "viewer", status: "승인됨" }); return; }
            var u = userByPw(pw);
            if (!u) { resolve({ found: false }); return; }
            resolve({ found: true, name: u.name, status: u.status, role: u.role, viewer: false });
            return;
          }
          case "cr_load":
            if (!checkPw(body.pw)) { reject(pwErr()); return; }
            resolve(DB.weekly); return;
          case "cr_status":
            if (!checkPw(body.pw)) { reject(pwErr()); return; }
            resolve(DB.status || {}); return;
          case "cr_kv_get":
            if (!checkPw(body.pw)) { reject(pwErr()); return; }
            resolve(DB.kv[body.key] !== undefined ? DB.kv[body.key] : null); return;
          case "cr_marks_load": {
            if (!checkPw(body.pw)) { reject(pwErr()); return; }
            var un = unameOf(body.pw), mine = [], fav = [];
            for (var i = 0; i < DB.marks.length; i++) {
              var m = DB.marks[i];
              if (m.k === "mine") mine.push({ c: m.c, a: m.a, n: m.n });
              else if (m.k === "fav" && m.n === un) fav.push({ c: m.c, a: m.a });
            }
            resolve({ me: un, mine: mine, fav: fav }); return;
          }
          case "cr_register": {
            var name = (body.p_name || "").trim(), rpw = body.p_pw || "";
            if (!/^[A-Za-z][A-Za-z0-9]{1,23}$/.test(name)) { reject(new Error("name_invalid")); return; }
            if (rpw === "0715") { reject(new Error("pw_reserved")); return; }
            if (!(rpw && rpw.length >= 4)) { reject(new Error("pw_weak")); return; }
            var rh = hex(rpw);
            for (var j = 0; j < DB.users.length; j++) {
              if (DB.users[j].name.toLowerCase() === name.toLowerCase()) { reject(new Error("name_taken")); return; }
              if (DB.users[j].pw_hash === rh) { reject(new Error("pw_taken")); return; }
            }
            DB.users.push({ name: name, status: "신청함", role: "viewer", pw_hash: rh });
            resolve({ ok: true }); return;
          }
          /* ---- writes (in-memory + persisted) ---- */
          case "cr_save": {
            if (!checkPw(body.pw)) { reject(pwErr()); return; }
            var rows = body.rows || [], seen = {};
            for (var s = 0; s < DB.weekly.length; s++) { var rr = DB.weekly[s]; seen[rr.channel + "|" + rr.week_start + "|" + rr.ad_name] = 1; }
            var ins = 0;
            for (var r = 0; r < rows.length; r++) {
              var row = rows[r], key = row.channel + "|" + row.week_start + "|" + row.ad_name;
              if (seen[key]) continue; seen[key] = 1;
              DB.weekly.push({ channel: row.channel, week_start: row.week_start, ad_name: row.ad_name, payload: row.payload || {} });
              ins++;
            }
            resolve({ inserted: ins, total: rows.length }); return;
          }
          case "cr_kv_merge":
            mergeKv(body.key, body.val || {}); persist(); resolve({ ok: true }); return;
          case "cr_names_merge":
            mergeMapDelete("nameovr", body.p_map || {}); persist(); resolve({ ok: true }); return;
          case "cr_svc_merge":
            mergeMapDelete("svcovr", body.p_map || {}); persist(); resolve({ ok: true }); return;
          case "cr_mark_set": {
            var un1 = unameOf(body.pw);
            if (!un1) { reject(new Error("no user")); return; }
            setMark(body.p_channel, body.p_ad, un1, body.p_kind, body.p_on); persist(); resolve({ ok: true }); return;
          }
          case "cr_mark_set_many": {
            var un2 = unameOf(body.pw);
            if (!un2) { reject(new Error("no user")); return; }
            var ads = body.p_ads || [];
            for (var a = 0; a < ads.length; a++) setMark(body.p_channel, ads[a], un2, body.p_kind, body.p_on);
            persist(); resolve({ ok: true }); return;
          }
          case "cr_admin_mark_set":
            setMark(body.p_channel, body.p_ad, body.p_user, body.p_kind, body.p_on); persist(); resolve({ ok: true }); return;
          default:
            resolve({ ok: true }); return;
        }
      } catch (e) { reject(e); }
    });
  };

  /* ---- media resolution helpers ---- */
  window.__vsrc = function (u) { /* video src -> local file if we have it */
    if (u == null) return "";
    var m = AS[u];
    if (m) return m;
    return /^https?:\/\//i.test(String(u)) ? u : "";
  };
  window.__ytThumb = function (id) { /* local YouTube poster jpg */
    return AS["https://img.youtube.com/vi/" + id + "/hqdefault.jpg"] || YT[id] || ("assets/yt/" + id + ".jpg");
  };
})();
