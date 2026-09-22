#Requires -RunAsAdministrator
param(
    [string]$PythonPath = "",
    [string]$ExtensionPath = "E:/ShunCode/resources/app/extensions/shuncode"
)
$ErrorActionPreference = "Stop"
$logPath = Join-Path $PSScriptRoot "install-admin.log"
$statusPath = Join-Path $PSScriptRoot "install-status.json"
try {
    if (-not $PythonPath) { $PythonPath = (Get-Command python -ErrorAction Stop).Source }
    & $PythonPath (Join-Path $PSScriptRoot "install.py") --extension $ExtensionPath 2>&1 | Tee-Object -FilePath $logPath
    $code = $LASTEXITCODE
    @{ success = ($code -eq 0); exitCode = $code; reloadRequired = ($code -eq 0); finishedAt = (Get-Date).ToString("o") } | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding UTF8
    exit $code
} catch {
    $_ | Out-String | Add-Content -LiteralPath $logPath -Encoding UTF8
    @{ success = $false; error = $_.Exception.Message; reloadRequired = $false; finishedAt = (Get-Date).ToString("o") } | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding UTF8
    exit 1
}
