# Consolidate agentenv + config into one tool

## Context

**Goal:** Merge the `config` script's functionality into `agentenv`, making agentenv the single tool for managing mutable repo installations (host and container). The registry and host wrappers/skills live in `~/config/`. The separate `config` script goes away.

**Why it matters:** We currently have two tools doing the same thing — `agentenv install` (registry at `~/.agentenv/installed/`, consumed by containers) and `config install` (registry at `~/config/installed/`, consumed by the host). They share identical semantics. Consolidating into one tool with one registry eliminates duplication and makes the mental model simpler: `agentenv install` registers a repo, and it's available everywhere — host PATH, host skills, and inside containers.

### Current state

**Two scripts, two registries:**
- `~/projects/agentenv/agentenv` — container launcher + basic install/uninstall/list using `~/.agentenv/installed/`
- `~/config/bin/config` — host wrappers + skills using `~/config/installed/`

**Both registries have the same repos installed.** They're duplicates.

### Target state

**One script, one registry:**
- `~/projects/agentenv/agentenv` — does everything
- Registry: `~/config/installed/`
- Host wrappers: `~/config/bin/`
- Host skills: `~/config/skills/`
- Container mounts: reads from `~/config/installed/`
- `~/config/bin/config` — deleted
- `~/.agentenv/` — deleted (registry moved to `~/config/installed/`)

### What agentenv becomes

```
agentenv install [name]         # register repo + generate host wrappers + link skills
agentenv uninstall <name>       # reverse all of the above
agentenv list                   # show installed repos with bin/flake/skills status
agentenv rewrap                 # regenerate all host wrappers + skill links
agentenv [options] [dir] [-- cmd]  # launch container (existing behavior)
```

The subcommand dispatch stays the same: if first arg matches `install|uninstall|list|rewrap`, dispatch. Otherwise, fall through to container launch.

### Key changes to agentenv script

1. **Registry path:** `INSTALLED_DIR` changes from `$HOME/.agentenv/installed` to `$HOME/config/installed`
2. **Add host paths:** `BIN_DIR="$HOME/config/bin"`, `SKILLS_DIR="$HOME/config/skills"`
3. **Absorb config script's functions:** `is_managed_wrapper`, `generate_wrappers`, `remove_wrappers`, `link_skills`, `unlink_skills` — copy from `~/config/bin/config`
4. **Update wrapper header:** change from `"managed by config install"` to `"managed by agentenv install"`
5. **Update install/uninstall:** call `generate_wrappers` + `link_skills` on install, `remove_wrappers` + `unlink_skills` on uninstall
6. **Add `rewrap` subcommand**
7. **Update `list`:** show skills count alongside bin/flake
8. **Update all user-facing messages:** `"config: ..."` → `"agentenv: ..."`
9. **Container mount section:** already reads `$INSTALLED_DIR`, so it will automatically use `~/config/installed/` after the path change

### Migration steps

1. Update agentenv script with all changes above
2. Delete `~/config/bin/config`
3. Remove `~/.agentenv/installed/` (old registry — repos are already in `~/config/installed/`)
4. Update the wrapper header in all existing wrappers: `s/managed by config install/managed by agentenv install/`
5. Since agentenv is itself installed, the wrapper at `~/config/bin/agentenv` calls through `~/config/installed/agentenv/bin/agentenv → ~/projects/agentenv/agentenv`. After updating the agentenv script, the wrapper still works — it calls the updated script.
6. Verify all tools still work: `agentenv list`, `polo --help`, `fetch --help`, `agentenv --help`
7. Commit in both repos (`~/projects/agentenv` and `~/config`)

### Reference

- Current agentenv script: `~/projects/agentenv/agentenv` (container launcher + basic install)
- Current config script: `~/config/bin/config` (host wrappers + skills — absorb this entirely)
- Entrypoint: `~/projects/agentenv/image/entrypoint.sh` (no changes needed — it already generates container wrappers from `/installed/*/bin/`)

---

## State

**Progress:** Complete

**Current understanding:**
- agentenv is now the single tool for install/uninstall/list/rewrap + container launch
- Registry lives at `~/config/installed/`, read by both host wrappers and container mounts
- `is_managed_wrapper` accepts both old ("config install") and new ("agentenv install") headers for backwards compatibility during rewrap

**Last iteration:** All tasks complete. Committed in both repos.

---

## Predictions

- [x] The wrapper at `~/config/bin/agentenv` will continue to work after the merge because it calls through the installed symlink to the actual script, which we're updating in-place
- [x] Updating the wrapper header from "config install" to "agentenv install" across existing wrappers will be a simple sed — no functional change
- [x] Deleting `~/config/bin/config` won't break anything because nothing depends on the `config` command (agentenv replaces it)
- [x] The `~/.agentenv/` directory can be safely removed since `~/config/installed/` already has all the same repos

---

## Prediction Outcomes

- **Wrapper continuity:** Confirmed. `~/config/bin/agentenv` calls through the symlink chain to the updated script. All wrappers work.
- **Header update:** Partially violated. The prediction said "simple sed" but `sed -i ''` on macOS choked on the em dash `—` (multi-byte UTF-8). The fix was to use `agentenv rewrap` to regenerate all wrappers from scratch, which is cleaner anyway. `is_managed_wrapper` was updated to match both old and new header strings so rewrap could overwrite the old wrappers.
- **config deletion:** Confirmed. `which config` returns nothing, no breakage.
- **~/.agentenv/ removal:** Confirmed with caveat. The old registry had a `container` entry not present in `~/config/installed/`. This was the macOS container CLI — a system-level tool that doesn't need to be in the managed registry.

---

## Discoveries

- **macOS sed + UTF-8:** `sed -i '' 's/…/…/'` silently fails when the pattern contains multi-byte UTF-8 characters like `—` (em dash). The command exits 0 and the file is unchanged. Workaround: use `perl -i -pe` for UTF-8-safe in-place edits, or regenerate the files from scratch (which is what `rewrap` does).
- **Registries diverge silently:** The old `~/.agentenv/installed/` had a `container` entry that never made it to `~/config/installed/`. Two registries with the "same" data will inevitably drift. This validates the consolidation — one registry, one truth.
- **`rewrap` is the migration tool:** Having a "regenerate everything" subcommand made the header migration trivial. Instead of surgically editing files, just regenerate them. This pattern (idempotent regeneration) is more robust than in-place patching for any future format changes.
- **`is_managed_wrapper` needs both patterns:** After consolidation, existing wrappers still have the old header until rewrapped. The guard function matches both `"managed by agentenv install"` and `"managed by config install"` so rewrap can overwrite old wrappers without manual intervention.

---

## Tasks

### Current Focus

- [x] Merge the config script's functions into agentenv: `is_managed_wrapper`, `generate_wrappers`, `remove_wrappers`, `link_skills`, `unlink_skills` — update paths to use `$HOME/config/` and messages to say `"agentenv:"`
- [x] Update agentenv's `cmd_install` to call `generate_wrappers` + `link_skills`
- [x] Update agentenv's `cmd_uninstall` to call `remove_wrappers` + `unlink_skills`
- [x] Update agentenv's `cmd_list` to show skills count
- [x] Add `cmd_rewrap` subcommand to agentenv
- [x] Add `rewrap` to subcommand dispatch
- [x] Update agentenv's usage/help text
- [x] Change `INSTALLED_DIR` from `$HOME/.agentenv/installed` to `$HOME/config/installed`
- [x] Delete `~/config/bin/config`
- [x] Update wrapper header in all existing wrappers in `~/config/bin/` (used `rewrap` instead of `sed`)
- [x] Remove `~/.agentenv/installed/` directory (old registry)
- [x] Update the home-manager skill at `~/.claude/skills/home-manager/SKILL.md`: replace references to `config install` with `agentenv install`

### Verify

- [x] `agentenv list` shows all installed repos with correct bin/flake/skills status
- [x] `agentenv --help` shows unified usage
- [x] `polo --help` works (wrapper still valid)
- [x] `fetch --help` works (wrapper still valid)
- [x] `agentenv install` from a repo generates wrappers and skill links
- [x] `agentenv uninstall` removes wrappers and skill links
- [x] `agentenv rewrap` regenerates everything
- [ ] Container launch still works (reads from `~/config/installed/`) (not tested — requires container runtime)

### Later

- [x] Update `~/projects/agentenv/docs/mutable-installations.md` to reflect the unified model
- [ ] Consider: should the agentenv entrypoint also handle skills for containers?

---

## Instructions

1. **Read context** — This file, `~/projects/agentenv/agentenv`, `~/config/bin/config`
2. **Pick the most important unchecked task** (not necessarily in order)
3. **Implement it fully** — no placeholders
4. **Run and verify** — test each step
5. **Update** — Check off tasks, update State section
6. **Commit** — Commit in the appropriate repo for each change

**Multi-repo work:** Primary changes in `~/projects/agentenv` (the script). Cleanup in `~/config` (delete config script, update wrappers).

---

## Success Criteria

- `agentenv` is the single tool for install/uninstall/list/rewrap AND container launch
- `~/config/bin/config` no longer exists
- `~/.agentenv/` no longer exists
- All existing tools still work via their wrappers
- One registry at `~/config/installed/`

---

## Termination

When all tasks complete OR blocked:
- All done: `<promise>COMPLETE</promise>`
- Blocked: `<promise>BLOCKED</promise>`

---

## If Stuck

1. Reframe: What question are you actually trying to answer?
2. Open up: List 3 ways forward, even awkward ones
3. Question constraints: Which blockers are real vs assumed?
4. If truly stuck: `<promise>BLOCKED</promise>`
