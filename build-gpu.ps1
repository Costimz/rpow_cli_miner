$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot

$gcc = Get-Command gcc -ErrorAction SilentlyContinue
if (-not $gcc) {
  Write-Error @"
gcc was not found.

Install MSYS2 from https://www.msys2.org/, open "MSYS2 MinGW x64", then run:
  pacman -S --needed mingw-w64-x86_64-gcc

After that, run this script again from PowerShell if gcc is available in PATH,
or build manually from the MSYS2 MinGW x64 shell:
  gcc -O2 rpow-gpu-miner.c -o rpow-gpu-miner.exe
"@
}

gcc -O2 rpow-gpu-miner.c -o rpow-gpu-miner.exe

if (-not (Test-Path .\rpow-gpu-miner.exe)) {
  Write-Error "Build appeared to succeed but rpow-gpu-miner.exe was not produced."
  exit 1
}

Write-Host "Built .\rpow-gpu-miner.exe"
Write-Host "Run: node rpow-cli.js mine --count 1 --engine gpu"
