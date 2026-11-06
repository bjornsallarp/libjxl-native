# Smoke-tests artifacts/package/LibJxl.Native.*.nupkg on Windows, the way a consumer
# uses it: a fresh copy of the harness restores the package from that folder only,
# and .NET resolves runtimes/<rid>/native/ itself. Counterpart of smoke.sh.
# Usage: ./smoke.ps1 -Rid win-x64
param(
    [Parameter(Mandatory)]
    [ValidateSet('win-x64', 'win-arm64')]
    [string]$Rid
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$nupkg = Get-Item artifacts/package/LibJxl.Native.*.nupkg
$version = $nupkg.BaseName -replace '^LibJxl\.Native\.', ''

Remove-Item build/smoke -Recurse -ErrorAction SilentlyContinue
New-Item build/smoke/src -ItemType Directory -Force | Out-Null
Copy-Item tests/Harness/*.cs, tests/Harness/Harness.csproj build/smoke/src/
dotnet build build/smoke/src -c Release -o build/smoke/app --nologo -v quiet `
    "-p:LibJxlNativeVersion=$version" "-p:RestoreSources=$($nupkg.DirectoryName)" `
    "-p:RestorePackagesPath=$PWD/build/smoke/packages" | Out-Null
if ($LASTEXITCODE) { exit $LASTEXITCODE }

Write-Host "==> $Rid ($($nupkg.Name))"
Remove-Item Env:JXL_NATIVE_PATH -ErrorAction SilentlyContinue
& dotnet build/smoke/app/Harness.dll
exit $LASTEXITCODE
