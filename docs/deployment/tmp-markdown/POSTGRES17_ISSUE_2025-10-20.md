# PostgreSQL 17 Deployment Issue - 2025-10-20

## Summary

Attempted to deploy PostgreSQL 17.5 to indiastrong (152.67.179.42) using safe `nixos-rebuild test` approach. System went offline after activation and has not recovered after 5+ minutes.

## Timeline

1. **17:40 UTC** - Updated config to use `pkgs.postgresql_17`
2. **17:42 UTC** - Synced config to remote system
3. **17:43 UTC** - Ran `nixos-rebuild dry-build` - **PASSED** ✅
4. **17:44 UTC** - Ran `nixos-rebuild test` - Build completed, activation started
5. **17:45 UTC** - SSH connection closed during service restarts (expected)
6. **17:45-17:58 UTC** - System offline, 60+ connection attempts failed

## Configuration Changes

```nix
# Before (working):
package = pkgs.postgresql_16;

# After (failed):
package = pkgs.postgresql_17;
```

## Why This Failed

Possible causes:
1. **PostgreSQL 17 initialization failure** - new major version may require different data directory initialization
2. **ARM64 compatibility** - PostgreSQL 17 might have issues on aarch64-linux
3. **Service dependency** - PostgreSQL service might depend on something else that failed
4. **Data migration needed** - PostgreSQL 17 can't read PostgreSQL 16 data (but we have no data yet)

Most likely: **PostgreSQL 17 service failed to start**, causing systemd to retry, which delayed SSH.

## Good News

✅ **Boot configuration unchanged** - we used `nixos-rebuild test`, not `switch`
✅ **System will recover** - reboot will restore working config
✅ **No data loss** - no PostgreSQL data exists yet

## Recovery Options

### Option 1: Wait for Auto-Recovery
System might recover by itself (has happened before). NixOS may rollback failed service.

### Option 2: Reboot from Oracle Console
1. Log into Oracle Cloud console
2. Navigate to indiastrong instance
3. Click "Reboot" button
4. System will boot with old working config (no PostgreSQL)

### Option 3: Wait and Investigate
When system comes back:
```bash
# Check systemd journal for PostgreSQL errors
journalctl -u postgresql -n 100

# Check systemd service status
systemctl status postgresql

# Check PostgreSQL logs
ls -la /var/log/postgresql/
```

## Next Steps

1. **Immediate**: Wait 10-15 minutes total, then check Oracle console
2. **When recovered**: Investigate why PostgreSQL 17 failed
3. **Alternative**: Try PostgreSQL 16 instead (known to work, see earlier tests)
4. **Long-term**: Figure out proper PostgreSQL 17 initialization on NixOS

## Lessons Learned

✅ **Good**: Using `test` instead of `switch` prevented permanent damage
✅ **Good**: dry-build caught no syntax errors (config was valid)
❌ **Bad**: Even valid config can fail during activation
❌ **Bad**: Need better way to test service startup without full activation

## Recommendation

**For next attempt**:
1. Start with PostgreSQL 16 (proven to work in nix-shell test)
2. Get application running with PostgreSQL 16
3. Test PostgreSQL 17 upgrade later in controlled manner

OR

Test PostgreSQL 17 service in isolation:
```bash
# On remote system
systemd-nspawn -D /var/lib/machines/test nixos-rebuild test ...
```

---

**Status**: System offline, waiting for recovery
**Risk**: LOW (boot config unchanged)
**Time offline**: 13+ minutes
**Next check**: Oracle Cloud console
