import sys, subprocess, os, concurrent.futures as cf
tsv = sys.argv[1]
P = int(sys.argv[2]) if len(sys.argv) > 2 else 16
base = os.path.dirname(os.path.abspath(tsv))
jobs = []
for line in open(tsv):
    line = line.rstrip('\n')
    if not line:
        continue
    url, out = line.split('\t', 1)
    jobs.append((url, os.path.join(base, out)))

def dl(job):
    url, out = job
    if os.path.exists(out) and os.path.getsize(out) > 0:
        return ('skip', url, out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    for _ in range(3):
        r = subprocess.run(['curl', '-sS', '-L', '--max-time', '150',
                            '-A', 'Mozilla/5.0', '-o', out + '.part', url],
                           capture_output=True)
        if r.returncode == 0 and os.path.exists(out + '.part') and os.path.getsize(out + '.part') > 0:
            os.replace(out + '.part', out)
            return ('ok', url, out)
    if os.path.exists(out + '.part'):
        os.remove(out + '.part')
    return ('FAIL', url, out)

ok = skip = fail = 0
fails = []
with cf.ThreadPoolExecutor(max_workers=P) as ex:
    for st, url, out in ex.map(dl, jobs):
        if st == 'ok':
            ok += 1
        elif st == 'skip':
            skip += 1
        else:
            fail += 1
            fails.append(url)
name = os.path.basename(tsv)
print(f"[{name}] ok={ok} skip={skip} fail={fail} total={len(jobs)}")
if fails:
    with open(os.path.join(base, 'dl_fail_' + name + '.log'), 'w') as f:
        f.write('\n'.join(fails))
    for u in fails[:15]:
        print("  FAIL", u)
