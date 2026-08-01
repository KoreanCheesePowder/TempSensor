$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot

function Invoke-ST {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)
  & smartthings @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "SmartThings CLI command failed: smartthings $($Arguments -join ' ')"
  }
}

if (-not (Get-Command smartthings.exe -ErrorAction SilentlyContinue) -and
    -not (Get-Command smartthings -ErrorAction SilentlyContinue)) {
  throw "SmartThings CLI was not found. Install it or add it to PATH, then run this installer again."
}

Write-Host "============================================================" -ForegroundColor DarkGray
Write-Host "C.P TempSensor 0.1C v1.4.0" -ForegroundColor Cyan
Write-Host "Author: CheesePowder" -ForegroundColor DarkGray
Write-Host "============================================================" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Packaging and installing the Edge driver..." -ForegroundColor Cyan
Write-Host "Select the requested channel or hub when prompted." -ForegroundColor Yellow
Write-Host ""
Invoke-ST -Arguments @("edge:drivers:package", ".", "--install")

Write-Host ""
Write-Host "Installation completed: C.P TempSensor 0.1C v1.4.0" -ForegroundColor Green
Write-Host "Open SmartThings and change the sensor driver to C.P TempSensor 0.1C." -ForegroundColor Yellow
