#!/usr/bin/env bash
# Print current free models so docker-services/inference-router/config.yaml can be refreshed by PR.
#   OpenRouter: public list, ids ending in ":free"
#   Nous Portal: needs NOUS_API_KEY; the catalog is not filtered here, pick the ones the portal marks free
#   Cloudflare: see the docs page (the model list needs no key)
set -euo pipefail
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

echo "== OpenRouter :free (id, context, tools?) =="
curl -fsS --max-time 20 https://openrouter.ai/api/v1/models \
  | jq -r '.data[] | select(.id | endswith(":free"))
           | [.id, .context_length, (if (.supported_parameters // []) | index("tools") then "tools" else "-" end)] | @tsv' \
  | sort -t$'\t' -k2 -nr

if [ -n "${NOUS_API_KEY:-}" ]; then
  echo; echo "== Nous Portal models =="
  curl -fsS --max-time 20 -H "Authorization: Bearer $NOUS_API_KEY" https://inference-api.nousresearch.com/v1/models \
    | jq -r '.data[].id' | sort
else
  echo; echo "(set NOUS_API_KEY to list Nous Portal models)"
fi

echo; echo "Cloudflare Workers AI models: https://developers.cloudflare.com/workers-ai/models/"
