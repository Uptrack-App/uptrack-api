# Quick Deploy Guide - indiastrong Node

## Status: ✅ READY TO DEPLOY

All code has been transferred to indiastrong at `/home/le/uptrack/`

---

## Deploy Commands

### Option 1: Quick Test (Recommended First)

```bash
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42

cd uptrack
nix develop
mix deps.get
mix compile
MIX_ENV=dev iex -S mix phx.server
```

### Option 2: Full Production Deploy

```bash
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42

cd uptrack
sudo nixos-rebuild switch --flake .#node-india-strong
```

---

## Verify Idle Prevention

```bash
# Check health
curl http://localhost:4000/api/health | jq '.checks.idle_prevention'

# Watch logs
tail -f logs/*.log | grep IdlePrevention
```

---

## What to Expect

- ✅ Every 5 minutes: Light load cycle
- ✅ Every 3 hours: Heavy load spike (30-60 sec)
- ✅ CPU/Memory/Network stay > 20%
- ✅ Oracle won't reclaim the instance

---

**Next Action**: SSH into indiastrong and run Option 1 commands
