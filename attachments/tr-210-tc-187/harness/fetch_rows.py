"""Lee (solo SELECT) las filas de product_metrics de la cuenta QA en dev via Data API."""
import json, subprocess, re, pathlib, sys
T = pathlib.Path.home() / ".claude/skills/csm-playbook-qa/generator/src/targets.ts"
src = T.read_text()
ARN = re.search(r"DEV_CLUSTER_ARN =\s*'([^']+)'", src) or re.search(r"(arn:aws:rds:[^'\"\s]+)", src)
ARN = ARN.group(1)
SEC = re.search(r"DEV_SECRET_ARN =\s*'([^']+)'", src).group(1)
ACC = sys.argv[1]
OUT = pathlib.Path(sys.argv[2])
def q(sql):
    r = subprocess.run(["aws", "rds-data", "execute-statement", "--profile", "veevart-tooling", "--region", "us-east-1",
        "--resource-arn", ARN, "--secret-arn", SEC, "--database", "csm_os", "--sql", sql,
        "--include-result-metadata", "--output", "json"], capture_output=True, text=True, check=True)
    d = json.loads(r.stdout)
    cols = [c["name"] for c in d["columnMetadata"]]
    return [{c: list(v.values())[0] if not v.get("isNull") else None for c, v in zip(cols, rec)} for rec in d["records"]]
assert re.fullmatch(r"[0-9a-f-]{36}", ACC)
raw = q(f"""SELECT metric_code, metric_name, unit, period_key, period_start::text AS period_start, value::text AS value,
  synced_at::text AS synced_at, dimension_key, is_primary, period_type, source_run_id
  FROM csm_os.product_metrics WHERE account_id = '{ACC}'::uuid ORDER BY metric_code, period_start""")
checks = q(f"""SELECT count(*) AS n, count(DISTINCT (metric_code, date_trunc('month', period_start))) AS uniq,
  count(*) FILTER (WHERE period_start IS NULL) AS nullstart, count(*) FILTER (WHERE value = 0) AS zeros,
  (date_trunc('month', now() AT TIME ZONE 'UTC')::date - INTERVAL '36 months')::date::text AS window_start
  FROM csm_os.product_metrics WHERE account_id = '{ACC}'::uuid AND is_primary AND period_type = 'monthly'""")
OUT.write_text(json.dumps({"rows": raw, "checks": checks[0]}, indent=1))
print(checks[0], len(raw))
