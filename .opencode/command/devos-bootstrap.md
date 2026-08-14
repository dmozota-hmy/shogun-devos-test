---
description: Crea el scaffolding del AI-DevOS LCISS (docs/ y memory/) en el proyecto actual. No sobrescribe archivos existentes.
---

Crea la estructura base del AI-DevOS LCISS en este proyecto. Si un archivo ya existe, reutilízalo y adáptalo, nunca lo sobrescribas:

1. `docs/requirements.md` — especificación técnica: objetivo, requisitos funcionales y no funcionales, criterios de aceptación.
2. `docs/backlog.md` — backlog priorizado con tabla: ID | Épica | Tarea | Estado (`ready`/`in-progress`/`done`/`blocked`) | Prioridad | Dependencias | Criterios de aceptación | Agente.
3. `docs/stack.md` — stack y estándares técnicos del proyecto (lenguajes, frameworks, convenciones, comandos de test/lint).
4. `docs/learning-log.md` — historial de decisiones append-only: fecha | agente | decisión | resultado.
5. `docs/technical-debt-system.md` — reglas de detección y registro de deuda técnica.
6. `docs/evolution-system.md` — sistema de evolución: ADRs y proceso de cambio arquitectónico.
7. `docs/refactor-system.md` — reglas y umbrales de refactor (qué se refactoriza, cuándo y con qué justificación).
8. `memory/INDEX.md` — índice del conocimiento acumulado (categorías: design-decision, pattern, bug, architecture, refactor).

Al terminar, lista los archivos creados o adaptados.
