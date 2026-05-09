#requires -Version 5.1
<#
.SYNOPSIS
  One-shot installer + launcher for the rpow GPU miner on Windows.

.DESCRIPTION
  Run this from PowerShell. It will:
    1. Install prerequisites with winget if missing (Git, Node.js LTS, MinGW gcc).
    2. Clone (or update) the rpow_cli_miner repo into $env:USERPROFILE\rpow-cli.
    3. Build the GPU miner binary.
    4. Walk you through magic-link login.
    5. Start mining in continuous mode against your GPU.

  All state (session cookies, saved challenge) lives in $env:USERPROFILE\.rpow-cli\state.json.

.PARAMETER Email
  Your account email. If omitted, the script will prompt.

.PARAMETER Repo
  Override the GitHub repo URL. Default is the official one.

.PARAMETER Branch
  Override the branch to clone. Default is main.

.PARAMETER InstallDir
  Where to clone the miner. Default $env:USERPROFILE\rpow-cli.

.PARAMETER SkipMine
  Stop after install + login; don't start mining.

.EXAMPLE
  irm https://raw.githubusercontent.com/fashaking/rpow_cli_miner/main/install.ps1 | iex

.EXAMPLE
  # With pre-supplied email, no prompt:
  $env:RPOW_EMAIL="you@example.com"; irm https://raw.githubusercontent.com/fashaking/rpow_cli_miner/main/install.ps1 | iex
#>

param(
  [string]$Email      = $env:RPOW_EMAIL,
  [string]$Repo       = "https://github.com/fashaking/rpow_cli_miner.git",
  [string]$Branch     = "main",
  [string]$InstallDir = (Join-Path $env:USERPROFILE "rpow-cli"),
  [switch]$SkipMine
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

function Write-Step($msg)  { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn2($msg) { Write-Host "    $msg" -ForegroundColor Yellow }
function Have($cmd)        { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

function Refresh-Path {
  $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
  $user    = [Environment]::GetEnvironmentVariable("Path", "User")
  $env:Path = ($machine, $user, "C:\Program Files\Git\cmd", "C:\msys64\mingw64\bin") -join ";"
}

function Ensure-Winget {
  if (Have winget) { return }
  throw "winget is not available. Install 'App Installer' from the Microsoft Store, then re-run this script."
}

function Winget-Install($id, $friendly) {
  Write-Step "Installing $friendly via winget ($id)"
  $args = @("install","--id",$id,"-e","--silent","--accept-source-agreements","--accept-package-agreements")
  & winget @args | Out-Null
  Refresh-Path
}

function Ensure-Git {
  if (Have git) { Write-Ok "git found"; return }
  Ensure-Winget
  Winget-Install "Git.Git" "Git"
  if (-not (Have git)) { throw "git still not on PATH after install. Open a new PowerShell window and re-run." }
  Write-Ok "git installed"
}

function Ensure-Node {
  if (Have node) {
    $v = (& node -v).Trim().TrimStart("v")
    $major = [int]($v.Split(".")[0])
    if ($major -ge 18) { Write-Ok "node $v found"; return }
    Write-Warn2 "node $v is too old; installing LTS"
  }
  Ensure-Winget
  Winget-Install "OpenJS.NodeJS.LTS" "Node.js LTS"
  if (-not (Have node)) { throw "node still not on PATH after install. Open a new PowerShell window and re-run." }
  Write-Ok "node $((& node -v).Trim()) installed"
}

function Ensure-Gcc {
  if (Have gcc) { Write-Ok "gcc found"; return }
  Ensure-Winget
  # MSYS2 gives us a real MinGW gcc that works for both build-native.ps1 and build-gpu.ps1.
  Winget-Install "MSYS2.MSYS2" "MSYS2 (provides MinGW gcc)"
  $mingw = "C:\msys64\mingw64\bin"
  if (Test-Path $mingw) {
    $env:Path = "$mingw;$env:Path"
  }
  if (-not (Have gcc)) {
    Write-Warn2 "gcc not yet on PATH; bootstrapping the MinGW toolchain inside MSYS2"
    $bash = "C:\msys64\usr\bin\bash.exe"
    if (Test-Path $bash) {
      & $bash -lc "pacman -Sy --noconfirm --needed mingw-w64-x86_64-gcc" | Out-Null
    }
    if (Test-Path $mingw) { $env:Path = "$mingw;$env:Path" }
  }
  if (-not (Have gcc)) {
    throw "gcc still not available. Open 'MSYS2 MinGW x64' from the Start Menu, run 'pacman -S --needed mingw-w64-x86_64-gcc', then re-run this script."
  }
  Write-Ok "gcc installed"
}

function Ensure-Repo {
  if (Test-Path (Join-Path $InstallDir ".git")) {
    Write-Step "Updating existing checkout in $InstallDir"
    Push-Location $InstallDir
    try {
      & git fetch --depth 1 origin $Branch | Out-Null
      & git checkout $Branch | Out-Null
      & git reset --hard "origin/$Branch" | Out-Null
    } finally { Pop-Location }
  } else {
    Write-Step "Cloning $Repo into $InstallDir"
    & git clone --depth 1 --branch $Branch $Repo $InstallDir | Out-Null
  }
  Write-Ok "repo ready"
}

function Build-GpuMiner {
  Write-Step "Building GPU miner"
  Push-Location $InstallDir
  try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File ".\build-gpu.ps1"
  } finally { Pop-Location }
  if (-not (Test-Path (Join-Path $InstallDir "rpow-gpu-miner.exe"))) {
    throw "GPU miner build failed; rpow-gpu-miner.exe not found."
  }
  Write-Ok "GPU miner built"
}

function Build-NativeMinerOptional {
  # CPU fallback. Don't fail the install if it can't build.
  Write-Step "Building CPU fallback miner (optional)"
  Push-Location $InstallDir
  try {
    try {
      & powershell -NoProfile -ExecutionPolicy Bypass -File ".\build-native.ps1"
      Write-Ok "CPU miner built"
    } catch {
      Write-Warn2 "CPU fallback build failed; GPU mining will still work. ($($_.Exception.Message))"
    }
  } finally { Pop-Location }
}

function Get-StateFile {
  $stateDir = Join-Path $env:USERPROFILE ".rpow-cli"
  if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir | Out-Null }
  return (Join-Path $stateDir "state.json")
}

function Test-LoggedIn($stateFile) {
  if (-not (Test-Path $stateFile)) { return $false }
  Push-Location $InstallDir
  try {
    $null = & node "rpow-cli.js" me --state $stateFile 2>$null
    return ($LASTEXITCODE -eq 0)
  } finally { Pop-Location }
}

function Do-Login($stateFile) {
  if (-not $Email) {
    $Email = Read-Host "Enter your rpow2.com account email"
  }
  if (-not $Email) { throw "Email is required to log in." }

  Write-Step "Requesting magic link for $Email"
  Push-Location $InstallDir
  try {
    & node "rpow-cli.js" login --email $Email --state $stateFile
    if ($LASTEXITCODE -ne 0) { throw "login request failed" }

    Write-Host ""
    Write-Host "Check your inbox for an email from rpow2.com." -ForegroundColor Yellow
    Write-Host "Copy the magic link from the email and paste it below." -ForegroundColor Yellow
    $link = Read-Host "Paste magic link"
    if (-not $link) { throw "No magic link provided." }

    & node "rpow-cli.js" complete-login --link $link --state $stateFile
    if ($LASTEXITCODE -ne 0) { throw "complete-login failed" }
  } finally { Pop-Location }
  Write-Ok "logged in"
}

function Start-Mining($stateFile) {
  Write-Step "Starting GPU miner (Ctrl+C to stop)"
  Push-Location $InstallDir
  try {
    & node "rpow-cli.js" mine `
      --count forever `
      --engine gpu `
      --state $stateFile `
      --gpu-batch 2097152 `
      --gpu-local-size 256
  } finally { Pop-Location }
}

# --- main ---

Write-Host ""
Write-Host "rpow GPU miner installer" -ForegroundColor Cyan
Write-Host "------------------------" -ForegroundColor Cyan

Refresh-Path
Ensure-Git
Ensure-Node
Ensure-Gcc
Ensure-Repo
Build-GpuMiner
Build-NativeMinerOptional

$stateFile = Get-StateFile

if (Test-LoggedIn $stateFile) {
  Write-Ok "existing session is valid; skipping login"
} else {
  Do-Login $stateFile
}

if ($SkipMine) {
  Write-Step "Done. Skipping mine as requested."
  Write-Host ""
  Write-Host "To start mining later:" -ForegroundColor Cyan
  Write-Host "  cd `"$InstallDir`"; node rpow-cli.js mine --count forever --engine gpu --state `"$stateFile`""
  return
}

Start-Mining $stateFile
