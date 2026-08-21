#Requires -Version 7
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [ValidateSet('Auto', 'Local', 'GitHub')]
    [string]$Source = 'Auto',
    [string]$TemplatePath = '',
    [string]$Repository = 'https://github.com/dmozota-hmy/shogun-devos.git',
    [string]$Branch = 'master'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path -LiteralPath $Root).Path
$configDirectory = Join-Path $projectRoot '.shogun\config'
$syncDirectories = @('.opencode', '.shogun')
$protectedShogunPath = '.shogun\tools\Sync-ShogunTemplate.ps1'
$temporarySource = $null

function Resolve-TemplateSource {
    if ($Source -eq 'Local' -or ($Source -eq 'Auto' -and $TemplatePath)) {
        if (-not $TemplatePath) {
            $TemplatePath = Join-Path (Split-Path $projectRoot -Parent) 'OpenCodeConfiguration'
        }
        if (-not (Test-Path -LiteralPath $TemplatePath)) { throw "Local template not found: $TemplatePath" }
        return (Resolve-Path -LiteralPath $TemplatePath).Path
    }

    if ($Source -eq 'Auto') {
        $sibling = Join-Path (Split-Path $projectRoot -Parent) 'OpenCodeConfiguration'
        if (Test-Path -LiteralPath (Join-Path $sibling 'opencode.json')) { return (Resolve-Path -LiteralPath $sibling).Path }
    }

    $script:temporarySource = Join-Path ([System.IO.Path]::GetTempPath()) ("shogun-template-{0}" -f [guid]::NewGuid())
    $cloneTarget = $script:temporarySource
    & git clone --depth 1 --branch $Branch -- $Repository $cloneTarget
    if ($LASTEXITCODE -ne 0) { throw "Unable to clone template from $Repository@$Branch" }
    return $script:temporarySource
}

function Remove-ContentsExcept {
    param([string]$Directory, [string[]]$KeepRelativePaths = @())

    if (-not (Test-Path -LiteralPath $Directory)) { return }
    foreach ($item in @(Get-ChildItem -LiteralPath $Directory -Force)) {
        $relative = $item.FullName.Substring($projectRoot.Length).TrimStart('\', '/')
        if ($KeepRelativePaths -contains $relative) { continue }
        if ($PSCmdlet.ShouldProcess($item.FullName, 'Remove template-managed content')) {
            Remove-Item -LiteralPath $item.FullName -Recurse -Force
        }
    }
}

function Copy-DirectoryContents {
    param([string]$SourceDirectory, [string]$DestinationDirectory)

    New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
    foreach ($item in @(Get-ChildItem -LiteralPath $SourceDirectory -Force | Where-Object {
        $_.Name -notin @('node_modules', 'tools', 'package.json', 'package-lock.json')
    })) {
        Copy-Item -LiteralPath $item.FullName -Destination $DestinationDirectory -Recurse -Force
    }
}

function Remove-LegacyShogunContent {
    $legacyPaths = @(
        'deploy\memory',
        'templates\demo-static',
        'tools\Configure-ShogunMemory.ps1',
        'tools\Initialize-ShogunDevOS.ps1',
        'tools\Test-DemoMemoryGarden.ps1',
        'tools\Test-ShogunPrerequisites.ps1',
        'tools\shogun-memory-mcp.mjs'
    )
    foreach ($relativePath in $legacyPaths) {
        $path = Join-Path $projectRoot $relativePath
        if ((Test-Path -LiteralPath $path) -and $PSCmdlet.ShouldProcess($path, 'Remove legacy Shogun content')) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}

try {
    $templateRoot = Resolve-TemplateSource
    if (-not (Test-Path -LiteralPath (Join-Path $templateRoot 'opencode.json'))) { throw "Template is missing opencode.json: $templateRoot" }
    foreach ($directory in $syncDirectories) {
        if (-not (Test-Path -LiteralPath (Join-Path $templateRoot $directory))) { throw "Template is missing $directory/: $templateRoot" }
    }

    New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
    $protected = @($protectedShogunPath)
    Remove-ContentsExcept -Directory (Join-Path $projectRoot '.opencode')
    Remove-ContentsExcept -Directory (Join-Path $projectRoot '.shogun') -KeepRelativePaths @('.shogun\config')
    Remove-LegacyShogunContent

    Copy-DirectoryContents -SourceDirectory (Join-Path $templateRoot '.opencode') -DestinationDirectory (Join-Path $projectRoot '.opencode')
    foreach ($item in @(Get-ChildItem -LiteralPath (Join-Path $templateRoot '.shogun') -Force)) {
        if ($item.Name -eq 'config') { continue }
        Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $projectRoot '.shogun') -Recurse -Force
    }

    $templateConfig = Join-Path $templateRoot '.shogun\config'
    if (Test-Path -LiteralPath $templateConfig) {
        foreach ($item in @(Get-ChildItem -LiteralPath $templateConfig -Force)) {
            $destination = Join-Path $configDirectory $item.Name
            if (-not (Test-Path -LiteralPath $destination)) {
                Copy-Item -LiteralPath $item.FullName -Destination $destination -Recurse -Force
            }
        }
    }

    Copy-Item -LiteralPath (Join-Path $templateRoot 'opencode.json') -Destination (Join-Path $projectRoot 'opencode.json') -Force
    [ordered]@{ status = 'succeeded'; source = $templateRoot; preserved = @('.shogun/config/*'); synchronized = @('.opencode/*', '.shogun/deploy/*', '.shogun/templates/*', '.shogun/tools/*', 'opencode.json') } | ConvertTo-Json -Depth 5
}
finally {
    if ($script:temporarySource -and (Test-Path -LiteralPath $script:temporarySource)) { Remove-Item -LiteralPath $script:temporarySource -Recurse -Force -ErrorAction SilentlyContinue }
}
