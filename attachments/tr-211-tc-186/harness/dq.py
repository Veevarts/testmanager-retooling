"""SELECT de solo lectura contra la base de dev via Data API. Uso: dq.py "<sql>" """
import json, subprocess, re, pathlib, sys
src = (pathlib.Path.home() / ".claude/skills/csm-playbook-qa/generator/src/targets.ts").read_text()
ARN = re.search(r"(arn:aws:rds:[^'\"\s]+)", src).group(1)  # el unico cluster que admite el generador: dev
SEC = re.search(r"DEV_SECRET_ARN =\s*'([^']+)'", src).group(1)
sql = sys.argv[1]
assert re.match(r"^\s*(SELECT|WITH)\b", sql, re.I) and not re.search(r"\b(INSERT|UPDATE|DELETE|DROP|ALTER|TRUNCATE|CREATE|GRANT)\b", sql, re.I), "solo SELECT"
r = subprocess.run(["aws", "rds-data", "execute-statement", "--profile", "veevart-tooling", "--region", "us-east-1",
    "--resource-arn", ARN, "--secret-arn", SEC, "--database", "csm_os", "--sql", sql,
    "--include-result-metadata", "--output", "json"], capture_output=True, text=True)
if r.returncode: print(r.stderr[-800:]); sys.exit(1)
d = json.loads(r.stdout); cols = [c["name"] for c in d["columnMetadata"]]
print(" | ".join(cols))
for rec in d["records"]:
    print(" | ".join("" if v.get("isNull") else str(list(v.values())[0]) for v in rec))
