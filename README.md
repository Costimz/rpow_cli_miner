# rpow_cli_miner

A CLI miner for the RPOW (reusable proof-of-work) token system at
`rpow2.com`. Solves the site's SHA-256 proof-of-work challenges from
the command line, with three interchangeable engines:

- **Node** worker threads — pure JavaScript, slowest, no build step.
- **Native** C miner — multi-threaded CPU SHA-256, ~35× faster than Node.
- **GPU** OpenCL miner — runs on any NVIDIA / AMD / Intel GPU with an
  OpenCL ICD, ~700× faster than the in-browser miner.

Auto-detects every GPU on the machine and can mine on **multiple GPUs
simultaneously** (e.g. NVIDIA discrete + Intel integrated together).

---

## Quick start (Windows, one-liner)

Open PowerShell and paste:

```powershell
irm https://raw.githubusercontent.com/fashaking/rpow_cli_miner/main/install.ps1 | iex
```

That single command will:

1. Install Git, Node.js LTS, and MinGW gcc via `winget` if missing.
2. Clone this repo into `%USERPROFILE%\rpow-cli`.
3. Build `rpow-gpu-miner.exe` (and the CPU fallback).
4. Enumerate every OpenCL GPU on your system and ask whether you want
   to use the most powerful one, all of them, or a specific subset.
5. Prompt for your account email, send a magic link, and prompt for the
   pasted-back link.
6. Ask how long you want to mine — forever, a token count, or a
   wall-clock duration like `7d`.
7. Start mining.

Session state lives in `%USERPROFILE%\.rpow-cli\state.json`, so re-running
the one-liner picks up where you left off.

### Pre-supplied answers (no prompts)

```powershell
$env:RPOW_EMAIL    = "you@example.com"
$env:RPOW_GPUS     = "all"      # auto | all | 0:0,1:0
$env:RPOW_DURATION = "7d"       # or set RPOW_COUNT="forever" / "1000000"
irm https://raw.githubusercontent.com/fashaking/rpow_cli_miner/main/install.ps1 | iex
```

### Re-running after install

```powershell
cd $env:USERPROFILE\rpow-cli
node rpow-cli.js mine --count forever --engine gpu --gpu-devices auto
```

---

## How it works

The site exposes a small REST flow that the CLI reproduces:

1. `POST /auth/request { email }` — sends a magic-link email.
2. You click / paste the magic link → server sets a session cookie.
3. `POST /challenge` — returns `{ challenge_id, nonce_prefix, difficulty_bits, expires_at }`.
4. The miner searches for a `nonce` (uint64) such that
   `SHA-256(nonce_prefix || little_endian(nonce))` has at least
   `difficulty_bits` trailing zero bits.
5. `POST /mint { challenge_id, solution_nonce }` — server verifies the
   hash and mints/credits a token to your account.
6. Repeat from step 3 until your `--count` is reached (or forever).

The CLI persists the session cookie and the in-progress challenge in
`%USERPROFILE%\.rpow-cli\state.json` (Linux/macOS: `~/.rpow-cli/state.json`),
so killing and restarting resumes mining without re-logging-in.

### What "multi-GPU" actually does

The C miner is single-device per process. When you ask for multiple
GPUs, the CLI launches one miner subprocess per device and gives each
one a disjoint nonce stripe (2⁴⁸ nonces apart, far more than any
plausible challenge can exhaust). Whichever device finds a valid nonce
first wins; the others are killed and the solution is submitted. The
combined hash rate is logged.

This means two devices of very different speeds work fine together —
the slow one just contributes whatever it can during the time the fast
one is searching. There is no work-stealing, but for short challenges
that doesn't matter.

---

## Commands

```text
node rpow-cli.js map                      # show the API endpoint table
node rpow-cli.js list-gpus                # enumerate OpenCL devices
node rpow-cli.js login --email you@...    # request a magic-link email
node rpow-cli.js complete-login --link "https://..."
node rpow-cli.js me                       # check session + balance
node rpow-cli.js mine --count 10          # mine 10 tokens then stop
node rpow-cli.js mine --count forever --engine gpu --gpu-devices auto
node rpow-cli.js send --to user@... --amount 1
node rpow-cli.js ledger                   # transaction history
node rpow-cli.js activity                 # account activity
node rpow-cli.js logout
```

### Common flags

| Flag                | Meaning                                                              |
| ------------------- | -------------------------------------------------------------------- |
| `--count N`         | Number of tokens to mint, or `forever`/`infinite`/`unlimited`. Defaults to `1`. Accepts any positive integer up to ~9 quadrillion. |
| `--duration SPEC`   | Stop after this much wall-clock time. Examples: `30s`, `5m`, `2h`, `7d`. Combine with `--count forever` to mine until either limit. |
| `--engine`          | `node`, `native` (CPU C), or `gpu` (OpenCL).                         |
| `--workers N`       | CPU threads (for `native`/`node`).                                   |
| `--gpu-devices`     | `auto`, `all`, or comma list `p:d,p:d` (e.g. `0:0,1:0`).             |
| `--gpu-batch`       | Nonces per kernel launch (default 1 048 576). Tune up on big GPUs.   |
| `--gpu-local-size`  | OpenCL local work-group size (default 256).                          |
| `--state PATH`      | Override state file path.                                            |
| `--proxy SPEC`      | HTTP/HTTPS proxy, e.g. `http://user:pass@host:8080`.                 |
| `--timeout MS`      | Per-request timeout (default 20 000).                                |
| `--retries N`       | Max retries on transient network errors (default 5).                 |
| `--log-every-ms`    | Mining progress log interval.                                        |
| `--verbose`         | Log every HTTP request.                                              |

### How long do you want to run?

```powershell
# Mine forever (until you hit Ctrl+C):
node rpow-cli.js mine --count forever --engine gpu --gpu-devices auto

# Mine a specific number of tokens:
node rpow-cli.js mine --count 1000000 --engine gpu --gpu-devices auto

# Mine for one week of wall-clock time:
node rpow-cli.js mine --duration 7d --engine gpu --gpu-devices auto

# Mine for 6 hours overnight:
node rpow-cli.js mine --duration 6h --engine gpu --gpu-devices all
```

The installer asks the same question interactively (forever / count / duration) right before mining starts. To skip the prompt, set `$env:RPOW_COUNT` (e.g. `forever` or `1000000`) **or** `$env:RPOW_DURATION` (e.g. `7d`).

---

## GPU selection

Run:

```powershell
node rpow-cli.js list-gpus
```

You'll see something like:

```text
Detected GPU devices:
  0:0  NVIDIA GeForce RTX 3060  vendor=NVIDIA Corporation  cu=28  mem=12288MB  [auto]
  1:0  Intel(R) UHD Graphics 770  vendor=Intel(R) Corporation  cu=32  mem=6494MB

Use one device :  --engine gpu --gpu-devices auto
Use all devices:  --engine gpu --gpu-devices all
Use specific  :  --engine gpu --gpu-devices 0:0,1:0
```

The `[auto]` tag marks the device that `--gpu-devices auto` will pick.
Selection prefers vendor (NVIDIA → AMD → Apple → Intel) then compute
unit count.

### Examples

Single best GPU:

```powershell
node rpow-cli.js mine --count forever --engine gpu --gpu-devices auto
```

Both NVIDIA and Intel iGPU together:

```powershell
node rpow-cli.js mine --count forever --engine gpu --gpu-devices all
```

Pick exactly platform 0 device 0 and platform 1 device 0:

```powershell
node rpow-cli.js mine --count forever --engine gpu --gpu-devices 0:0,1:0
```

---

## Manual install (without the one-liner)

Requirements:

- Windows 10/11, Linux, or macOS.
- Node.js 18+.
- A C compiler if you want the native or GPU engine
  (MinGW-w64 gcc on Windows, `gcc`/`clang` on Linux/macOS).
- For GPU: an OpenCL ICD. NVIDIA / AMD drivers ship one. Intel may
  need the *Intel OpenCL Runtime*.

Build:

```powershell
# Windows
.\build-native.ps1
.\build-gpu.ps1
```

```bash
# Linux / macOS
./build-native.sh
./build-gpu.sh
```

Then:

```bash
node rpow-cli.js login --email you@example.com
node rpow-cli.js complete-login --link "https://..."
node rpow-cli.js list-gpus
node rpow-cli.js mine --count forever --engine gpu --gpu-devices auto
```

---

## Security notes

- All API calls go to a hardcoded allowlist of hosts
  (`api.rpow2.com`, `rpow2.com`, `www.rpow2.com`). The CLI does not let
  the server redirect API calls elsewhere.
- API endpoint paths are hardcoded too — the bundled `index.js` is only
  used by the `map` command for human inspection.
- `/challenge` responses are validated (challenge ID shape, hex
  `nonce_prefix` capped at 64 bytes, difficulty in `[1, 64]`, parseable
  `expires_at`) before any value is passed to the C miner.
- Spawned miner processes receive arguments as a `spawn` argv array,
  never a shell string — so server-supplied values cannot inject shell
  commands.
- Session state (cookies + in-progress challenge) is stored under your
  user profile (`%USERPROFILE%\.rpow-cli\state.json`), never globally.
- The CLI never reads your password — auth is magic-link only.

If you want to run against a local dev server, set `RPOW_DEV=1` to
re-enable `127.0.0.1` and `127.0.0.1.sslip.io` in the host allowlist.

---

## Troubleshooting

**`gpu miner not built`**
You haven't built `rpow-gpu-miner.exe`. Run `.\build-gpu.ps1` (Windows)
or `./build-gpu.sh` (Linux/macOS).

**`OpenCL runtime not found`**
Your machine has no OpenCL ICD. Install your GPU vendor's normal driver:

- NVIDIA: GeForce or Studio driver.
- AMD: Adrenalin.
- Intel: Latest Intel Graphics driver, plus the *Intel OpenCL Runtime*.

**`no OpenCL GPU/accelerator found on selected platform`**
Run `node rpow-cli.js list-gpus` to see what platforms exist; your CPU
may be installed as an OpenCL platform but with no GPU under it.

**Mining starts then immediately says `challenge expired`**
Your system clock is wrong. Sync it (Windows: *Settings → Time & language
→ Date & time → Sync now*).

**`magic-link request is rate-limited`**
You've requested too many magic links in a short window. Wait a minute
and try again.

**Throttled hash rate / GPU runs hot**
Lower `--gpu-batch` (e.g. `524288`) so each kernel launch is shorter
and the GPU has more cooling headroom. Increase `--gpu-local-size` to
512 on big NVIDIA cards if it divides your batch size.

---

## Files

| File                       | Purpose                                                  |
| -------------------------- | -------------------------------------------------------- |
| `rpow-cli.js`              | Main CLI: HTTP, auth, mining orchestration, state.       |
| `rpow-miner-worker.js`     | Pure-JS Node worker (`--engine node`).                   |
| `rpow-native-miner.c/.exe` | Native CPU miner (`--engine native`).                    |
| `rpow-gpu-miner.c/.exe`    | OpenCL GPU miner (`--engine gpu`).                       |
| `install.ps1`              | One-liner Windows installer.                             |
| `build-native.{sh,ps1}`    | Build script for the CPU miner.                          |
| `build-gpu.{sh,ps1}`       | Build script for the GPU miner.                          |
| `index.js`                 | Site bundle, kept for the `map` command (informational). |

See `rpow-cli.README.md`, `INSTALL-OTHER-PC.md`, and
`INSTALL-GPU-OTHER-PC.md` for additional notes.
