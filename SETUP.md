# Brainrot Inc. — Developer Setup (Windows, solo dev)

Step-by-step setup for a fresh clone on Windows. This is the honest path —
some steps (Studio plugins, MCP server) cannot be fully automated and must be
done by you in the GUI. Follow in order.

Tooling is already decided and pinned. Do not swap it out:

- **Code sync:** Argon (Rojo-compatible project format)
- **Studio AI bridge:** official Roblox Studio MCP (`Roblox/studio-rust-mcp-server` / built-in)
- **Package manager:** Wally
- **Toolchain manager:** rokit (successor to aftman)

---

## 0. Prerequisites

- Windows 11 (you have this)
- [Git](https://git-scm.com/download/win)
- [Roblox Studio](https://create.roblox.com/) (logged in)
- A terminal: PowerShell is fine. Examples below use PowerShell syntax.

---

## 1. Install rokit (toolchain manager)

rokit installs and pins every CLI tool this repo needs (argon, wally, selene,
stylua, darklua) at the exact versions in `rokit.toml`.

1. Install rokit once (per machine). Download the latest Windows release from
   <https://github.com/rojo-rbx/rokit/releases> and run the installer, or use
   the documented install command on that page. After install, restart your
   terminal so `rokit` is on `PATH`.

2. Verify:
   ```powershell
   rokit --version
   ```

3. From the repo root, install the pinned toolchain:
   ```powershell
   rokit install
   ```
   This reads `rokit.toml` and downloads argon, wally, selene, stylua, darklua.

4. Verify the tools resolve:
   ```powershell
   argon --version
   wally --version
   selene --version
   stylua --version
   ```

> If a pinned version fails to resolve, open `rokit.toml`, check the tool's
> GitHub releases page for the newest tag, update the version, and re-run
> `rokit install`. Bump deliberately and commit the change.

---

## 2. Install Wally packages

Wally reads `wally.toml` and downloads dependencies.

```powershell
wally install
```

This creates/fills:
- `Packages/`     — runtime deps (Trove, Signal) → maps to `ReplicatedStorage/Packages`
- `DevPackages/`  — dev-only deps (TestEZ)      → only mounted by `test.project.json`

Both folders are gitignored (re-downloadable). The `.gitkeep` placeholders keep
the Rojo mount points valid before the first install.

> **Signal package — needs your confirmation.** `wally.toml` currently pins
> `stravant/goodsignal`. If you prefer `sleitnick/signal` (the Trove author's
> signal) or another, change the `Signal` line and re-run `wally install`.

---

## 3. Install Argon (CLI + Studio plugin)

Argon has two halves that must both be running and connected:

**a) CLI** — already installed by `rokit install` (step 1). Confirm:
```powershell
argon --version
```

**b) Studio plugin** — install it once into Studio. Easiest:
```powershell
argon plugin install
```
This installs the Argon plugin into your local Studio plugins folder. If that
command is unavailable in your version, install the "Argon" plugin from the
Roblox Creator Marketplace / plugin page instead.

### Start syncing

1. From the repo root, start the sync server:
   ```powershell
   argon serve
   ```
   It serves `default.project.json` by default.

2. Open Roblox Studio with a new/baseplate place.

3. Open the **Argon** plugin toolbar → **Connect** (default host
   `localhost`, port `8000`). Once connected, the file tree maps into the
   DataModel per `default.project.json`.

> **Do NOT run two sync systems at once.** If you ever try the weppy fallback
> (see MCP section), stop `argon serve` first. Two live syncers fighting over
> the same DataModel will clobber each other.

---

## 4. Install the official Studio MCP (for Claude Code)

This lets Claude Code talk to Studio (read/modify the open place, run Luau).
It is a separate moving part from Argon and needs manual wiring. Three parts:

**a) Install the Studio MCP plugin / companion.** Get the official Roblox
   Studio MCP from `Roblox/studio-rust-mcp-server` (GitHub releases) or the
   built-in Studio MCP if your Studio build ships it. Run its installer; it
   installs a Studio plugin and a local MCP server binary.

**b) Run the MCP server.** Launch the server binary it installed (or enable the
   built-in server in Studio's settings). Keep it running while you work.

**c) Register it in `.claude/settings.json` → `mcpServers`.** Add an entry next
   to the existing `blender` entry, following the same shape. Example snippet
   (replace the command/args with the actual binary the installer placed — do
   not guess the path, copy it from the installer output):

   ```json
   {
     "mcpServers": {
       "blender": {
         "command": "uvx",
         "args": ["blender-mcp"]
       },
       "roblox-studio": {
         "command": "<absolute-path-to-studio-mcp-server-binary>",
         "args": ["--stdio"]
       }
     }
   }
   ```

   Notes:
   - Mirror the existing `blender` entry's structure (a `command` plus `args`).
   - Use the real install path/flags from the MCP installer. The `args` above
     (`--stdio`) are illustrative; check the server's `--help`.
   - This snippet is documentation only. I did not write a live binary path into
     `.claude/settings.json` because guessing it would break startup.

> **Compatibility note:** Claude Code's official Studio MCP support was expanded
> in **Feb 2026**, so prefer a current Claude Code build. If the official MCP is
> flaky on your setup, **weppy** is a known fallback sync/bridge — but remember
> the rule from step 3: never run weppy and `argon serve` at the same time.

---

## 5. Verify the pipeline (smoke test)

1. `argon serve` running (step 3) and the Studio plugin **Connected**.
2. In Studio, press **Play** (or just look at Output on connect for the server
   script).
3. Open **View → Output**. You should see:
   ```
   [Brainrot Inc.] server up
   [Brainrot Inc.] client up
   ```
   - `server up` comes from `src/ServerScriptService/Bootstrap.server.luau`
   - `client up` comes from `src/StarterPlayer/StarterPlayerScripts/Bootstrap.client.luau`

If both print, the Argon → Studio pipeline works. These Bootstrap scripts are
smoke tests only — the lead-programmer replaces them with real bootstrapping.

---

## 6. Day-to-day commands

```powershell
argon serve                              # start live sync (default.project.json)
argon build default.project.json -o BrainrotInc.rbxlx   # build a place file
selene src/                              # lint
stylua src/                              # format (add --check in CI)
wally install                            # refresh packages after editing wally.toml
```

Tests (TestEZ) sync via the separate `test.project.json`, which also mounts
`DevPackages/` and `tests/`:
```powershell
argon serve test.project.json
```

---

## Folder map (what syncs where)

| Filesystem path                              | Studio location                         |
|----------------------------------------------|-----------------------------------------|
| `src/ServerScriptService/`                   | `ServerScriptService`                   |
| `src/ServerStorage/`                         | `ServerStorage`                         |
| `src/ReplicatedStorage/`                     | `ReplicatedStorage`                     |
| `src/ReplicatedStorage/Shared/`              | `ReplicatedStorage.Shared`              |
| `Packages/`                                  | `ReplicatedStorage.Packages`            |
| `src/ReplicatedFirst/`                       | `ReplicatedFirst`                       |
| `src/StarterGui/`                            | `StarterGui`                            |
| `src/StarterPlayer/StarterPlayerScripts/`    | `StarterPlayer.StarterPlayerScripts`    |
| `tests/` (test project only)                 | `ReplicatedStorage.Tests`               |
| `DevPackages/` (test project only)           | `ReplicatedStorage.DevPackages`         |

File naming (Rojo/Argon convention, `.luau`):
- `*.server.luau` → `Script`
- `*.client.luau` → `LocalScript`
- `*.luau` → `ModuleScript`
- `init.luau` in a folder → that folder becomes a `ModuleScript`
