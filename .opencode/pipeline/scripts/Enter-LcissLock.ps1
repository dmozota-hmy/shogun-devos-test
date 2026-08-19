param(
    [string]$Root,
    [Parameter(Mandatory)] [string]$RunId,
    [switch]$RecoverStaleLock
)

. (Join-Path $PSScriptRoot 'Pipeline.Common.ps1')
$rootPath = Get-LcissRoot -Root $Root
$paths = Get-LcissPaths -Root $rootPath
$pipeline = Get-LcissPipelineConfig -Paths $paths
Initialize-LcissRuntime -Paths $paths

if (Test-Path -LiteralPath $paths.LockDirectory) {
    $owner = if (Test-Path -LiteralPath $paths.LockOwner) {
        Get-Content -LiteralPath $paths.LockOwner -Raw | ConvertFrom-Json -Depth 10
    } else { $null }
    $created = (Get-Item -LiteralPath $paths.LockDirectory).CreationTimeUtc
    $age = [DateTime]::UtcNow - $created
    $ttl = [TimeSpan]::FromMinutes([int]$pipeline.lock.staleAfterMinutes)

    $activeOwner = $false
    if ($owner -and $owner.processId) {
        try {
            $process = Get-Process -Id ([int]$owner.processId) -ErrorAction Stop
            if (-not $owner.processStartedUtc -or $process.StartTime.ToUniversalTime().ToString('o') -eq $owner.processStartedUtc) {
                $activeOwner = $true
            }
        } catch { }
    }
    if ($activeOwner) {
        throw "LCISS lock is actively owned by process $($owner.processId) for run '$($owner.runId)'."
    }

    if ($age -lt $ttl) {
        $ownerRun = if ($owner) { $owner.runId } else { 'unknown' }
        throw "LCISS lock is active for run '$ownerRun' and is younger than $($ttl.TotalMinutes) minutes."
    }
    if (-not $RecoverStaleLock) {
        throw "LCISS lock is stale. Re-run with -RecoverStaleLock after human verification."
    }
    Remove-Item -LiteralPath $paths.LockDirectory -Recurse -Force
    Add-LcissEvent -Paths $paths -RunId $RunId -Type 'stale-lock-recovered' -Data $owner
}

New-Item -ItemType Directory -Path $paths.LockDirectory -ErrorAction Stop | Out-Null
$process = Get-Process -Id $PID
$owner = [ordered]@{
    runId = $RunId
    processId = $PID
    processStartedUtc = $process.StartTime.ToUniversalTime().ToString('o')
    acquiredAtUtc = [DateTime]::UtcNow.ToString('o')
    user = "$env:USERDOMAIN\$env:USERNAME"
}
Write-LcissAtomicJson -Path $paths.LockOwner -Value $owner
$owner | ConvertTo-Json -Depth 10
