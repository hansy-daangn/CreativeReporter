#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CreativeReporter 오프라인 미리보기 자산 다운로더
=================================================
인터넷이 되는 곳에서 이 스크립트를 한 번만 실행하면, 소재 미리보기(이미지·영상·
YouTube 썸네일) 약 1,525개를 assets/ 폴더로 내려받아 완전 오프라인 상태에서도
사이트가 온라인과 똑같이 작동합니다.

사용법:
    python3 fetch_assets.py

- 이미 받은 파일은 건너뜁니다(중간에 끊겨도 다시 실행하면 이어받음).
- 파이썬 3.6+ 표준 라이브러리만 사용합니다(추가 설치 불필요).
"""
import os, sys, ssl, time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
MANIFEST = os.path.join(HERE, "assets_manifest.tsv")
WORKERS = 12
UA = "Mozilla/5.0 (offline-fetch) CreativeReporter"

def load_jobs():
    jobs = []
    with open(MANIFEST, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or "\t" not in line:
                continue
            url, rel = line.split("\t", 1)
            jobs.append((url, os.path.join(HERE, rel)))
    return jobs

_ctx = ssl.create_default_context()
def fetch(job):
    url, out = job
    if os.path.exists(out) and os.path.getsize(out) > 0:
        return "skip"
    os.makedirs(os.path.dirname(out), exist_ok=True)
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60, context=_ctx) as r:
                data = r.read()
            if data:
                with open(out + ".part", "wb") as w:
                    w.write(data)
                os.replace(out + ".part", out)
                return "ok"
        except Exception:
            time.sleep(1 + attempt)
    try:
        if os.path.exists(out + ".part"):
            os.remove(out + ".part")
    except OSError:
        pass
    return "FAIL\t" + url

def main():
    if not os.path.exists(MANIFEST):
        print("assets_manifest.tsv 를 찾을 수 없습니다. 이 스크립트와 같은 폴더에 있어야 합니다.")
        sys.exit(1)
    jobs = load_jobs()
    total = len(jobs)
    print(f"미리보기 자산 {total}개를 내려받습니다 (assets/ 폴더). 인터넷 연결이 필요합니다...\n")
    ok = skip = fail = done = 0
    fails = []
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        for res in ex.map(fetch, jobs):
            done += 1
            if res == "ok":
                ok += 1
            elif res == "skip":
                skip += 1
            else:
                fail += 1
                fails.append(res.split("\t", 1)[1])
            if done % 50 == 0 or done == total:
                sys.stdout.write(f"\r  진행 {done}/{total}  (신규 {ok} · 건너뜀 {skip} · 실패 {fail})")
                sys.stdout.flush()
    print("\n")
    if fail:
        print(f"⚠ {fail}개를 못 받았습니다. 인터넷을 확인하고 다시 실행하면 이어받습니다.")
        with open(os.path.join(HERE, "fetch_failures.txt"), "w", encoding="utf-8") as f:
            f.write("\n".join(fails))
        print("  (실패 목록: fetch_failures.txt)")
    else:
        print("✅ 모든 자산을 받았습니다. 이제 인터넷 없이 index.html 을 열어도 똑같이 작동합니다.")

if __name__ == "__main__":
    main()
