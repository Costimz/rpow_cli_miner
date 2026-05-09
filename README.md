# rpow_cli_miner

Native C/OpenCL RPOW miner with CPU and GPU backends, up to 700x faster than the website and 35x faster than CPU mining.

## Features

- Browserless CLI flow for RPOW backend/API
- Native CPU miner in C
- Native GPU miner in C with OpenCL
- Node fallback miner
- Session persistence with local state files
- Retry handling for transient API/network failures
- Portable Windows bundle with no `npm install`

## Included engines

- `--engine node`
- `--engine native`
- `--engine gpu`

## Quick start (Windows, one-liner)

Open PowerShell and paste:

```powershell
irm https://raw.githubusercontent.com/fashaking/rpow_cli_miner/main/install.ps1 | iex
```

That single command will:

1. Install Git, Node.js LTS, and MinGW gcc via `winget` if they aren't already present.
2. Clone this repo into `%USERPROFILE%\rpow-cli`.
3. Build the GPU miner (`rpow-gpu-miner.exe`) and CPU fallback.
4. Prompt you for your account email, send a magic link, and prompt you to paste it back.
5. Start continuous GPU mining.

Session state is kept in `%USERPROFILE%\.rpow-cli\state.json` so re-running the one-liner picks up where you left off.

To re-run later without prompting:

```powershell
cd $env:USERPROFILE\rpow-cli
node rpow-cli.js mine --count forever --engine gpu --state $env:USERPROFILE\.rpow-cli\state.json
```

## Quick start (manual)

```powershell
node rpow-cli.js login --email you@example.com
node rpow-cli.js complete-login --link "https://..."
node rpow-cli.js mine --count forever --engine gpu
```

## Windows GPU setup

1. Install Node.js 18+ and confirm it works:

```powershell
node -v
```

2. Make sure your GPU driver is installed with OpenCL support.

- NVIDIA: standard GeForce or Studio driver is usually enough.
- AMD: install the normal Adrenalin driver.

3. Build the GPU miner:

```powershell
.\build-gpu.ps1
```

4. Request a magic link:

```powershell
node rpow-cli.js login --email you@example.com --state .rpow-a.json
```

5. Complete login with the link from your email:

```powershell
node rpow-cli.js complete-login --link "https://..." --state .rpow-a.json
```

6. Start GPU mining:

```powershell
node rpow-cli.js mine --count 1000 --engine gpu --state .rpow-a.json
```

7. Optional tuning example for stronger GPUs:

```powershell
node rpow-cli.js mine --count 1000 --engine gpu --state .rpow-a.json --workers 16 --gpu-batch 2097152 --gpu-local-size 256
```

If the GPU binary does not start, test it directly:

```powershell
.\rpow-gpu-miner.exe --prefix 00 --difficulty 1 --batch-size 1024 --local-size 64
```

If GPU mining is unavailable, use CPU fallback:

```powershell
node rpow-cli.js mine --count 1000 --engine native --workers 8 --state .rpow-a.json
```

## GPU example

```powershell
node rpow-cli.js mine --count 1000 --engine gpu --state .rpow-a.json --workers 16 --gpu-batch 2097152 --gpu-local-size 256
```

## CPU example

```powershell
node rpow-cli.js mine --count 1000 --engine native --workers 12 --state .rpow-a.json
```

## Files

- `rpow-cli.js` - CLI orchestrator
- `rpow-native-miner.c` / `rpow-native-miner.exe` - native CPU miner
- `rpow-gpu-miner.c` / `rpow-gpu-miner.exe` - native GPU miner
- `rpow-miner-worker.js` - Node fallback worker
- `index.js` - frontend bundle used for API discovery

See `rpow-cli.README.md`, `INSTALL-OTHER-PC.md`, and `INSTALL-GPU-OTHER-PC.md` for more usage details.
