Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LcissRoot {
    param([string]$Root)

    if ($Root) { return (Resolve-Path -LiteralPath $Root).Path }
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
}

function Get-LcissPaths {
    param([string]$Root)

    $runtime = Join-Path $Root '.lciss'
    return [pscustomobject]@{
        Root = $Root
        Pipeline = Join-Path $Root '.opencode\pipeline\pipeline.json'
        StateDirectory = Join-Path $runtime 'state'
        State = Join-Path $runtime 'state\current.json'
        Events = Join-Path $runtime 'state\events.ndjson'
        LockDirectory = Join-Path $runtime 'lock'
        LockOwner = Join-Path $runtime 'lock\owner.json'
        Outputs = Join-Path $runtime 'outputs'
        Logs = Join-Path $runtime 'logs'
    }
}

function Initialize-LcissRuntime {
    param([pscustomobject]$Paths)

    @($Paths.StateDirectory, $Paths.Outputs, $Paths.Logs) | ForEach-Object {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
    }
}

function Get-LcissPipelineConfig {
    param([pscustomobject]$Paths)

    if (-not (Test-Path -LiteralPath $Paths.Pipeline)) {
        throw "Missing pipeline configuration: $($Paths.Pipeline)"
    }
    return Get-Content -LiteralPath $Paths.Pipeline -Raw | ConvertFrom-Json -Depth 20
}

function Write-LcissAtomicJson {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] $Value
    )

    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporary = Join-Path $directory (".{0}.{1}.tmp" -f (Split-Path -Leaf $Path), [guid]::NewGuid())
    $json = $Value | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Get-LcissState {
    param([pscustomobject]$Paths)

    if (-not (Test-Path -LiteralPath $Paths.State)) { return $null }
    return Get-Content -LiteralPath $Paths.State -Raw | ConvertFrom-Json -Depth 20
}

function Write-LcissState {
    param(
        [pscustomobject]$Paths,
        [Parameter(Mandatory)] $State
    )

    $State.updatedAtUtc = [DateTime]::UtcNow.ToString('o')
    Write-LcissAtomicJson -Path $Paths.State -Value $State
}

function Add-LcissEvent {
    param(
        [pscustomobject]$Paths,
        [Parameter(Mandatory)] [string]$RunId,
        [Parameter(Mandatory)] [string]$Type,
        $Data
    )

    New-Item -ItemType Directory -Path $Paths.StateDirectory -Force | Out-Null
    $event = [ordered]@{
        timestampUtc = [DateTime]::UtcNow.ToString('o')
        runId = $RunId
        type = $Type
        data = $Data
    } | ConvertTo-Json -Depth 20 -Compress
    Add-Content -LiteralPath $Paths.Events -Value $event -Encoding utf8
}

function Assert-LcissTransition {
    param(
        [Parameter(Mandatory)] $Pipeline,
        [Parameter(Mandatory)] [string]$From,
        [Parameter(Mandatory)] [string]$To
    )

    $allowed = @($Pipeline.transitions.$From)
    if ($To -notin $allowed) {
        throw "Invalid LCISS transition: $From -> $To"
    }
}
