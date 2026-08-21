#Requires -Version 7
param([string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$files = @('demo-memory-garden\index.html', 'demo-memory-garden\app.js', 'demo-memory-garden\styles.css')
foreach ($relativePath in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $relativePath))) { throw "Missing demo file: $relativePath" }
}
$html = Get-Content -LiteralPath (Join-Path $Root 'demo-memory-garden\index.html') -Raw
$js = Get-Content -LiteralPath (Join-Path $Root 'demo-memory-garden\app.js') -Raw
if ($html -notmatch 'id="memory"' -or $html -notmatch 'id="save"' -or $html -notmatch 'id="memories"') { throw 'The Memory Garden HTML is missing required controls.' }
if ($js -notmatch 'localStorage' -or $js -notmatch 'shogun-memory-garden') { throw 'The Memory Garden JavaScript does not persist browser memories.' }
Write-Host 'Memory Garden demo verification passed.' -ForegroundColor Green
