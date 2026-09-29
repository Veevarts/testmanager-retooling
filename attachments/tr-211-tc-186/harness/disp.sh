#!/bin/zsh
# uso: disp.sh <etiqueta> <accountId>  -> dispatch account.renewal_window_entered (days=90) y guarda la respuesta
S=$(cd "$(dirname "$0")" && pwd)
T=$(date -u +%H:%M:%S)
curl -s -X POST localhost:4311/api/dispatch -H 'content-type: application/json' -d "{\"catalogKey\":\"account.renewal_window_entered\",\"accountIds\":[\"$2\"],\"payload\":{\"event.days\":90}}" > $S/dev3/$1.json
python3 - "$S/dev3/$1.json" "$1" "$T" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
a=d.get("accounts",[{}])[0]
print(sys.argv[2], "enviado", sys.argv[3], "| status", a.get("status"), "| evaluationRunId", str(d.get("evaluationRunId"))[:8], "| err", d.get("error"))
PY
