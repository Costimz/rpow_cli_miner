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
  gcc -O3 -march=native -pthread rpow-native-miner.c -o rpow-native-miner.exe
"@
}

gcc -O3 -march=native -pthread rpow-native-miner.c -o rpow-native-miner.exe

if (-not (Test-Path .\rpow-native-miner.exe)) {
  Write-Error "Build appeared to succeed but rpow-native-miner.exe was not produced."
  exit 1
}

Write-Host "Built .\rpow-native-miner.exe"
Write-Host "Run: node rpow-cli.js mine --count 1 --engine native"
