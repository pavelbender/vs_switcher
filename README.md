# vs-switcher

A keyboard-driven launcher that opens project folders in VS Code under isolated **Codex contexts** — each with its own `CODEX_HOME`, VS Code user data directory and sign-in.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/platform-Windows-0078d4.svg)](#requirements)
[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE.svg)](#requirements)

```
VS Code project launcher
Codex account: Work Codex account | Context: Work
Path: C:\Projects\work
Up/Down: select | Right: enter folder | Left: back | Enter: open in VS Code | Esc: quit

> Work        C:\Projects\work
  Personal    C:\Projects\personal
  OpenRouter  C:\Projects
```

## Why

One machine, several Codex identities. Signing in and out — or letting a work account write into a personal project's history — is the thing this avoids. Each context gets its own Codex home and VS Code profile, so the accounts never see each other.

Three contexts ship by default:

| Context | Codex home | VS Code user data | Auth |
| --- | --- | --- | --- |
| `Work` | `%USERPROFILE%\.codex-work` | `%LOCALAPPDATA%\VSCode-Work` | ChatGPT sign-in |
| `Personal` | `%USERPROFILE%\.codex-personal` | `%LOCALAPPDATA%\VSCode-Personal` | ChatGPT sign-in |
| `OpenRouter` | `%USERPROFILE%\.codex-openrouter` | `%LOCALAPPDATA%\VSCode-OpenRouter` | OpenRouter API key |

Extensions are shared across contexts (`%USERPROFILE%\.vscode\extensions`) — only the accounts are separated.

## Requirements

- Windows with PowerShell 5.1 or later
- VS Code with the `code` command on `PATH` (in VS Code: **Shell Command: Install 'code' command in PATH**)

## Install

```powershell
.\install.ps1
```

This copies the script to `%LOCALAPPDATA%\VSCodeAccountLauncher`, writes a `c.cmd` shim and adds that folder to your user `PATH`. Open a new PowerShell window and run:

```powershell
c
```

On the first launch you are asked for a parent projects folder, such as `C:\Projects`. If it contains `work` and `personal` subfolders they are picked up automatically; otherwise each folder is asked for separately.

## Controls

| Key | Action |
| --- | --- |
| `Up` / `Down` | Select a context or folder |
| `Right` | Enter the selected folder |
| `Left` | Go to the parent; from a context root, back to the main menu |
| `Enter` | Open the current folder in VS Code (the launcher stays running) |
| `Esc` | Quit |

## How context isolation works

VS Code is started with the selected context's `CODEX_HOME` and `--user-data-dir`. On each launch the Codex home is created if missing, with `log`, `sessions`, `attachments` and `tmp` subfolders, and `config.toml`, `AGENTS.md` and `RTK.md` are seeded from `~\.codex` on first creation.

`auth.json` is never copied, so every context keeps its own sign-in — the first time a context opens, sign in from the Codex panel. Without the directory the Codex CLI refuses to start with `CODEX_HOME points to "..." but that path does not exist`, and the Codex panel stays on its logo.

> VS Code reads `CODEX_HOME` from the process environment at startup. If a window for that context was already open when the folders were created, run **Developer: Reload Window**.

## OpenRouter context

The `OpenRouter` context runs Codex against the OpenRouter API instead of a signed-in ChatGPT account, following the [Codex CLI cookbook](https://openrouter.ai/docs/cookbook/coding-agents/codex-cli). It opens on the parent projects folder, so any project can be browsed under it.

Its `config.toml` is generated rather than copied from `~\.codex`:

```toml
model_provider = "openrouter"
model_reasoning_effort = "high"
model = "~openai/gpt-latest"

[model_providers.openrouter]
name = "openrouter"
base_url = "https://openrouter.ai/api/v1"

[model_providers.openrouter.auth]
command = "powershell"
args = ["-NoProfile", "-Command", "Write-Output $env:OPENROUTER_API_KEY"]
```

`AGENTS.md` and `RTK.md` are still seeded from `~\.codex`.

### API key

Write the key as a single line in:

```
%USERPROFILE%\.codex-openrouter\openrouter.key
```

The launcher reads that file and exports `OPENROUTER_API_KEY` into the VS Code process it starts, so the key stays with this context and never reaches the `Work` or `Personal` windows. If the file is missing it falls back to an `OPENROUTER_API_KEY` already in the environment (`setx OPENROUTER_API_KEY "sk-or-..."`). If neither exists, opening the context prints a reminder and Codex fails to authenticate.

Change the model by editing `model` in `%USERPROFILE%\.codex-openrouter\config.toml`, for example `~anthropic/claude-sonnet-latest`. The `model` value in the launcher config is only used when `config.toml` is first generated.

## Configuration

Paths and labels live in `%LOCALAPPDATA%\VSCodeAccountLauncher\config.json` and can be edited by hand. Each entry in `roots` accepts:

| Field | Meaning |
| --- | --- |
| `name` | Label shown in the menu |
| `path` | Folder the context opens on |
| `account` | Description shown in the header |
| `codexHome` | Value exported as `CODEX_HOME` |
| `userDataDir` | VS Code `--user-data-dir` |
| `extensionsDir` | VS Code `--extensions-dir` |
| `provider` | `openrouter` to generate the API-backed `config.toml` |
| `model` | Model written into a generated `config.toml` |
| `apiKeyEnv` | Environment variable the key is exported as |
| `apiKeyFile` | File the key is read from |

Configurations written before the `OpenRouter` context existed get it appended automatically on the next launch. Activity is logged to `%LOCALAPPDATA%\VSCodeAccountLauncher\launcher.log` (capped at 10,000 lines).

## Uninstall

```powershell
Remove-Item -Recurse "$env:LOCALAPPDATA\VSCodeAccountLauncher"
```

Then drop that folder from your user `PATH`. Codex homes and VS Code user data directories are left alone — delete `~\.codex-*` and `%LOCALAPPDATA%\VSCode-*` if you want those gone too.

## License

[MIT](LICENSE)
