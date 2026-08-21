---
description: Sincroniza el harness y runtime de Shogun desde la plantilla, preservando .shogun/config y el código del proyecto.
agent: orchestrator
---

Ejecuta desde la raíz del proyecto:

```powershell
pwsh -NoProfile -File .shogun/tools/Sync-ShogunTemplate.ps1 -Root . -Source Auto
```

`Auto` usa la plantilla local hermana si existe y, si no, clona `shogun-devos` desde GitHub. El proceso reemplaza `.opencode/`, `.shogun/deploy/`, `.shogun/templates/` y `.shogun/tools/`, además de `opencode.json`; preserva completamente `.shogun/config/`, que contiene claves y configuración local. No modifica el código de la aplicación ni `docs/` o `memory/`.
