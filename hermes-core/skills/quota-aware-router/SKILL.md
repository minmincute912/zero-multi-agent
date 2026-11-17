---
name: quota-aware-router
description: Choose which free-tier LLM provider to use for each task so inference stays at $0. Light tasks go to Cloudflare Workers AI; heavy tasks go to OpenRouter or Nous Portal models marked ":free". Use before delegating work to a model, when a provider returns 429/quota errors, or when planning a batch of LLM calls.
---

# Quota-Aware Router

Goal: spend $0. Pick the cheapest lane that can do the job, and never touch a paid model unless the user approves.

## Tiers
| Tier | Tasks | Lane |
|---|---|---|
| Light | classify, tag, route, short summary, extract fields, yes/no checks | Cloudflare Workers AI (small instruct model) |
| Heavy | long-context reading, multi-step reasoning, tool-calling chains, drafting | OpenRouter `:free` model, or Nous Portal free model |
| Judgment | irreversible actions, money, security, ambiguous goals | Stop. Ask the user; a paid model is a manual choice |

Pick concrete model IDs from each provider's current model list at call time. Do not rely on remembered IDs.

## Procedure
1. Classify the task into a tier. When unsure, start one tier lighter and escalate on failure.
2. Check remaining quota for the lane before a batch (provider dashboard or API). Estimate cost: calls x tokens.
3. Run the call. Validate the output (format, required fields). A small model failing validation twice means escalate one tier.
4. On 429 or quota exhausted: do NOT retry in a tight loop. Back off, then fall to the next free lane in the same tier. If every free lane is exhausted, queue the task for after the reset or ask the user.
5. Only models whose ID ends in `:free` (or are listed as free by the provider) may be used. Refuse any model that would bill.
6. Log each call: lane, model, tokens, result, error. Keep the log outside git.

## Quota facts (unverified, from a public article, checked 2026-11-14)
- Cloudflare Workers AI free tier: about 10,000 neurons/day, resets 00:00 UTC.
- OpenRouter `:free` models: rate-limited, availability varies per model.
- Nous Portal free plan: free models only; paid models are blocked without credit.
- AMD Token Lab: trial, expires about 2026-12-14. Evaluation only.
Re-check these at the provider before relying on them. Update this section with a new date when you do.

## Pitfalls
- Free models change names or disappear. Re-list models periodically.
- Free tiers may log or train on prompts. Never send secrets or personal data.
- Unattended loops on a lane that can bill are the main way to lose money. Cap iterations.

## Verification
- Every call in the log used a free lane.
- No retry storm: no more than 3 attempts per task per lane.
