#Requires -Version 7
<#
.SYNOPSIS
  Levanta el stack de TencentDB Agent Memory (memory-core + memory-hub + proxy)
  con Docker Compose, replicando los scripts oficiales bash del upstream.
  Genera config/proxy.yaml a partir de .env (el proxy solo lee YAML).
.PARAMETER Stop
  Detiene los contenedores (mantiene volúmenes y .admin-key).
.PARAMETER Purge
  Detiene y borra volúmenes + .admin-key (borrado completo).
.EXAMPLE
  .\start.ps1
  .\start.ps1 -Stop
#>
param(
    [switch]$Stop,
    [switch]$Purge
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
$EnvFile = Join-Path $ScriptDir '.env'
$AdminKeyFile = Join-Path $ScriptDir '.admin-key'
$ProxyConfigFile = Join-Path $ScriptDir 'config\proxy.yaml'

function Get-EnvValue {
    param([string]$Key)
    $m = Select-String -Path $EnvFile -Pattern "^\s*$Key\s*=\s*(.*)$" | Select-Object -Last 1
    if ($null -eq $m) { return '' }
    return $m.Matches[0].Groups[1].Value.Trim()
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
    docker compose -f (Join-Path $ScriptDir 'docker-compose.yml') down -v
    Remove-Item $AdminKeyFile -ErrorAction SilentlyContinue
    Write-Host 'Stack detenido y volúmenes eliminados.' -ForegroundColor Green
    exit 0
}
if ($Stop) {
    docker compose -f (Join-Path $ScriptDir 'docker-compose.yml') down
    Write-Host 'Stack detenido (volúmenes conservados).' -ForegroundColor Green
    exit 0
}

if (-not (Test-Path $EnvFile)) {
    Write-Error "No existe .env — copia .env.example a .env y rellena los valores."
}

$required = @('MEMORY_LLM_BASE_URL', 'MEMORY_LLM_API_KEY', 'MEMORY_LLM_MODEL', 'PROXY_UPSTREAM_URL', 'PROXY_UPSTREAM_API_KEY')
$missing = @($required | Where-Object { (Get-EnvValue $_) -in @('', 'REPLACE_ME') })
if ($missing.Count -gt 0) {
    Write-Error "Faltan valores en .env: $($missing -join ', ')"
}

# ── Generar config/proxy.yaml (mismo contenido que start-proxy.sh oficial) ──
New-Item -ItemType Directory -Path (Join-Path $ScriptDir 'config') -Force | Out-Null
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

# ── Levantar stack ───────────────────────────────────────────────────────────
Write-Host 'Levantando memory-core + memory-hub + proxy...' -ForegroundColor Cyan
docker compose -f (Join-Path $ScriptDir 'docker-compose.yml') up -d
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
$proxyPort = Get-EnvValue 'PROXY_PORT'
if (-not $proxyPort) { $proxyPort = '8096' }
Write-Host ''
Write-Host '=== TencentDB Agent Memory UP ===' -ForegroundColor Green
Write-Host "  Panel UI     : http://localhost:$($(Get-EnvValue 'PANEL_PORT'))/" -NoNewline
Write-Host "  (login user_key: $($adminKey.Substring(0, 11))****$($adminKey.Substring($adminKey.Length - 4)))" -ForegroundColor DarkGray
Write-Host "  Knowledge    : http://localhost:$($(Get-EnvValue 'KNOWLEDGE_PORT'))/v3/"
Write-Host "  MemoryCore   : http://localhost:$corePort/"
Write-Host "  Proxy        : http://localhost:$proxyPort/"
Write-Host ''
Write-Host 'Siguiente: entra en el panel, crea Team -> Agent -> Task y copia sus' -ForegroundColor Yellow
Write-Host 'ids a las variables TDAI_USER_KEY / TDAI_TEAM_ID / TDAI_AGENT_ID /' -ForegroundColor Yellow
Write-Host 'TDAI_TASK_ID de .env (o del entorno), y reinicia opencode.' -ForegroundColor Yellow
