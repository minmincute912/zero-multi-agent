---
description: Scaffold a new agentskills.io skill in hermes-core/skills/
argument-hint: <skill-name> <one-line purpose>
---

Create skill `$ARGUMENTS` in `hermes-core/skills/`.

1. Name: lowercase letters, digits and hyphens only, and it must equal the directory name. Stop if the directory exists.
2. Read `hermes-core/skills/skill-creator/SKILL.md` and follow its template.
3. Write `hermes-core/skills/<name>/SKILL.md` with frontmatter `name`, `description` (says what it does AND when to use it, under 1024 chars), then sections: When to use, Procedure, Pitfalls, Verification.
4. Keep it under about 150 lines. Put long material in `references/`, scripts in `scripts/`.
5. No secrets, no invented model IDs, no undated quota numbers.
6. Report the path. Do not commit; `/ship` does that.
