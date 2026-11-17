#!/usr/bin/env bash
# PreToolUse (Bash): block `git commit` when forbidden files are staged (or would be staged by
# `git add` / `commit -a` in the same command). Exit 2 = block, stderr goes to Claude.
cmd=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)
case "$cmd" in *"git commit"*) ;; *) exit 0 ;; esac

# Forbidden: .env / .env.* (except .env.example|sample|template), *.sqlite, *.sqlite3, browser-profiles/
bad() {
  grep -E '(^|/)\.env(\.[^/]+)?$|\.sqlite3?$|(^|/)browser-profiles(/|$)' \
    | grep -Ev '(^|/)\.env\.(example|sample|template)$'
}

hits=$(git diff --cached --name-only 2>/dev/null | bad)
# Same command also stages things: check what the tree would add (non-ignored only).
case "$cmd" in
  *"git add"*|*"commit -a"*|*"commit --all"*)
    hits="$hits"$'\n'$( { git ls-files -m -o --exclude-standard; } 2>/dev/null | bad)
    # `git add -f <path>` can bypass .gitignore, so also scan the command text.
    hits="$hits"$'\n'$(printf '%s\n' "$cmd" | tr ' ;&|' '\n' | bad) ;;
esac
hits=$(printf '%s\n' "$hits" | sed '/^$/d' | sort -u)

if [ -n "$hits" ]; then
  echo "BLOCKED: refusing to commit secret/local-state files:" >&2
  printf '  %s\n' $hits >&2
  echo "Unstage them (git restore --staged <file>) and make sure .gitignore covers them." >&2
  exit 2
fi
exit 0
