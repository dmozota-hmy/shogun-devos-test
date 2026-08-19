param(
    [string]$Root,
    [string]$RunId = 'manual'
)

. (Join-Path $PSScriptRoot 'Pipeline.Common.ps1')
$rootPath = Get-LcissRoot -Root $Root
$paths = Get-LcissPaths -Root $rootPath
$pipeline = Get-LcissPipelineConfig -Paths $paths
Initialize-LcissRuntime -Paths $paths

$result = [ordered]@{}
foreach ($name in 'test', 'lint', 'build') {
    $gate = $pipeline.qualityGate.$name
    if ([string]::IsNullOrWhiteSpace($gate.command)) {
        if ($gate.required) { throw "Required quality gate '$name' has no command." }
        $result[$name] = [ordered]@{ status = 'not-applicable'; durationMs = 0; output = $gate.notApplicableReason }
        continue
    }

    $log = Join-Path $paths.Logs "$RunId-$name.log"
    $started = [DateTime]::UtcNow
    Push-Location $rootPath
    try {
        & pwsh -NoProfile -Command $gate.command *> $log
        $exitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    $duration = [int]([DateTime]::UtcNow - $started).TotalMilliseconds
    $result[$name] = [ordered]@{
        status = if ($exitCode -eq 0) { 'passed' } else { 'failed' }
        durationMs = $duration
        output = $log
        exitCode = $exitCode
    }
}

$result | ConvertTo-Json -Depth 10
if (@($result.Values | Where-Object { $_.status -eq 'failed' }).Count) { exit 1 }
