<!--
  TEMPLATE: devbook-entry-template.md
  Purpose: A single Dev Book entry, the atomic unit that gets pasted into
  DEVBOOK-PB0X.md (one block per RD there). Use this standalone file when
  drafting an entry before it's merged into the project's Dev Book, or
  when a tool generates entries individually before aggregation.
-->

# Dev Book Entry

**RD ID:** RD-PB0X-012.03
<!-- The RD this entry documents. Must exist in the project's rd-template.yaml
     instances and be referenced from DEVBOOK-PB0X.md. -->

**Dev Book profile in effect:** <!-- Light | Standard | Heavy -->
<!-- Standard/Heavy require >=1 human-authored correction below; Heavy
     additionally requires the Root Cause section to be filled in. -->

---

## What AI Proposed

<!-- Describe, specifically, what the AI generated/implemented for this RD
     before any human correction. Be concrete — reference the actual
     approach/code pattern, not just "implemented the feature." -->

<!-- Example:
"AI implemented the point-redemption deduction as two separate database
calls: a SELECT to read the current balance, followed by an UPDATE to
write the new balance computed in application code." -->

REPLACE_ME

---

## The Human Correction Made

<!-- MUST be authored by a human, describing exactly what was changed and
     why. This is the field that makes the entry valid under Standard/
     Heavy profile — an empty or AI-authored version of this section does
     not satisfy the requirement. If truly zero correction was needed,
     write that explicitly and note it may indicate a rubber-stamp review
     risk (cross-reference CASE-STUDY.md metric) rather than leaving this
     blank. -->

<!-- Example:
"Replaced the two-step SELECT+UPDATE with a single atomic SQL statement:
UPDATE ledger SET balance = balance - :amount WHERE user_id = :uid AND
balance >= :amount, checking the affected-row count to detect
insufficient balance. This closes a race condition where two concurrent
redemptions could both read the same starting balance and cause the
ledger to go negative." -->

REPLACE_ME

**Correction author (human, required):** <!-- name -->

---

## Why / Root Cause (required if Dev Book profile = Heavy)

<!-- Explain the underlying reason the AI produced the flawed/incomplete
     output — not just what was wrong, but why the model tended toward
     that pattern. This is what turns a one-off fix into a reusable
     lesson (feeds into CASE-STUDY.md lessons-learned and can become a
     standing instruction for future RDs on similar modules). -->

<!-- Example:
"The model's default pattern for 'update a counter' problems is
app-level read-modify-write, because that's the most common pattern in
its training distribution for non-concurrent contexts. It doesn't
proactively reach for DB-level atomic guards unless the prompt
explicitly flags concurrency as a concern. Fix: add a standing
instruction for any RD touching MOD-PB0X-001 (Points Ledger, Layer 0)
to explicitly require atomic/concurrency-safe writes in the RD statement
itself." -->

REPLACE_ME
<!-- If profile is Light or Standard (not Heavy), write "N/A — root cause
     not required at this profile level" instead of leaving blank. -->

---

## Metadata

| Field | Value |
|---|---|
| Timestamp | <!-- YYYY-MM-DDTHH:MM --> |
| Gate reference | <!-- GATE-RD-PB0X-012.03-01 --> |
| Delegation level / leash at time of entry | <!-- e.g. L1 / A+ --> |
