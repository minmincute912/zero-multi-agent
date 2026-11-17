---
name: skill-creator
description: Package a repeatable workflow you just completed into a new agentskills.io SKILL.md and commit it to Git. Use when a procedure worked, will recur, and should be reusable, or when the user says "save this as a skill".
---

# Skill Creator

## When to use
- A multi-step procedure succeeded and is likely to repeat.
- The user asks to save, package or remember a workflow.
- Do NOT create a skill for one-off tasks, or one that duplicates an existing skill (search first and update that one instead).

## Procedure
1. **Search existing skills** (`hermes skills list`, or look in `skills/`). Update rather than duplicate.
2. **Name it**: lowercase letters, digits, hyphens. The directory name equals frontmatter `name`.
3. **Write `${HERMES_CORE_DIR}/skills/<name>/SKILL.md`** (that is the Git-tracked directory; `skills.create_dir` points there. If `HERMES_CORE_DIR` is unset, stop and tell the user, because the skill would land in the untracked `~/.hermes/skills/`):
   ```
   ---
   name: <name>
   description: <what it does AND when to use it, under 1024 chars>
   ---
   # Title
   ## When to use
   ## Procedure        (numbered, imperative, each step checkable)
   ## Pitfalls         (what failed or surprised you)
   ## Verification     (how to confirm it worked)
   ```
4. **Keep it small**: under about 150 lines. Move long reference material to `references/`, executable helpers to `scripts/`.
5. **Strip before saving**: no API keys, tokens, cookies, personal data, absolute home paths. Reference env var names only. Quota numbers get a date and "unverified" unless just checked.
6. **Test it once**: follow the file literally as a fresh reader. Fix any step that needs knowledge the file does not contain.
7. **Commit** in the repo that holds `${HERMES_CORE_DIR}`:
   ```
   git -C "$HERMES_CORE_DIR" add skills/<name>
   git -C "$HERMES_CORE_DIR" commit -m "feat(skill): add <name>"
   ```
   Stage by explicit path only. Do not push unless the user asked.

## Pitfalls
- A `name` that differs from the directory name makes the skill unloadable or ambiguous.
- Vague descriptions mean the skill never triggers. Say when to use it.
- Never `git add -A`: it can sweep in `.env`, `*.sqlite` or `browser-profiles/`.

## Verification
- `head -5 skills/<name>/SKILL.md` shows matching `name` and a `description`.
- `git -C "$HERMES_CORE_DIR" log --oneline -1` shows the new commit and `git -C "$HERMES_CORE_DIR" status --short` is clean.
