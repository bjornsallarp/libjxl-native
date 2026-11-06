# Runs the encode/decode harness against artifacts/native/<rid>/ on Windows, then
# smoke-tests a package of the Windows DLLs, letting .NET pick runtimes/<rid>/native/.
# Used by .github/workflows/windows.yml; a pass writes test-result.txt.
# Usage: ./test.ps1 -Rid win-x64
param(
    [Parameter(Mandatory)]
    [ValidateSet('win-x64', 'win-arm64')]
    [string]$Rid
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Invoke-Checked([scriptblock]$Command) {
    $out = & $Command 2>&1
    $code = $LASTEXITCODE
    $out | Write-Host
    if ($code) { exit $code }
    return $out
}

$dir = "artifacts/native/$Rid"
Remove-Item "$dir/test-result.txt" -ErrorAction SilentlyContinue

Invoke-Checked { dotnet build tests/Harness -c Release -o build/harness --nologo -v quiet } | Out-Null

# The dump (encoded .jxl plus source pixels) is uploaded for the djxl cross-check.
$env:JXL_NATIVE_PATH = (Resolve-Path "$dir/jxl_native.dll").Path
$log = Invoke-Checked { dotnet build/harness/Harness.dll --dump build/dump }
Remove-Item Env:JXL_NATIVE_PATH

Write-Host "==> $Rid (package)"
Invoke-Checked { dotnet pack src/LibJxl.Native -o build/package --nologo -v quiet } | Out-Null
$version = (Get-Item build/package/LibJxl.Native.*.nupkg).BaseName -replace '^LibJxl\.Native\.', ''
New-Item build/smoke/src -ItemType Directory -Force | Out-Null
Copy-Item tests/Harness/*.cs, tests/Harness/Harness.csproj build/smoke/src/
Invoke-Checked {
    dotnet build build/smoke/src -c Release -o build/smoke/app --nologo -v quiet `
        "-p:LibJxlNativeVersion=$version" "-p:RestoreSources=$((Resolve-Path build/package).Path)" `
        "-p:RestorePackagesPath=$PWD/build/smoke/packages"
} | Out-Null
$smokeLog = Invoke-Checked { dotnet build/smoke/app/Harness.dll }

$header = "commit: $(git rev-parse HEAD)", "date: $((Get-Date).ToUniversalTime().ToString('s'))Z"
$header + $log + "package smoke test ($version):" + $smokeLog + "OK" | Set-Content "$dir/test-result.txt"
