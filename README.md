# Shogun DevOS

[Español](README.es.md)

**Shogun DevOS** is a ready-to-use [OpenCode](https://opencode.ai) template for
building software with a disciplined multi-agent workflow.

One orchestrator coordinates seven specialist agents. Every change follows the
same path: context → implementation → quality checks → review → learning.

## What It Is For

Use this template when you want OpenCode to help build a project with:

- Clear agent roles.
- Mandatory review before completion.
- Local project memory.
- Optional shared memory with TencentDB Agent Memory.

## Requirements

| Requirement | Why |
|---|---|
| OpenCode + GitHub Copilot | Runs the agents and models. |
| PowerShell 7+ | Runs setup, validation, and pipeline scripts. |
| Git | Tracks your project and changes. |
| Docker Desktop | Optional. Required only for TencentDB team memory. |
| OpenAI-compatible LLM | Optional. Required only by TencentDB to summarize and index memory. |

You can use Shogun without Docker or an extra LLM. Local memory always works.

## Start A Project

1. Click **Use this template** on GitHub.
2. Clone your new repository.
3. Open the project in OpenCode and run `/connect`.
4. Select **GitHub Copilot**.
5. Restart OpenCode.
6. Run:

```powershell
pwsh -NoProfile -File tools/Initialize-ShogunDevOS.ps1 -Root . -Demo -AcceptScaffold
```

Or run this from OpenCode:

```text
/shogun-init
```

The setup creates a small dependency-free demo, `docs/`, and `memory/`.
It never installs packages without asking.

## Daily Use

Create a task in `docs/backlog.md`, then run:

```text
/devos Implement DEMO-001.
```

Shogun will:

1. Read project memory and the backlog.
2. Dispatch one specialist at a time.
3. Run test, lint, and build checks when configured.
4. Request review before completion.
5. Record decisions in `docs/learning-log.md` and `memory/`.

Configure project checks in `.opencode/pipeline/pipeline.json`.

## Memory

### Local Memory

Always available. No setup required.

```text
memory/                 Reusable project knowledge
docs/learning-log.md    Decisions and outcomes
```

### TencentDB Agent Memory

Optional team memory hub. It adds a web panel, shared memory, Wiki, Skills,
and CodeGraph.

Run this only if Docker Desktop is available:

```powershell
pwsh -NoProfile -File tools/Initialize-ShogunDevOS.ps1 -Root . -ConfigureMemoryHub -StartMemoryHub
```

It asks only for `MEMORY_LLM_BASE_URL`, `MEMORY_LLM_API_KEY`, and
`MEMORY_LLM_MODEL`. They are stored in `deploy/memory/.env`, ignored by Git.

TencentDB does **not** automatically intercept GitHub Copilot requests. It is
an optional memory hub; agents continue to work with local memory if it is
unavailable.

## Useful Commands

```powershell
pwsh -NoProfile -File .opencode/pipeline/scripts/Test-LcissConfig.ps1 -Root .
pwsh -NoProfile -File .opencode/pipeline/scripts/Invoke-QualityGate.ps1 -Root .
pwsh -NoProfile -File tools/Test-ShogunPrerequisites.ps1 -Root .
```

Restart OpenCode after changing `opencode.json`, `.opencode/`, or agent files.
