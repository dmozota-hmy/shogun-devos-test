#Requires -Version 7
<#
.SYNOPSIS
  Levanta el hub opcional de TencentDB Agent Memory (memory-core + memory-hub).
  El proxy de LLM es un opt-in avanzado mediante -Proxy; no es necesario para
  la memoria local de Shogun ni se integra automáticamente con GitHub Copilot.
.PARAMETER Stop
  Detiene los contenedores (mantiene volúmenes y .admin-key).
.PARAMETER Purge
  Detiene y borra volúmenes + .admin-key (borrado completo).
.PARAMETER Proxy
  Incluye el proxy LLM. Requiere PROXY_UPSTREAM_* y una integración de cliente
  compatible; no usar para GitHub Copilot nativo sin validación previa.
.PARAMETER HubOnly
  Alias explícito para el comportamiento predeterminado: inicia solo el hub.
.EXAMPLE
  .\start.ps1
  .\start.ps1 -Stop
#>
param(
    [switch]$Stop,
    [switch]$Purge,
    [switch]$Proxy,
    [switch]$HubOnly
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
$ConfigDir = Join-Path $ScriptDir '..\..\config'
$EnvFile = Join-Path $ConfigDir '.env'
$AdminKeyFile = Join-Path $ConfigDir '.admin-key'
$ProxyConfigFile = Join-Path $ConfigDir 'proxy.yaml'

function Get-EnvValue {
    param([string]$Key)
    $m = Select-String -Path $EnvFile -Pattern "^\s*$Key\s*=\s*(.*)$" | Select-Object -Last 1
    if ($null -eq $m) { return '' }
    return $m.Matches[0].Groups[1].Value.Trim()
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

$DockerPath = Find-Docker

function Test-DockerReady {
    if (-not $DockerPath) {
        Write-Warning 'Docker CLI no esta instalado. Instala Docker Desktop para usar el hub opcional de TencentDB.'
        return $false
    }
    try {
        & $DockerPath info *> $null
        if ($LASTEXITCODE -eq 0) { return $true }
    } catch { }
    Write-Warning 'Docker Desktop esta instalado pero no esta iniciado. Arrancalo y vuelve a ejecutar este comando.'
    return $false
}

function Invoke-AdminInit {
    param([string]$Port, [string]$ApiKey)
    $key = $null
    if (Test-Path $AdminKeyFile) { $key = (Get-Content $AdminKeyFile -Raw).Trim() }
    if (-not $key) {
        $bytes = New-Object byte[] 32
        [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
        $key = 'sk-mem-' + (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
        Set-Content -Path $AdminKeyFile -Value $key -NoNewline
        Write-Host "[init] generada user_key -> $AdminKeyFile" -ForegroundColor DarkGray
    }
    $username = Get-EnvValue 'MEMORY_CORE_ADMIN_USERNAME'
    if (-not $username) { $username = 'admin' }
    $body = @{ username = $username; user_key = $key } | ConvertTo-Json -Compress
    $headers = @{ 'x-tdai-service-id' = 'default' }
    $gwKey = Get-EnvValue 'MEMORY_CORE_GATEWAY_API_KEY'
    if ($gwKey) { $headers['Authorization'] = "Bearer $gwKey" }
    try {
        $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v3/internal/meta/user/init-admin" -Method Post -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 15
        Write-Host "[init] admin user '$username' creado" -ForegroundColor Green
    } catch {
        if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 409) {
            Write-Host "[init] admin user ya existe (reusando .admin-key)" -ForegroundColor DarkYellow
        } else {
            Write-Host "[init] aviso: init-admin fallo ($($_.Exception.Message))" -ForegroundColor DarkYellow
        }
    }
    return $key
}

if ($Purge) {
    if (-not (Test-DockerReady)) { return }
    if (Test-Path -LiteralPath $EnvFile) {
        & $DockerPath compose --env-file $EnvFile -f (Join-Path $ScriptDir 'docker-compose.yml') down -v
    } else {
        & $DockerPath compose -f (Join-Path $ScriptDir 'docker-compose.yml') down -v
    }
    Remove-Item $AdminKeyFile -ErrorAction SilentlyContinue
    Write-Host 'Stack detenido y volúmenes eliminados.' -ForegroundColor Green
    exit 0
}
if ($Stop) {
    if (-not (Test-DockerReady)) { return }
    if (Test-Path -LiteralPath $EnvFile) {
        & $DockerPath compose --env-file $EnvFile -f (Join-Path $ScriptDir 'docker-compose.yml') down
    } else {
        & $DockerPath compose -f (Join-Path $ScriptDir 'docker-compose.yml') down
    }
    Write-Host 'Stack detenido (volúmenes conservados).' -ForegroundColor Green
    exit 0
}

if (-not (Test-DockerReady)) { return }

if (-not (Test-Path $EnvFile)) {
    Copy-Item -LiteralPath (Join-Path $ConfigDir '.env.example') -Destination $EnvFile
    Write-Warning "Se ha creado $EnvFile. Configura MEMORY_LLM_BASE_URL, MEMORY_LLM_API_KEY y MEMORY_LLM_MODEL antes de iniciar el hub."
    return
}

$required = @('MEMORY_LLM_BASE_URL', 'MEMORY_LLM_API_KEY', 'MEMORY_LLM_MODEL')
if ($Proxy) { $required += @('PROXY_UPSTREAM_URL', 'PROXY_UPSTREAM_API_KEY', 'PROXY_UPSTREAM_MODEL') }
$missing = @($required | Where-Object { (Get-EnvValue $_) -in @('', 'REPLACE_ME') })
if ($missing.Count -gt 0) {
    Write-Warning "El hub no se inicio. Faltan valores en .env: $($missing -join ', ')"
    Write-Host 'Para el hub basico solo necesitas MEMORY_LLM_BASE_URL, MEMORY_LLM_API_KEY y MEMORY_LLM_MODEL.' -ForegroundColor Yellow
    return
}

if ($Proxy) {
    # ── Generar config/proxy.yaml (solo para integraciones avanzadas) ─────────
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    $gwKey = Get-EnvValue 'MEMORY_CORE_GATEWAY_API_KEY'
    if (-not $gwKey) { $gwKey = 'local' }
    $proxyConfig = @"
# Generado por start.ps1 a partir de .env — no editar a mano.
server:
  host: 0.0.0.0
  port: 8096
  forwardTimeoutMs: 600000

upstream:
  url: "$(Get-EnvValue 'PROXY_UPSTREAM_URL')"
  apiKey: "$(Get-EnvValue 'PROXY_UPSTREAM_API_KEY')"

log:
  file: ""
  level: info
  backend: console

tdai:
  enabled: true
  endpoint: "http://memory-core:8420"
  apiKey: "$gwKey"
  serviceId: default
  memory:
    enabled: true
    inject: true
    writeL0: true
    recallL1: true
    injectL2L3: true

skill:
  endpoint: "http://memory-core:8420"
  serviceToken: "$gwKey"

auth:
  enabled: true
  url: "http://memory-core:8420"
  timeoutMs: 5000

sessionInit:
  enabled: true
  maxRetries: 3
  injectAgentContext: true
  injectTaskContext: true
  headerAutoSelect:
    enabled: true
    teamHeader: "x-team-id"
    agentHeader: "x-agent-id"
    taskHeader: "x-task-id"
    onMismatch: "form"

costGuard:
  enabled: false

injection:
  enabled: true
  injectors:
    - skill
    - knowledge
    - tdai-memory

redis:
  enabled: false
"@
    Set-Content -Path $ProxyConfigFile -Value $proxyConfig -Encoding utf8
    Write-Host "[config] $ProxyConfigFile generado" -ForegroundColor DarkGray
}

# ── Levantar stack ───────────────────────────────────────────────────────────
if ($Proxy) {
    Write-Host 'Levantando memory-core + memory-hub + proxy...' -ForegroundColor Cyan
    & $DockerPath compose --env-file $EnvFile -f (Join-Path $ScriptDir 'docker-compose.yml') --profile proxy up -d
} else {
    Write-Host 'Levantando memory-core + memory-hub...' -ForegroundColor Cyan
    & $DockerPath compose --env-file $EnvFile -f (Join-Path $ScriptDir 'docker-compose.yml') up -d memory-core memory-hub
}
if ($LASTEXITCODE -ne 0) { Write-Error 'docker compose up fallo.' }

# ── Esperar health de memory-core ────────────────────────────────────────────
$corePort = Get-EnvValue 'MEMORY_CORE_PORT'
if (-not $corePort) { $corePort = '8420' }
$ok = $false
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 2
    try {
        $h = Invoke-RestMethod -Uri "http://127.0.0.1:$corePort/health" -TimeoutSec 3
        if ($h.status -eq 'ok') { $ok = $true; break }
    } catch { }
}
if (-not $ok) { Write-Warning "memory-core no respondio en /health (¿puerto $corePort?). Revisa: docker logs tdai-memory-core" }

# ── init-admin + persistir user_key ──────────────────────────────────────────
$adminKey = Invoke-AdminInit -Port $corePort

# ── Resumen ──────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '=== TencentDB Agent Memory UP ===' -ForegroundColor Green
Write-Host "  Panel UI     : http://localhost:$($(Get-EnvValue 'PANEL_PORT'))/" -NoNewline
Write-Host "  (login user_key: $($adminKey.Substring(0, 11))****$($adminKey.Substring($adminKey.Length - 4)))" -ForegroundColor DarkGray
Write-Host "  Knowledge    : http://localhost:$($(Get-EnvValue 'KNOWLEDGE_PORT'))/v3/"
Write-Host "  MemoryCore   : http://localhost:$corePort/"
if ($Proxy) {
    $proxyPort = Get-EnvValue 'PROXY_PORT'
    if (-not $proxyPort) { $proxyPort = '8096' }
    Write-Host "  Proxy        : http://localhost:$proxyPort/"
}
Write-Host ''
Write-Host 'Siguiente: entra en el panel y crea Team -> Agent -> Task para organizar los activos compartidos.' -ForegroundColor Yellow
if ($Proxy) {
    Write-Host 'El proxy requiere TDAI_USER_KEY, TDAI_TEAM_ID, TDAI_AGENT_ID y TDAI_TASK_ID; GitHub Copilot nativo no los usa.' -ForegroundColor Yellow
} else {
    Write-Host 'El hub es opcional: Shogun sigue funcionando con memoria local aunque el hub se detenga.' -ForegroundColor Yellow
}
