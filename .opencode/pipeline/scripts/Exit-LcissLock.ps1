param(
    [string]$Root,
    [Parameter(Mandatory)] [string]$RunId
)

. (Join-Path $PSScriptRoot 'Pipeline.Common.ps1')
$rootPath = Get-LcissRoot -Root $Root
$paths = Get-LcissPaths -Root $rootPath

if (-not (Test-Path -LiteralPath $paths.LockOwner)) {
    throw 'No LCISS lock owner was found.'
}
$owner = Get-Content -LiteralPath $paths.LockOwner -Raw | ConvertFrom-Json -Depth 10
if ($owner.runId -ne $RunId) {
    throw "Run '$RunId' cannot release a lock owned by '$($owner.runId)'."
}
Remove-Item -LiteralPath $paths.LockDirectory -Recurse -Force
Add-LcissEvent -Paths $paths -RunId $RunId -Type 'lock-released' -Data $null
