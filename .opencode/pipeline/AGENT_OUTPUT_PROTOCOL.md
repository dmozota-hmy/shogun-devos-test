# LCISS Agent Output Protocol v1

Every dispatched agent returns one JSON object in a fenced `json` block. The
orchestrator is the only role allowed to persist it through
`.opencode/pipeline/scripts/Invoke-LcissPipeline.ps1`.

```json
{
  "contractVersion": "1.0",
  "runId": "<run-id from .lciss/state/current.json>",
  "taskId": "<backlog task id>",
  "agent": "developer",
  "status": "succeeded",
  "summary": "Implemented the requested change.",
  "artifacts": ["src/example.ts", "tests/example.test.ts"],
  "qualityEvidence": {
    "tests": "not-run",
    "lint": "not-run",
    "build": "not-run"
  },
  "next": "quality-gate",
  "issues": [],
  "timestampUtc": "2026-08-19T00:00:00Z"
}
```

Rules:

- Never declare `succeeded` without concrete artifacts or an explicit reason
  why no artifact applies.
- `reviewer` must add `reviewVerdict`: `APROBADO`, `CAMBIOS REQUERIDOS`, or
  `RECHAZADO`.
- A subagent never writes `.lciss/state`, `.lciss/lock`, or `.lciss/outputs`.
- A subagent never delegates. It asks `orchestrator` to request another role.
- The orchestrator rejects malformed output, output for another run/task, and
  any transition not allowed by `pipeline.json`.
