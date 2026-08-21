#Requires -Version 7
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [ValidateSet('Local', 'Remote')] [string]$Mode,
    [string]$MemoryUrl,
    [string]$KnowledgeUrl,
    [string]$TeamId,
    [string]$AgentId,
    [string]$TaskId,
    [string]$SessionId = 'shogun-devos-project',
    [switch]$UseLocalAdminKey
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$directory = Join-Path $Root '.shogun\config'
New-Item -ItemType Directory -Path $directory -Force | Out-Null

function Read-SecretValue {
    param([string]$Prompt)
    $secure = Read-Host -Prompt $Prompt -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

if (-not $Mode) { $Mode = if ((Read-Host 'Use local TencentDB at localhost? [Y/n]') -match '^(|y|yes|s|si)$') { 'Local' } else { 'Remote' } }
if ($Mode -eq 'Local') {
    if (-not $MemoryUrl) { $MemoryUrl = 'http://127.0.0.1:8420' }
    if (-not $KnowledgeUrl) { $KnowledgeUrl = 'http://127.0.0.1:8424' }
} else {
    if (-not $MemoryUrl) { $MemoryUrl = Read-Host 'TencentDB Memory Core URL (example: https://memory.example.com)' }
    if (-not $KnowledgeUrl) { $KnowledgeUrl = Read-Host 'TencentDB Knowledge URL (example: https://knowledge.example.com)' }
}
$adminKeyPath = Join-Path $Root '.shogun\config\.admin-key'
if (-not $env:TDAI_USER_KEY -and $Mode -eq 'Local' -and (Test-Path -LiteralPath $adminKeyPath)) { $env:TDAI_USER_KEY = (Get-Content -LiteralPath $adminKeyPath -Raw).Trim() }
$userKey = if ($env:TDAI_USER_KEY) { $env:TDAI_USER_KEY } elseif ($UseLocalAdminKey -and (Test-Path -LiteralPath $adminKeyPath)) { (Get-Content -LiteralPath $adminKeyPath -Raw).Trim() } else { Read-SecretValue 'TencentDB user_key (hidden input)' }
if (-not $TeamId) { $TeamId = Read-Host 'TencentDB team_id' }
if (-not $AgentId) { $AgentId = Read-Host 'TencentDB agent_id for Shogun Knowledge' }
if (-not $TaskId) { $TaskId = Read-Host 'TencentDB task_id for project memory' }
$gatewayKey = if ($env:TDAI_MEMORY_API_KEY) { $env:TDAI_MEMORY_API_KEY } elseif ($Mode -eq 'Remote') { Read-SecretValue 'TencentDB gateway API key (hidden, leave empty only if disabled)' } else { '' }
foreach ($entry in @(@{ name = 'MemoryUrl'; value = $MemoryUrl }, @{ name = 'KnowledgeUrl'; value = $KnowledgeUrl }, @{ name = 'UserKey'; value = $userKey }, @{ name = 'TeamId'; value = $TeamId }, @{ name = 'AgentId'; value = $AgentId }, @{ name = 'TaskId'; value = $TaskId })) { if ([string]::IsNullOrWhiteSpace($entry.value)) { throw "$($entry.name) is required." } }
$config = [ordered]@{ memoryUrl = $MemoryUrl.Trim(); knowledgeUrl = $KnowledgeUrl.Trim(); serviceId = 'default'; userKey = $userKey.Trim(); gatewayKey = $gatewayKey.Trim(); teamId = $TeamId.Trim(); agentId = $AgentId.Trim(); taskId = $TaskId.Trim(); sessionId = $SessionId }
$config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $directory 'memory.json') -Encoding utf8
Write-Host "Saved TencentDB configuration in $directory\memory.json (ignored by Git)." -ForegroundColor Green
