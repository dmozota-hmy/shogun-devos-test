---
description: Ejecuta el ciclo completo del AI-DevOS LCISS (orquestación determinista del pipeline: backlog → contexto → despacho → revisión → registro).
agent: orchestrator
---

Ejecuta el ciclo de orquestación del AI-DevOS LCISS con enforcement.

Trabajo solicitado: $ARGUMENTS

Antes de despachar, ejecuta `Test-LcissConfig.ps1`. Para una tarea concreta, inicia el ciclo con `Invoke-LcissPipeline.ps1 -Action Start -TaskId <id>`. Mantén un único subagente activo, exige el contrato JSON LCISS de cada resultado, valídalo con `Test-AgentOutput.ps1` y persístelo con `Invoke-LcissPipeline.ps1 -Action RecordOutput`. Ejecuta `Invoke-QualityGate.ps1` antes del reviewer. Nunca avances si falla una validación, un gate o un contrato.

Al terminar, usa `Invoke-LcissPipeline.ps1 -Action Finish -Outcome <completed|blocked|failed|escalated>` y entrega el resumen del ciclo: tarea, veredicto, estado, evidencia de calidad y learning log.
