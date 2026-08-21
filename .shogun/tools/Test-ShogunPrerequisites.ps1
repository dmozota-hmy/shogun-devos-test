#Requires -Version 7
param([string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CommandStatus {
    param([string]$Name)
    $command = Get-Command -Name $Name -ErrorAction SilentlyContinue
    [ordered]@{ available = [bool]$command; path = if ($command) { $command.Source } else { $null } }
}

function Find-Docker {
    $command = Get-Command -Name 'docker' -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    @(
        (Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin\docker.exe'),
        (Join-Path $env:ProgramW6432 'Docker\Docker\resources\bin\docker.exe'),
        (Join-Path $env:LOCALAPPDATA 'Docker\Docker\resources\bin\docker.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

$dockerPath = Find-Docker
$docker = [ordered]@{ available = [bool]$dockerPath; path = $dockerPath }
$dockerDaemon = $false
$dockerMessage = 'Docker CLI not found. Install Docker Desktop to use the optional TencentDB Memory Hub.'
if ($docker.available) {
    try {
        & $dockerPath info *> $null
        if ($LASTEXITCODE -eq 0) { $dockerDaemon = $true; $dockerMessage = 'Docker daemon is ready.' }
        else { $dockerMessage = 'Docker Desktop is installed but its daemon is not running. Start Docker Desktop and retry.' }
    } catch { $dockerMessage = 'Docker Desktop is installed but its daemon is not running. Start Docker Desktop and retry.' }
}

$memoryEnv = Join-Path $Root '.shogun\config\.env'
$memoryEnvReady = $false
if (Test-Path -LiteralPath $memoryEnv) {
    $content = Get-Content -LiteralPath $memoryEnv -Raw
    $missing = @(@('MEMORY_LLM_BASE_URL', 'MEMORY_LLM_API_KEY', 'MEMORY_LLM_MODEL') | Where-Object { $content -notmatch "(?m)^$_=(?!REPLACE_ME$).+" })
    $memoryEnvReady = $missing.Count -eq 0
}

[ordered]@{
    root = $Root
    prerequisites = [ordered]@{
        powershell = [ordered]@{ available = $PSVersionTable.PSVersion.Major -ge 7; version = $PSVersionTable.PSVersion.ToString() }
        git = Get-CommandStatus -Name 'git'
        docker = [ordered]@{ available = $docker.available; daemonReady = $dockerDaemon; message = $dockerMessage }
    }
    localMemory = [ordered]@{ available = $true; message = 'Local memory needs no external service.' }
    memoryHub = [ordered]@{ envFileExists = Test-Path -LiteralPath $memoryEnv; extractionLlmConfigured = $memoryEnvReady; status = if (-not $dockerDaemon) { 'optional-unavailable' } elseif (-not $memoryEnvReady) { 'needs-llm-configuration' } else { 'ready-to-start' } }
    copilotProxyIntegration = [ordered]@{ status = 'not-configured-not-guaranteed'; message = 'Agents use native GitHub Copilot. TencentDB is an optional memory hub and does not automatically intercept Copilot requests.' }
} | ConvertTo-Json -Depth 10
