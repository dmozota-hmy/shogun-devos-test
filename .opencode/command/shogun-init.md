---
description: Configura Shogun DevOS para un proyecto nuevo: diagnostica requisitos, crea la demo sin dependencias, documentos y memoria local. Docker y TencentDB son opcionales.
agent: orchestrator
---

Ejecuta el onboarding reproducible de Shogun DevOS en el proyecto actual:

```powershell
pwsh -NoProfile -File .shogun/tools/Initialize-ShogunDevOS.ps1 -Root . -Demo -AcceptScaffold
```

Explica el resumen resultante de forma simple. Si Docker no está disponible, confirma que la memoria local y la demo siguen listas; no intentes instalar Docker. Si el usuario pide TencentDB, ejecuta primero el diagnóstico y solicita únicamente la configuración mínima `MEMORY_LLM_BASE_URL`, `MEMORY_LLM_API_KEY` y `MEMORY_LLM_MODEL`.
