---
name: remotes-audit
description: Audit all RemoteEvent and RemoteFunction usage for security, correctness, and bandwidth efficiency. Checks for server-side validation, rate limiting, type checking, and anti-exploit patterns.
---

# /remotes-audit — Remotes Security Audit

## Delegate to: remotes-networking-specialist (with exploit-security-specialist for security review)

## Steps:
1. Find all RemoteEvent/RemoteFunction creation: `grep -rn "RemoteEvent\|RemoteFunction\|UnreliableRemoteEvent" src/`
2. Find all OnServerEvent handlers: `grep -rn "OnServerEvent\|OnServerInvoke" src/`
3. Find all FireServer calls: `grep -rn "FireServer\|InvokeServer" src/`

## For each server-side handler, verify:

### Critical (must fix):
- [ ] Type checking on EVERY argument (`typeof(arg) == expected`)
- [ ] Range/sanity checks on numeric values
- [ ] Player reference validation (is this player allowed to do this?)
- [ ] No RemoteFunction with OnServerInvoke from client (server hang risk)

### Important (should fix):
- [ ] Rate limiting per player (configurable, recommended 10-30 calls/sec depending on remote)
- [ ] Cooldown enforcement server-side (not relying on client cooldown)
- [ ] No Instance references passed through remotes (use string keys/IDs)
- [ ] Bandwidth estimation for high-frequency remotes

### Architecture:
- [ ] Remotes manifest exists and is up to date (`design/remotes-manifest.md`)
- [ ] Remotes centrally managed (not scattered Instance.new calls)
- [ ] Clear naming convention for remotes

## Output:
Generate a security report with findings organized by severity:

```markdown
# Remotes Audit

## Summary
- Total remotes found: X
- Client → Server: X
- Server → Client: X
- Unreliable: X

## Remotes Inventory
| Name | Type | Direction | Validation | Rate Limit | Status |
|------|------|-----------|------------|------------|--------|
| PurchaseItem | RemoteEvent | C→S | ✅ | ✅ 5/sec | OK |
| ShowMessage | RemoteEvent | S→C | N/A | N/A | OK |
| RequestData | RemoteFunction | S→C | N/A | N/A | OK |
| DangerousRemote | RemoteFunction | C→S | ❌ | ❌ | ⚠️ CRITICAL |

## Critical Findings
1. **DangerousRemote** (`src/ServerScriptService/X.lua:42`)
   - Client → Server RemoteFunction — server hang risk
   - Fix: Convert to RemoteEvent with optional response via separate remote

## Important Findings
...

## Recommendations
- Create `design/remotes-manifest.md` if missing
- Consolidate remote creation into `ReplicatedStorage/Shared/Remotes.lua`
```

Offer to delegate fixes to the appropriate specialist.
