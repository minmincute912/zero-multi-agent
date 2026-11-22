#!/usr/bin/env bash
# Print current free models so docker-services/inference-router/config.yaml can be refreshed by PR.
#   OpenRouter: public list, ids ending in ":free"
#   Cloudflare: its docs still list retired models, so ping each ID with a real call before adding it
set -euo pipefail
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

echo "== OpenRouter :free (id, context, tools?) =="
curl -fsS --max-time 20 https://openrouter.ai/api/v1/models \
  | jq -r '.data[] | select(.id | endswith(":free"))
           | [.id, .context_length, (if (.supported_parameters // []) | index("tools") then "tools" else "-" end)] | @tsv' \
  | sort -t$'\t' -k2 -nr

echo; echo "Cloudflare Workers AI models: https://developers.cloudflare.com/workers-ai/models/"
