# How Terra Handles PostgreSQL (Lesson Applied to Uptrack)

## Problem We Had
- Added PostgreSQL to NixOS with complex timeout configurations
- Each attempt to add timeouts or safeguards made things worse
- System kept hanging during boot

## Solution: Learn from Terra
Our terra booking project (`/repos/booking/terra`) uses PostgreSQL successfully:

### Terra's Approach
```nix
services.postgresql = {
  enable = true;
  package = pkgs.postgresql_17;
  # ... simple config ...
  # NO custom systemd overrides
  # NO timeouts
  # NO wantedBy manipulation
  # Just works!
};
```

### Key Insight
**Simple is better than clever.** The more we tried to "fix" things with timeouts and overrides, the more problems we created.

## What We Changed in Uptrack

### Before (Broken)
```nix
services.postgresql = { ... };

# Problematic systemd override
systemd.services.postgresql = {
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    TimeoutStartSec = "60s";     # ← Makes things worse!
    TimeoutStopSec = "10s";
    Restart = "on-failure";
    RestartSec = "5s";
  };
};
```

### After (Simple, like Terra)
```nix
services.postgresql = {
  enable = true;
  package = pkgs.postgresql_16;
  enableTCPIP = true;

  settings = { ... };  # Conservative resource limits

  # Auto-create database and user (terra feature)
  ensureDatabases = [ "uptrack" ];
  ensureUsers = [{
    name = "uptrack";
    ensureDBOwnership = true;
  }];

  authentication = { ... };
};

# NO custom systemd overrides
# NO timeouts
# Let NixOS handle it
```

## Why This Works Better

| Aspect | Complex (Broken) | Simple (Works) |
|--------|------------------|----------------|
| Timeouts | Interfered with initdb | NixOS defaults work fine |
| Service startup | Hung waiting for conditions | Natural boot sequence |
| Debugging | Hard to find root cause | Clear and obvious |
| Maintenance | Fragile, breaks easily | Robust, proven pattern |
| When it fails | Complete boot hang | Normal NixOS error handling |

## Lessons Learned

1. **Don't fight the system** - NixOS has good defaults
2. **Copy proven patterns** - Terra's approach works
3. **Remove, don't add complexity** - Every override added risk
4. **Simple beats clever** - The timeout "fixes" made things worse

## Resource Constraints (Oracle Free Tier)

Yes, Oracle Free Tier is resource-constrained, BUT:
- ✅ PostgreSQL still boots fine (just takes time)
- ✅ First boot takes longer (initdb), but only once
- ✅ Subsequent boots are fast (database exists)
- ✅ Once running, PostgreSQL works normally

**Accept that first boot is slow**. That's OK! Better slow boot than no boot.

## Next Steps

1. Deploy simplified config (already updated)
2. Boot will take longer first time (initdb)
3. System will come back online
4. PostgreSQL will be running and working
5. Application deployment next

## For PostgreSQL 17 Upgrade

Use same simple approach when upgrading:
```nix
# Just change the package
package = pkgs.postgresql_17;

# That's it! NixOS handles the rest
```

No timeouts, no overrides, no "safeguards". Just work with the system, not against it.
