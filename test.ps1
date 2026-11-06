# Runs the encode/decode harness against artifacts/native/<rid>/ on Windows.
# Used by .github/workflows/windows.yml; a pass writes test-result.txt.
# Usage: ./test.ps1 -Rid win-x64
param(
    [Parameter(Mandatory)]
    [ValidateSet('win-x64', 'win-arm64')]
    [string]$Rid
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$dir = "artifacts/native/$Rid"
Remove-Item "$dir/test-result.txt" -ErrorAction SilentlyContinue

dotnet build tests/Harness -c Release -o build/harness --nologo -v quiet
if ($LASTEXITCODE) { exit $LASTEXITCODE }

$env:JXL_NATIVE_PATH = (Resolve-Path "$dir/jxl_native.dll").Path
$log = & dotnet build/harness/Harness.dll 2>&1
$code = $LASTEXITCODE
$log | Write-Host
if ($code) { exit $code }

$header = "commit: $(git rev-parse HEAD)", "date: $((Get-Date).ToUniversalTime().ToString('s'))Z"
$header + $log | Set-Content "$dir/test-result.txt"
