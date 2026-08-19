param(
    [string]$Root,
    [Parameter(Mandatory)] [string]$Path
)

. (Join-Path $PSScriptRoot 'Pipeline.Common.ps1')
$rootPath = Get-LcissRoot -Root $Root
$paths = Get-LcissPaths -Root $rootPath
$pipeline = Get-LcissPipelineConfig -Paths $paths
$state = Get-LcissState -Paths $paths
if ($null -eq $state) { throw 'No active LCISS state exists.' }

try { $output = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 20 }
catch { throw "Invalid agent output JSON: $($_.Exception.Message)" }

$required = 'contractVersion', 'runId', 'taskId', 'agent', 'status', 'summary', 'artifacts', 'qualityEvidence', 'next', 'issues', 'timestampUtc'
foreach ($property in $required) {
    if ($null -eq $output.PSObject.Properties[$property]) {
        throw "Agent output is missing '$property'."
    }
}
foreach ($property in 'contractVersion', 'runId', 'taskId', 'agent', 'status', 'summary', 'next', 'timestampUtc') {
    if ([string]::IsNullOrWhiteSpace([string]$output.$property)) {
        throw "Agent output has an empty '$property'."
    }
}
if ($output.contractVersion -ne '1.0') { throw 'Unsupported agent output contractVersion.' }
if ($output.runId -ne $state.runId -or $output.taskId -ne $state.taskId) { throw 'Agent output does not match active run/task.' }
if ($output.agent -notin @('orchestrator', 'architect', 'planner', 'developer', 'reviewer', 'refactor', 'knowledge')) { throw 'Unknown agent.' }
if ($output.status -notin @('succeeded', 'failed', 'blocked', 'rejected')) { throw 'Invalid output status.' }
if ($output.next -notin @('context', 'architecture', 'implementation', 'quality-gate', 'review', 'remediation', 'completed', 'blocked', 'failed', 'escalated')) { throw 'Invalid next state.' }
if ($output.agent -eq 'reviewer' -and $output.reviewVerdict -notin @('APROBADO', 'CAMBIOS REQUERIDOS', 'RECHAZADO')) { throw 'Reviewer output requires reviewVerdict.' }

$expectedAgent = switch ($state.state) {
    'context' { $pipeline.agents.context }
    'architecture' { $pipeline.agents.architecture }
    'implementation' { $pipeline.agents.implementation }
    'remediation' { $pipeline.agents.remediation }
    'review' { $pipeline.agents.review }
    'quality-gate' { 'orchestrator' }
    default { $null }
}
if ($expectedAgent -and $output.agent -ne $expectedAgent) {
    throw "State '$($state.state)' accepts output only from '$expectedAgent', not '$($output.agent)'."
}

foreach ($gate in 'tests', 'lint', 'build') {
    if ($null -eq $output.qualityEvidence.PSObject.Properties[$gate] -or $output.qualityEvidence.$gate -notin @('passed', 'failed', 'not-run', 'not-applicable')) {
        throw "Invalid qualityEvidence.$gate."
    }
}
if ($state.state -eq 'quality-gate') {
    $failedGate = @('tests', 'lint', 'build') | Where-Object { $output.qualityEvidence.$_ -in @('failed', 'not-run') }
    if ($output.next -eq 'review' -and $failedGate.Count) {
        throw 'Quality gate cannot transition to review without passed or not-applicable evidence for every gate.'
    }
}

if ($output.agent -eq 'reviewer') {
    switch ($output.reviewVerdict) {
        'APROBADO' { if ($output.next -ne 'completed') { throw 'An approved review must transition to completed.' } }
        'CAMBIOS REQUERIDOS' { if ($output.next -ne 'remediation') { throw 'Requested changes must transition to remediation.' } }
        'RECHAZADO' { if ($output.next -notin @('blocked', 'failed', 'escalated')) { throw 'A rejected review must stop or escalate the pipeline.' } }
    }
}

if ($output.status -in @('failed', 'blocked')) {
    if ($output.next -notin @('failed', 'blocked', 'escalated')) { throw 'Failed or blocked output must stop or escalate the pipeline.' }
} else {
    Assert-LcissTransition -Pipeline $pipeline -From $state.state -To $output.next
}

$output | ConvertTo-Json -Depth 20
