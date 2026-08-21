---
description: Configura la identidad Team/Agent/Task del MCP de TencentDB para el agente knowledge.
agent: orchestrator
---

Ejecuta en local:

```powershell
pwsh -NoProfile -File tools/Configure-ShogunMemory.ps1 -Root .
```

Para un hub remoto:

```powershell
pwsh -NoProfile -File tools/Configure-ShogunMemory.ps1 -Root . -Mode Remote
```

Solicita URLs, `user_key` y Team/Agent/Task. Guarda todo en `.shogun-memory/config.json`, ignorado por Git; nunca escribas claves en archivos versionados. El MCP vive en `.opencode/mcp/` y los scripts de configuración en `tools/`.
