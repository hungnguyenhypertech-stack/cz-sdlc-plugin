# Security Notes

**NOT APPLICABLE as of 1.0.26.** OmniRoute support was removed from this plugin (see
`.claude-plugin/plugin.json` notes) — `config/model-routing.yaml` is deleted, the
`model-gateway`/`adapter` concept described below was never wired past `adapter: direct`, and
model selection per role is now just the static `model:` field in each `agents/*.md`. Everything
below is kept as historical record of the security posture that would have been required *if*
OmniRoute wiring had gone ahead; none of it applies to the current plugin and none of these
caveats need to be re-checked before use.

---

This document exists because two of these issues (the OmniRoute disable-list and the ToS
risk) are the kind of thing that fails an FPT security review on sight if not handled before
ship, not after. Read this before configuring the model-gateway adapter or presenting any
ROI/cost figures from telemetry.

## OmniRoute Disable-List — Non-Negotiable

CZ-Harness uses OmniRoute as the reference `model-gateway` adapter (see `CASAN-MAPPING.md`,
Tầng 2). OmniRoute ships with features that are appropriate for individual/hobbyist use but
are **not acceptable in an FPT-governed deployment.** Both of the following MUST be disabled
before this adapter is used on any FPT asset:

- **TLS fingerprint stealth (JA3/JA4 spoofing).** OmniRoute can disguise its outbound TLS
  fingerprint to look like ordinary browser traffic rather than API-client traffic. This exists
  to route around provider-side bot detection. In an enterprise security review this reads as
  traffic obfuscation with no legitimate justification — disable it unconditionally.
- **Transparent MITM decryption.** Any mode where OmniRoute inserts itself as a man-in-the-
  middle to inspect or rewrite traffic transparently must be off. This is the kind of behavior
  a security review will flag immediately and correctly, regardless of the (possibly
  legitimate) debugging reason it exists for.

**Required configuration posture:**

- Self-host the OmniRoute adapter (do not use a third-party-hosted instance) with both of the
  above features explicitly disabled in config, not merely left at default.
- Restrict outbound routing to an **approved-provider allow-list** — do not let OmniRoute route
  to arbitrary providers it happens to support.
- Document the disabled-feature configuration as part of the adapter's own setup docs, so a
  future reviewer can verify the posture without having to re-derive it from OmniRoute's full
  feature set.

## Free-Tier ToS Risk

OmniRoute's own README flags roughly 15 providers as "ToS-flagged" — meaning routing traffic
through them may violate that provider's terms of service (commonly because the route relies on
a personal/free-tier credential path the provider's ToS doesn't intend for this kind of
automated, third-party-proxied use).

**Policy: approved-provider allow-list only. No ToS-flagged tier may be used for an FPT
asset, ever, regardless of cost savings.** This is not a risk that gets weighed against
convenience — using a ToS-flagged route on company work is a compliance exposure, not a
technical tradeoff. When configuring the model-gateway adapter for a real project, the
allow-list must be checked against OmniRoute's current ToS-flagged list at setup time and at
each 6-month CASAN re-sync (see `CASAN-MAPPING.md` header), since providers can move on/off
that list between OmniRoute releases.

## Cost Accounting Caveat

OmniRoute's analytics report **$0** for any request routed through a subscription or
coding-plan provider (i.e., a provider where you pay a flat monthly fee rather than metered
per-token cost) — because from OmniRoute's point of view, no incremental spend occurred.

This is technically true and operationally misleading. If telemetry-derived ROI figures
(`telemetry/events.jsonl` → `deliverables/WEEKLY-PB0X.md` / `deliverables/CASE-STUDY.md`) are built naively off
OmniRoute's reported cost, a project that happens to route heavily through subscription-tier
providers will look artificially cheap — "artificially" in a direction that flatters the
project's own ROI story, which is exactly the failure mode to be suspicious of.

**Required practice:** cost reporting must separate metered spend (real, reportable per-token
cost) from subscription-covered usage (real cost, just not visible per-request) and note the
subscription's flat cost separately, rather than letting subscription usage silently read as
free in any report. Any case study or weekly report that cites a cost or ROI figure must state
which portion, if any, is subscription-covered.

## Secrets Policy

- **Deny-list enforcement** via the `guard-secrets` hook: writes matching known credential
  patterns (API keys, private key blocks, connection strings with embedded credentials, etc.)
  are blocked at write time, not caught later in review.
- **No hardcoded credentials**, anywhere in generated code or config, under any profile. This
  is not a Light/Standard/Heavy-dependent relaxation — it holds unconditionally.
- **Hazard paths auto-escalate regardless of declared module or profile.** The following path
  patterns, defined in `gates.yaml`, trigger mandatory security review and elevated gate
  scrutiny no matter what module the RD claims to belong to or which profile the project runs
  under:

  ```
  auth/
  permissions/
  migrations/
  *secret*
  payment/
  pii/
  .github/workflows/
  ```

  An RD that touches any of these paths cannot use Light profile's security-review skip, and
  cannot be mis-declared into a module that would otherwise avoid this scrutiny — the hazard
  detector matches on actual file paths touched, not on the RD's self-reported module.
