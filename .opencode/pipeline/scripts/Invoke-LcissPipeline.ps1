param(
    [ValidateSet('Start', 'RecordOutput', 'Finish')]
    [Parameter(Mandatory)] [string]$Action,
    [string]$Root,
    [string]$TaskId,
    [string]$OutputPath,
    [ValidateSet('completed', 'blocked', 'failed', 'escalated')]
    [string]$Outcome,
    [switch]$RecoverStaleLock
)

. (Join-Path $PSScriptRoot 'Pipeline.Common.ps1')
$rootPath = Get-LcissRoot -Root $Root
$paths = Get-LcissPaths -Root $rootPath
Initialize-LcissRuntime -Paths $paths

switch ($Action) {
    'Start' {
        if ([string]::IsNullOrWhiteSpace($TaskId)) { throw 'Start requires -TaskId.' }
        & (Join-Path $PSScriptRoot 'Test-LcissConfig.ps1') -Root $rootPath
        if (Get-LcissState -Paths $paths) { throw 'An LCISS state already exists. Finish or recover it first.' }
        $runId = [guid]::NewGuid().ToString()
        & (Join-Path $PSScriptRoot 'Enter-LcissLock.ps1') -Root $rootPath -RunId $runId -RecoverStaleLock:$RecoverStaleLock | Out-Null
        $now = [DateTime]::UtcNow.ToString('o')
        $state = [pscustomobject]@{
            schemaVersion = '1.0'; runId = $runId; taskId = $TaskId; state = 'context'; status = 'active'; activeAgent = 'knowledge'; remediationAttempts = 0; consecutiveFailures = 0; startedAtUtc = $now; updatedAtUtc = $now
        }
        Write-LcissState -Paths $paths -State $state
        Add-LcissEvent -Paths $paths -RunId $runId -Type 'run-started' -Data $state
        $state | ConvertTo-Json -Depth 10
    }
    'RecordOutput' {
        if ([string]::IsNullOrWhiteSpace($OutputPath)) { throw 'RecordOutput requires -OutputPath.' }
        $state = Get-LcissState -Paths $paths
        if ($null -eq $state -or $state.status -ne 'active') { throw 'No active LCISS run exists.' }
        $validated = & (Join-Path $PSScriptRoot 'Test-AgentOutput.ps1') -Root $rootPath -Path $OutputPath | ConvertFrom-Json -Depth 20
        $directory = Join-Path $paths.Outputs $state.runId
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $destination = Join-Path $directory ("{0}-{1}.json" -f $state.state, $validated.agent)
        if (Test-Path -LiteralPath $destination) { throw "Output already recorded: $destination" }
        Copy-Item -LiteralPath $OutputPath -Destination $destination
        $state.state = $validated.next
        $state.activeAgent = switch ($validated.next) {
            'context' { $pipeline.agents.context }
            'architecture' { $pipeline.agents.architecture }
            'implementation' { $pipeline.agents.implementation }
            'remediation' { $pipeline.agents.remediation }
            'review' { $pipeline.agents.review }
            'quality-gate' { 'orchestrator' }
            default { $null }
        }
        if ($validated.next -eq 'remediation') { $state.remediationAttempts++ }
        if ($validated.status -in @('failed', 'blocked', 'rejected')) { $state.consecutiveFailures++ } else { $state.consecutiveFailures = 0 }
        if ($validated.next -in @('blocked', 'failed', 'escalated')) { $state.status = $validated.next }
        if ($state.consecutiveFailures -ge [int]$pipeline.limits.maxConsecutiveFailures) { $state.state = 'escalated'; $state.status = 'escalated'; $state.activeAgent = $null }
        if ($state.remediationAttempts -gt [int]$pipeline.limits.maxRemediationAttempts) { $state.state = 'escalated'; $state.status = 'escalated'; $state.activeAgent = $null }
        Write-LcissState -Paths $paths -State $state
        Add-LcissEvent -Paths $paths -RunId $state.runId -Type 'agent-output-recorded' -Data $validated
        $state | ConvertTo-Json -Depth 10
    }
    'Finish' {
        if ([string]::IsNullOrWhiteSpace($Outcome)) { throw 'Finish requires -Outcome.' }
        $state = Get-LcissState -Paths $paths
        if ($null -eq $state) { throw 'No LCISS state exists.' }
        $state.state = $Outcome
        $state.status = $Outcome
        $state.activeAgent = $null
        Write-LcissState -Paths $paths -State $state
        Add-LcissEvent -Paths $paths -RunId $state.runId -Type 'run-finished' -Data @{ outcome = $Outcome }
        & (Join-Path $PSScriptRoot 'Exit-LcissLock.ps1') -Root $rootPath -RunId $state.runId
        Remove-Item -LiteralPath $paths.State -Force
    }
}
