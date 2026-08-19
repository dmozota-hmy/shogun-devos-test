# ADR 0001: LCISS Pipeline Enforcement v1

**Status:** Accepted
**Date:** 2026-08-19

## Decision

LCISS uses versioned JSON contracts, persisted runtime state, a directory lock,
and PowerShell wrappers to enforce its sequential pipeline. The implementation
uses no external dependencies and is compatible with Windows PowerShell 7+.

## Consequences

- Only `orchestrator` can dispatch subagents.
- Every agent result is validated before a state transition.
- Test, lint, and build must pass or be explicitly marked not applicable.
- Runtime data under `.lciss/` is append-only or atomically replaced and is
  excluded from Git.
- A stale lock is never removed automatically; recovery requires an explicit
  operator action.
