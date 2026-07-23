#!/usr/bin/env bash
# Localize Pretendard (the app's web font) for offline use.
# Downloads the dynamic-subset CSS + all its woff2 shards, then rewrites the CSS
# to point at the local copies. Output: fonts/pretendard.css + fonts/woff2/*.woff2
set -e
OUT="${1:-fonts}"
BASE="https://cdn.jsdelivr.net/gh/orioncactus/pretendard@v1.3.9/dist/web/variable"
CSSURL="$BASE/pretendardvariable-dynamic-subset.css"
mkdir -p "$OUT/woff2"
curl -sSfL "$CSSURL" -o "$OUT/pretendard.src.css"
grep -oE "url\(\.\./[^)]+\.woff2\)" "$OUT/pretendard.src.css" | sed -E 's/url\((.*)\)/\1/' | sort -u > "$OUT/_rel.txt"
python3 - "$OUT" "$CSSURL" <<'PY'
import sys, os, subprocess, urllib.parse, concurrent.futures as cf
out, base = sys.argv[1], sys.argv[2]
rels = [l.strip() for l in open(os.path.join(out, "_rel.txt")) if l.strip()]
def job(rel):
    absu = urllib.parse.urljoin(base, rel)
    dst = os.path.join(out, "woff2", os.path.basename(rel))
    if os.path.exists(dst) and os.path.getsize(dst) > 0: return "skip"
    for _ in range(3):
        r = subprocess.run(["curl", "-sSfL", "--max-time", "60", "-o", dst, absu])
        if r.returncode == 0 and os.path.getsize(dst) > 0: return "ok"
    return "FAIL " + os.path.basename(rel)
with cf.ThreadPoolExecutor(max_workers=16) as ex:
    print("fonts:", {r: sum(1 for x in ex.map(job, rels) if x == r) for r in ["ok", "skip"]})
PY
# rewrite CSS to local relative paths
sed -E 's#url\(\.\./\.\./\.\./packages/pretendard/dist/web/variable/woff2-dynamic-subset/([^)]+)\)#url(woff2/\1)#g' \
    "$OUT/pretendard.src.css" > "$OUT/pretendard.css"
rm -f "$OUT/pretendard.src.css" "$OUT/_rel.txt"
echo "done -> $OUT/pretendard.css + $OUT/woff2/*.woff2"
