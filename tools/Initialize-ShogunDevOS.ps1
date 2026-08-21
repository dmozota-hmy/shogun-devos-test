#Requires -Version 7
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [switch]$Demo,
    [switch]$AcceptScaffold,
    [switch]$ConfigureMemoryHub,
    [switch]$StartMemoryHub
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Confirm-Action { param([string]$Question, [switch]$Accepted); if ($Accepted) { return $true }; (Read-Host "$Question [y/N]") -match '^(y|yes|s|si)$' }
function New-FileIfMissing { param([string]$Path, [string]$Content); if (Test-Path -LiteralPath $Path) { return $false }; New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null; Set-Content -LiteralPath $Path -Value $Content.TrimEnd("`r", "`n") -Encoding utf8; return $true }
function Set-EnvValue {
    param([string]$Path, [string]$Key, [string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Contains("`n") -or $Value.Contains("`r")) { throw "$Key must be a single non-empty line." }
    $content = Get-Content -LiteralPath $Path -Raw
    $pattern = "(?m)^$([regex]::Escape($Key))=.*$"
    $replacement = "$Key=$Value"
    if ($content -match $pattern) { $content = [regex]::Replace($content, $pattern, $replacement) } else { $content = "$content`n$replacement`n" }
    Set-Content -LiteralPath $Path -Value $content -Encoding utf8
}

function Normalize-LlmBaseUrl {
    param([string]$Value)
    $normalized = $Value.Trim().TrimEnd('/')
    if ($normalized -match '\.cognitiveservices\.azure\.com$') { return "$normalized/openai/v1" }
    if ($normalized -match '\.openai\.azure\.com$') { return "$normalized/openai/v1" }
    return $normalized
}
function Read-PlainSecret {
    param([string]$Prompt)
    $secure = Read-Host -Prompt $Prompt -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

$rootPath = (Resolve-Path -LiteralPath $Root).Path
$report = & (Join-Path $PSScriptRoot 'Test-ShogunPrerequisites.ps1') -Root $rootPath | ConvertFrom-Json -Depth 10
Write-Host "`nShogun DevOS onboarding" -ForegroundColor Cyan
Write-Host 'Local memory: ready (no external dependencies).' -ForegroundColor Green
Write-Host "Memory Hub: $($report.memoryHub.status)." -ForegroundColor Yellow
Write-Host $report.copilotProxyIntegration.message -ForegroundColor DarkYellow

$created = [System.Collections.Generic.List[string]]::new()
$createDemo = if ($Demo) { $true } elseif ($ConfigureMemoryHub -or $StartMemoryHub) { $false } else { Confirm-Action -Question 'Create the dependency-free memory demo?' -Accepted:$AcceptScaffold }
if ($createDemo) {
    $templates = Join-Path $rootPath 'templates\demo-static'
    $target = Join-Path $rootPath 'demo-memory-garden'
    Get-ChildItem -LiteralPath $templates -File | ForEach-Object { $destination = Join-Path $target $_.Name; if (New-FileIfMissing -Path $destination -Content (Get-Content -LiteralPath $_.FullName -Raw)) { $created.Add($destination) } }
    $pipelinePath = Join-Path $rootPath '.opencode\pipeline\pipeline.json'
    $pipeline = Get-Content -LiteralPath $pipelinePath -Raw | ConvertFrom-Json -Depth 20
    $pipeline.qualityGate.test.required = $true; $pipeline.qualityGate.test.command = 'pwsh -NoProfile -File tools/Test-DemoMemoryGarden.ps1'; $pipeline.qualityGate.test.PSObject.Properties.Remove('notApplicableReason')
    $pipeline.qualityGate.lint.required = $false; $pipeline.qualityGate.lint.command = ''; $pipeline.qualityGate.lint.notApplicableReason = 'The dependency-free demo has no separate linter.'
    $pipeline.qualityGate.build.required = $false; $pipeline.qualityGate.build.command = ''; $pipeline.qualityGate.build.notApplicableReason = 'The dependency-free demo is served directly as static files.'
    Set-Content -LiteralPath $pipelinePath -Value ($pipeline | ConvertTo-Json -Depth 20) -Encoding utf8
    $created.Add($pipelinePath)
}

$documents = [ordered]@{
    'docs\requirements.md' = "# Requirements`n`n## Goal`nBuild a small memory garden demo to understand Shogun DevOS.`n"
    'docs\backlog.md' = "# Backlog`n`n| ID | Epic | Task | State | Priority | Dependencies | Acceptance criteria | Agent |`n|---|---|---|---|---|---|---|---|`n| DEMO-001 | Memory Garden | Verify local memory flow | ready | high | none | Demo opens; learning log receives an entry; pipeline validation passes | developer |`n"
    'docs\stack.md' = "# Stack`n`n- Static HTML, CSS, and JavaScript.`n- No package installation required.`n"
    'docs\learning-log.md' = "# Learning Log`n`n| Date | Agent | Decision | Result |`n|---|---|---|---|`n"
    'docs\technical-debt-system.md' = "# Technical Debt System`n`nRecord deferred work with impact, owner, and exit criteria.`n"
    'docs\evolution-system.md' = "# Evolution System`n`nArchitecture decisions are recorded under `docs/adr/`.`n"
    'docs\refactor-system.md' = "# Refactor System`n`nRefactors require green quality gates before and after the change.`n"
    'memory\INDEX.md' = @'
# Memory Index

- `patterns/` — reusable practices
- `decisions/` — design decisions
- `bugs/` — resolved incidents
'@
}
if ($createDemo -or (-not $ConfigureMemoryHub -and -not $StartMemoryHub)) {
    foreach ($entry in $documents.GetEnumerator()) { $path = Join-Path $rootPath $entry.Key; if (New-FileIfMissing -Path $path -Content $entry.Value) { $created.Add($path) } }
}

$memoryEnv = Join-Path $rootPath 'deploy\memory\.env'
if ($report.prerequisites.docker.daemonReady -and $ConfigureMemoryHub -and (-not $report.memoryHub.extractionLlmConfigured)) {
    if (-not (Test-Path -LiteralPath $memoryEnv)) { Copy-Item -LiteralPath (Join-Path $rootPath 'deploy\memory\.env.example') -Destination $memoryEnv; $created.Add($memoryEnv) }
    Write-Host 'The hub needs one OpenAI-compatible extraction LLM. The proxy is not configured here.' -ForegroundColor Yellow
    $baseUrl = Normalize-LlmBaseUrl (Read-Host 'MEMORY_LLM_BASE_URL (Azure: https://resource.cognitiveservices.azure.com/openai/v1)')
    $apiKey = Read-PlainSecret -Prompt 'MEMORY_LLM_API_KEY (hidden input)'
    $model = Read-Host 'MEMORY_LLM_MODEL (example: gpt-4o-mini)'
    Set-EnvValue -Path $memoryEnv -Key 'MEMORY_LLM_BASE_URL' -Value $baseUrl
    Set-EnvValue -Path $memoryEnv -Key 'MEMORY_LLM_API_KEY' -Value $apiKey
    Set-EnvValue -Path $memoryEnv -Key 'MEMORY_LLM_MODEL' -Value $model
    Write-Host "Memory Hub configuration saved to $memoryEnv. The file is ignored by Git." -ForegroundColor Green
}
if (($ConfigureMemoryHub -or $StartMemoryHub) -and -not $report.prerequisites.docker.daemonReady) {
    Write-Warning 'TencentDB no se ha configurado: instala e inicia Docker Desktop y vuelve a ejecutar el mismo comando.'
}
if ($StartMemoryHub) {
    if (-not $report.prerequisites.docker.daemonReady) { Write-Warning 'The Memory Hub was not started: Docker Desktop is unavailable or stopped.' }
    elseif (-not (Test-Path -LiteralPath $memoryEnv)) { Write-Warning 'The Memory Hub was not started: run again with -ConfigureMemoryHub and set the three MEMORY_LLM_* values.' }
    else { & (Join-Path $rootPath 'deploy\memory\start.ps1') -HubOnly }
}
$demoReady = Test-Path -LiteralPath (Join-Path $rootPath 'demo-memory-garden\index.html')
$nextStep = if ($StartMemoryHub -and -not $report.prerequisites.docker.daemonReady) { 'Start Docker Desktop and run this same command again.' } elseif ($StartMemoryHub) { 'Open http://localhost:8125 and create a Team, Agent, and Task.' } elseif ($demoReady) { 'Open demo-memory-garden/index.html, then run /devos for DEMO-001 in OpenCode.' } else { 'Run /shogun-init or rerun with -Demo to create the learning demo.' }
$memoryStatus = if ($StartMemoryHub -and -not $report.prerequisites.docker.daemonReady) { 'not-started-docker-unavailable' } elseif ($StartMemoryHub) { 'requested' } else { $report.memoryHub.status }
[ordered]@{ root = $rootPath; created = $created; localMemory = 'ready'; demo = if ($demoReady) { 'ready' } else { 'skipped' }; memoryHub = $memoryStatus; copilotProxyIntegration = 'not-configured-not-guaranteed'; nextStep = $nextStep } | ConvertTo-Json -Depth 10
