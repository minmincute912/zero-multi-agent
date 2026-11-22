#!/usr/bin/env bash
# Print current free models so docker-services/inference-router/config.yaml can be refreshed by PR.
#   OpenRouter: public list, ids ending in ":free"
#   Nous Portal: public catalog, ids ending in ":free" with price 0 (NOUS_API_KEY is needed only to call them)
#   Cloudflare: see the docs page (the model list needs no key)
set -euo pipefail
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

echo "== OpenRouter :free (id, context, tools?) =="
curl -fsS --max-time 20 https://openrouter.ai/api/v1/models \
  | jq -r '.data[] | select(.id | endswith(":free"))
           | [.id, .context_length, (if (.supported_parameters // []) | index("tools") then "tools" else "-" end)] | @tsv' \
  | sort -t$'\t' -k2 -nr

echo; echo "== Nous Portal :free (id, context, tools?) =="
curl -fsS --max-time 20 https://inference-api.nousresearch.com/v1/models \
  | jq -r '.data[] | select((.id | endswith(":free")) and ((.pricing.prompt | tonumber) == 0))
           | [.id, .context_length, (if (.supported_parameters // []) | index("tools") then "tools" else "-" end)] | @tsv' \
  | sort -t$'\t' -k2 -nr

echo; echo "Cloudflare Workers AI models: https://developers.cloudflare.com/workers-ai/models/"
