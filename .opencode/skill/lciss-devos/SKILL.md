---
name: lciss-devos
description: Arquitectura multi-agente del AI-DevOS de LCISS. Define los 7 agentes (orchestrator, architect, planner, developer, reviewer, refactor, knowledge), sus roles, el flujo de colaboración determinista y las reglas globales del pipeline. WHEN: AI-DevOS, devos, pipeline, backlog, learning log, orquestar agentes, despachar tarea, revisar código, deuda técnica, refactor, memoria del sistema, ciclo de desarrollo autónomo.
---

# LCISS — Arquitectura Multi-Agente

**Fecha:** 2026-03-09
**Estado:** Definido

---

## Visión General

El AI-DevOS de LCISS opera mediante un sistema de **7 agentes especializados** que colaboran de forma determinista para ejecutar el ciclo completo de desarrollo autónomo: análisis → planificación → implementación → revisión → evolución.

Cada agente tiene un rol único, inputs/outputs definidos y reglas de colaboración claras. La orquestación es **secuencial y determinista** — no hay decisiones no trazables.

---

## Principios del Sistema Multi-Agente

1. **Determinismo:** misma entrada → misma secuencia de acciones.
2. **Trazabilidad:** cada decisión de agente queda registrada en el learning log.
3. **Fallo seguro:** si un agente falla, el pipeline se detiene — nunca avanza con estado corrupto.
4. **Single responsibility:** cada agente hace exactamente una cosa bien.
5. **Composabilidad:** los agentes se combinan en pipelines configurables.

---

## Mapa de Agentes

```
                    ┌─────────────────────┐
                    │  ORCHESTRATOR_AGENT  │
                    │  (Director)          │
                    └──────────┬──────────┘
                               │
            ┌──────────────────┼──────────────────┐
            │                  │                   │
   ┌────────▼────────┐ ┌──────▼──────┐ ┌─────────▼────────┐
   │ ARCHITECT_AGENT  │ │ PLANNER_AGENT│ │ KNOWLEDGE_AGENT  │
   │ (Diseño)         │ │ (Backlog)    │ │ (Memoria)        │
   └────────┬─────────┘ └──────┬──────┘ └─────────┬────────┘
            │                  │                   │
            │           ┌──────▼──────┐            │
            │           │DEVELOPER_AGENT│           │
            │           │(Implementación)│          │
            │           └──────┬──────┘            │
            │                  │                   │
            │    ┌─────────────┼──────────┐        │
            │    │             │          │        │
            │ ┌──▼───────┐ ┌──▼────────┐ │        │
            │ │REVIEWER   │ │REFACTOR   │ │        │
            │ │AGENT      │ │AGENT      │ │        │
            │ └───────────┘ └───────────┘ │        │
            │                             │        │
            └─────────────────────────────┘        │
                          │                        │
                          └────────────────────────┘
                          (feedback loop → memoria)
```

---

## Agentes

### 1. ORCHESTRATOR_AGENT (`orchestrator` — primario)

**Rol:** Director del sistema. Coordina la ejecución del pipeline, selecciona tareas, asigna agentes y gestiona el flujo completo.

**Responsabilidades:**
- Leer el backlog y seleccionar la siguiente tarea priorizada.
- Verificar precondiciones de cada tarea (dependencias, estado del repo).
- Despachar la tarea al agente correspondiente.
- Recoger resultados y decidir el siguiente paso (avance, rollback, escalación).
- Mantener el estado global de ejecución.
- Registrar cada decisión en el learning log.

**Inputs:** `docs/backlog.md`, estado del repositorio, `docs/learning-log.md`, `memory/`.

**Outputs:** Selección de tarea + agente asignado, actualización de backlog, entrada en learning log por ciclo.

**Manejo de fallos:**
- Si DEVELOPER falla → registrar error, mover tarea a `blocked`, seleccionar siguiente.
- Si REVIEWER rechaza → devolver a DEVELOPER con feedback.
- Si 3 fallos consecutivos en misma tarea → escalar a intervención humana.

---

### 2. ARCHITECT_AGENT (`architect` — subagente)

**Rol:** Guardián de la arquitectura. Diseña, valida y evoluciona la estructura técnica.

**Responsabilidades:** Definir y mantener la arquitectura, validar cambios, proponer evoluciones, mantener `docs/stack.md` y ADRs, evaluar impacto arquitectónico de features.

**Inputs:** `docs/requirements.md`, `docs/stack.md`, `docs/technical-debt-system.md`, código fuente.

**Outputs:** ADRs, actualizaciones a `docs/evolution-system.md`, validaciones (aprobado/rechazado + justificación), refactors propuestos.

**Manejo de fallos:** Sin impacto determinable → más contexto de KNOWLEDGE. Conflicto de diseño → documentar opciones y escalar.

---

### 3. PLANNER_AGENT (`planner` — subagente)

**Rol:** Gestor del backlog. Descompone requisitos en épicas, historias y tareas ejecutables.

**Responsabilidades:** Mantener `docs/backlog.md`, descomponer features, asignar prioridades y dependencias, estimar complejidad, verificar criterios de aceptación, replanificar.

**Inputs:** `docs/requirements.md`, `docs/backlog.md`, feedback de REVIEWER, resultados de DEVELOPER.

**Outputs:** Tareas nuevas con formato estándar, actualizaciones de estado, dependencias resueltas, repriorización documentada.

**Manejo de fallos:** Requisito ambiguo → tarea de investigación previa. Dependencia circular → escalar a ARCHITECT.

---

### 4. DEVELOPER_AGENT (`developer` — subagente)

**Rol:** Implementador. Escribe código, crea tests y produce cambios funcionales.

**Responsabilidades:** Implementar tareas según estándares, escribir tests, seguir `docs/stack.md`, commits Conventional Commits, documentación inline.

**Inputs:** Tarea con criterios de aceptación, código fuente, `docs/stack.md`, `memory/`.

**Outputs:** Código implementado, tests, commits descriptivos, self-review completado.

**Manejo de fallos:** Tests fallan → fix (máx 2 iteraciones). Bloqueo técnico → tarea `blocked`. Dependencia externa → tarea previa vía PLANNER.

---

### 5. REVIEWER_AGENT (`reviewer` — subagente, sin permisos de edición)

**Rol:** Revisor de calidad. Valida código, detecta problemas y gestiona deuda técnica.

**Responsabilidades:** Revisar cada cambio, verificar criterios de aceptación, detectar problemas de calidad/seguridad/rendimiento, gestionar deuda técnica, aprobar o rechazar con justificación.

**Inputs:** Código producido, criterios de aceptación, `docs/technical-debt-system.md`, resultados de tests y lint.

**Outputs:** Veredicto APROBADO / CAMBIOS REQUERIDOS / RECHAZADO, issues con severidad, deuda técnica actualizada, feedback estructurado.

**Manejo de fallos:** Área no evaluable → contexto de KNOWLEDGE. Issue crítico de seguridad → bloquear merge inmediatamente.

---

### 6. REFACTOR_AGENT (`refactor` — subagente)

**Rol:** Optimizador. Mejora la calidad del código sin cambiar funcionalidad.

**Responsabilidades:** Analizar código, proponer y ejecutar refactors seguros, reducir complejidad ciclomática, eliminar duplicación, mejorar legibilidad. Solo con tests green antes y después.

**Inputs:** Reporte de deuda de REVIEWER, propuestas de ARCHITECT, `docs/refactor-system.md`, código fuente.

**Outputs:** Código refactorizado, tests verificados, documentación del cambio, actualización del learning log.

**Manejo de fallos:** Tests fallan post-refactor → revertir inmediatamente. Mejora marginal → abortar y documentar. Nunca refactorizar código con tareas activas.

---

### 7. KNOWLEDGE_AGENT (`knowledge` — subagente)

**Rol:** Memoria del sistema. Almacena, recupera y mantiene el conocimiento acumulado.

**Responsabilidades:** Gestionar `memory/`, almacenar decisiones/patrones/bugs, proveer contexto histórico, mantener `docs/learning-log.md`, detectar patrones recurrentes, indexar conocimiento.

**Inputs:** Resultados de todos los agentes, `docs/learning-log.md`, `memory/`.

**Outputs:** Contexto relevante, entradas en learning log, archivos en `memory/`, alertas de patrones problemáticos.

**Manejo de fallos:** Memoria corrupta → reconstruir desde learning log. Consulta sin resultados → contexto vacío (nunca fabrica información).

---

## Flujo de Colaboración Estándar

```
1. ORCHESTRATOR selecciona tarea del backlog
2. ORCHESTRATOR consulta KNOWLEDGE_AGENT para contexto
3. ORCHESTRATOR consulta ARCHITECT_AGENT si hay impacto arquitectónico
4. ORCHESTRATOR despacha a DEVELOPER_AGENT
5. DEVELOPER_AGENT implementa + tests
6. REVIEWER_AGENT revisa
7. Si APROBADO → merge + KNOWLEDGE_AGENT registra
8. Si RECHAZADO → DEVELOPER_AGENT corrige (máx 2 iter)
9. ORCHESTRATOR actualiza backlog
10. KNOWLEDGE_AGENT registra en learning log
```

---

## Reglas Globales del Sistema

1. **Un solo agente activo a la vez** (secuencial, no paralelo).
2. **Todo cambio pasa por REVIEWER_AGENT** antes de merge.
3. **Ningún agente modifica el backlog** excepto PLANNER_AGENT y ORCHESTRATOR_AGENT.
4. **La memoria es append-only** — nunca se borra conocimiento, solo se depreca.
5. **Tres strikes rule** — 3 fallos consecutivos en una tarea → intervención humana.
6. **Tests siempre green** — ningún merge con tests fallando.

---

## Memoria externa (TencentDB Agent Memory)

El sistema se integra con un Memory Hub (TencentDB Agent Memory) como memoria persistente de equipo. El despliegue vive en `deploy/memory/` de este repo.

| Servicio | Puertos | Uso |
|---|---|---|
| memory-core | `8420` | gateway de memoria (L0-L3, skills, metadata) |
| memory-hub | `8125` (panel) / `8424` (knowledge) | panel de control + Wiki/CodeGraph |
| proxy | `8096` | inyecta memoria/skills/knowledge en cada llamada LLM |

**Flujo:** los agentes usan el provider nativo `github-copilot` y los modelos válidos `gpt-5.6-terra` o `gpt-5.6-luna`. El proxy TencentDB es opcional: cuando se configura como endpoint del modelo, registra la sesión contra Team/Agent/Task vía headers (`x-team-id`, `x-agent-id`, `x-task-id`, `x-conversation-id`), inyecta L2/L3 + Skills + Wiki/CodeGraph y captura L0.

**Puesta en marcha:**

1. `deploy/memory/.env.example` → `.env` (dos grupos LLM: `MEMORY_LLM_*` interno y `PROXY_UPSTREAM_*` del agente).
2. `.\start.ps1` — genera `config/proxy.yaml`, levanta el stack y crea el admin (`deploy/memory/.admin-key`).
3. Panel `http://localhost:8125` → crear Team → Agent → Task; copiar `user_key` y los ids a `TDAI_USER_KEY`, `TDAI_TEAM_ID`, `TDAI_AGENT_ID`, `TDAI_TASK_ID` (variables de entorno o `.env`).
4. Reiniciar opencode. Para usar el proxy como transporte de memoria hay que cambiar explícitamente los modelos de los agentes al provider compatible configurado; por defecto los agentes funcionan directamente con `github-copilot`.

**Notas:** el catálogo Copilot actual no expone variantes `-medium`/`-high`: los IDs válidos son `github-copilot/gpt-5.6-terra` y `github-copilot/gpt-5.6-luna`. `x-conversation-id` es estático por config cuando se usa el proxy: cambiar el valor por conversación si se quiere aislar contextos de memoria.
