param([string]$Root)

. (Join-Path $PSScriptRoot 'Pipeline.Common.ps1')
$rootPath = Get-LcissRoot -Root $Root
$paths = Get-LcissPaths -Root $rootPath
$errors = [System.Collections.Generic.List[string]]::new()

try { Get-Content -LiteralPath (Join-Path $rootPath 'opencode.json') -Raw | ConvertFrom-Json -Depth 20 | Out-Null }
catch { $errors.Add("Invalid opencode.json: $($_.Exception.Message)") }

$pipeline = $null
try { $pipeline = Get-LcissPipelineConfig -Paths $paths }
catch { $errors.Add($_.Exception.Message) }

if ($pipeline) {
    if ($pipeline.schemaVersion -ne '1.0') { $errors.Add('pipeline.json schemaVersion must be 1.0.') }
    foreach ($gate in 'test', 'lint', 'build') {
        $item = $pipeline.qualityGate.$gate
        if ($null -eq $item) { $errors.Add("Missing quality gate '$gate'."); continue }
        if ($item.required -and [string]::IsNullOrWhiteSpace($item.command)) {
            $errors.Add("Required quality gate '$gate' has no command.")
        }
        if (-not $item.required -and [string]::IsNullOrWhiteSpace($item.command) -and [string]::IsNullOrWhiteSpace($item.notApplicableReason)) {
            $errors.Add("Optional quality gate '$gate' needs a command or notApplicableReason.")
        }
    }
}

foreach ($path in @(
    '.opencode\pipeline\contracts\agent-output.v1.schema.json',
    '.opencode\pipeline\contracts\cycle-state.v1.schema.json',
    '.opencode\pipeline\AGENT_OUTPUT_PROTOCOL.md',
    '.opencode\pipeline\scripts\Invoke-LcissPipeline.ps1',
    '.opencode\pipeline\scripts\Invoke-QualityGate.ps1',
    '.opencode\pipeline\scripts\Test-AgentOutput.ps1'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $rootPath $path))) { $errors.Add("Missing LCISS enforcement asset '$path'.") }
}

$expected = @{
    'orchestrator.md' = 'primary'
    'architect.md' = 'subagent'
    'planner.md' = 'subagent'
    'developer.md' = 'subagent'
    'reviewer.md' = 'subagent'
    'refactor.md' = 'subagent'
    'knowledge.md' = 'subagent'
}
foreach ($entry in $expected.GetEnumerator()) {
    $path = Join-Path $rootPath ".opencode\agent\$($entry.Key)"
    if (-not (Test-Path -LiteralPath $path)) { $errors.Add("Missing agent file '$($entry.Key)'."); continue }
    $content = Get-Content -LiteralPath $path -Raw
    if ($content -notmatch "(?m)^mode: $($entry.Value)$") { $errors.Add("Agent '$($entry.Key)' must use mode '$($entry.Value)'.") }
    if ($content -notmatch '(?m)^model: github-copilot/gpt-5\.6-(terra|luna)$') { $errors.Add("Agent '$($entry.Key)' has an unsupported Copilot model.") }
    if ($entry.Value -eq 'subagent' -and $content -notmatch '(?m)^  task: deny$') { $errors.Add("Subagent '$($entry.Key)' must deny task delegation.") }
}

if ($errors.Count) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Host 'LCISS configuration is valid.' -ForegroundColor Green
