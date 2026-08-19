# Shogun DevOS

[English](README.md)

**Shogun DevOS** es una plantilla para [OpenCode](https://opencode.ai) que
permite construir software con un flujo de agentes disciplinado.

Un orquestador coordina siete agentes especializados. Cada cambio sigue el
mismo camino: contexto → implementación → calidad → revisión → aprendizaje.

## Para Qué Sirve

- Roles de agentes claros.
- Revisión obligatoria antes de terminar.
- Memoria local del proyecto.
- Memoria compartida opcional con TencentDB Agent Memory.

## Requisitos

| Requisito | Por qué |
|---|---|
| OpenCode + GitHub Copilot | Ejecuta los agentes y modelos. |
| PowerShell 7+ | Ejecuta scripts de inicio, validación y pipeline. |
| Git | Guarda el historial del proyecto. |
| Docker Desktop | Opcional. Solo necesario para memoria TencentDB. |
| LLM compatible con OpenAI | Opcional. TencentDB lo usa para extraer memoria. |

Puedes usar Shogun sin Docker ni otro LLM. La memoria local siempre funciona.

## Empezar Un Proyecto

1. Pulsa **Use this template** en GitHub.
2. Clona tu nuevo repositorio.
3. Abre el proyecto con OpenCode y ejecuta `/connect`.
4. Selecciona **GitHub Copilot**.
5. Reinicia OpenCode.
6. Ejecuta:

```powershell
pwsh -NoProfile -File tools/Initialize-ShogunDevOS.ps1 -Root . -Demo -AcceptScaffold
```

También puedes ejecutar desde OpenCode:

```text
/shogun-init
```

El inicio crea una demo sin dependencias, `docs/` y `memory/`. No instala
paquetes sin pedir confirmación.

## Uso Diario

Crea una tarea en `docs/backlog.md` y ejecuta:

```text
/devos Implement DEMO-001.
```

Shogun lee memoria y backlog, usa un agente cada vez, ejecuta controles de
calidad, pide revisión y registra las decisiones en `docs/learning-log.md` y
`memory/`.

Configura los checks del proyecto en `.opencode/pipeline/pipeline.json`.

## Memoria

### Memoria Local

Siempre disponible y sin configuración:

```text
memory/                 Conocimiento reutilizable
docs/learning-log.md    Decisiones y resultados
```

### TencentDB Agent Memory

Hub opcional de memoria de equipo. Añade panel web, memoria compartida, Wiki,
Skills y CodeGraph.

Ejecuta esto solo si tienes Docker Desktop:

```powershell
pwsh -NoProfile -File tools/Initialize-ShogunDevOS.ps1 -Root . -ConfigureMemoryHub -StartMemoryHub
```

Solo solicita `MEMORY_LLM_BASE_URL`, `MEMORY_LLM_API_KEY` y
`MEMORY_LLM_MODEL`. Se guardan en `deploy/memory/.env`, ignorado por Git.

TencentDB **no** intercepta automáticamente GitHub Copilot. Es un hub opcional;
si no está disponible, los agentes continúan usando memoria local.

## Comandos Útiles

```powershell
pwsh -NoProfile -File .opencode/pipeline/scripts/Test-LcissConfig.ps1 -Root .
pwsh -NoProfile -File .opencode/pipeline/scripts/Invoke-QualityGate.ps1 -Root .
pwsh -NoProfile -File tools/Test-ShogunPrerequisites.ps1 -Root .
```

Reinicia OpenCode después de cambiar `opencode.json`, `.opencode/` o agentes.
