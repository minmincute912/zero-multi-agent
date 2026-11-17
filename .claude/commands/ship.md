---
description: Validate, then commit current changes (no push unless asked)
argument-hint: [commit message]
---

Ship the current changes.

1. `git status --short` and `git diff --stat`. Stop if there is nothing to commit.
2. Validate every changed file: `.py` with `python3 -m py_compile`, `.yaml`/`.yml` with `yaml.safe_load`, `.sh` with `bash -n`, `.json` with `python3 -m json.tool`. Stop on any failure.
3. Stage by explicit path, never `git add -A`. Never stage `.env`, `*.sqlite`, `browser-profiles/` (`.env.example` is fine). Stop and report if any appear.
4. Commit with `$ARGUMENTS` as the message, or write a Conventional Commits message from the diff if empty.
5. Do not push. Print the commit hash and `git log --oneline -1`. Ask before pushing.
