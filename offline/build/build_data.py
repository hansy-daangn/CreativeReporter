import json, os
R = "_raw"
def load(n): return json.load(open(os.path.join(R, n)))
weekly = load("weekly.json")
kv = {k: load(f"kv_{k}.json") for k in ["gmap","ginfo","ocr","ytt","nameovr","svcovr"]}
users = load("users.json")
marks = load("marks.json")
status = load("status.json")
db = {"weekly": weekly, "kv": kv, "users": users, "marks": marks, "status": status}
with open("data.js", "w") as f:
    f.write("/* CreativeReporter offline data snapshot — generated. Do NOT commit to a public repo. */\n")
    f.write("window.OFFLINE_DB=")
    json.dump(db, f, ensure_ascii=False, separators=(',', ':'))
    f.write(";\n")
print("weekly rows:", len(weekly))
print("kv keys:", {k: (len(v) if isinstance(v, (dict, list)) else type(v).__name__) for k, v in kv.items()})
print("users:", len(users), "marks:", len(marks))
print("data.js size:", os.path.getsize("data.js"))
