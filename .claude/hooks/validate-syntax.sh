#!/usr/bin/env bash
# PostToolUse (Write|Edit): validate Python/YAML/Bash syntax of the edited file.
# Exit 2 = syntax error (stderr is fed back to Claude). Missing validator = warn, never block.
f=$(python3 -c 'import json,sys; d=json.load(sys.stdin); ti=d.get("tool_input",{}); print(ti.get("file_path",""))' 2>/dev/null)
[ -n "$f" ] && [ -f "$f" ] || exit 0

case "$f" in
  *.py)
    # ast.parse validates without writing __pycache__
    out=$(python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])' "$f" 2>&1) \
      || { echo "Python syntax error in $f:" >&2; echo "$out" >&2; exit 2; } ;;
  *.yaml|*.yml)
    python3 -c 'import yaml' 2>/dev/null || { echo "warn: PyYAML missing, skipped $f" >&2; exit 0; }
    out=$(python3 -c 'import sys,yaml; list(yaml.safe_load_all(open(sys.argv[1])))' "$f" 2>&1) \
      || { echo "YAML syntax error in $f:" >&2; echo "$out" >&2; exit 2; } ;;
  *.sh)
    out=$(bash -n "$f" 2>&1) || { echo "Bash syntax error in $f:" >&2; echo "$out" >&2; exit 2; } ;;
esac
exit 0
