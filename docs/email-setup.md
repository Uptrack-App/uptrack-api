# Uptrack Email Setup

## Addresses

| Address | Type | Purpose |
|---------|------|---------|
| `hello@uptrack.app` | Inbound + Outbound | Public-facing: support, contact, security reports, MCP directory |
| `team@uptrack.app` | Outbound only | App-generated: invitations, magic links |
| `alerts@uptrack.app` | Outbound only | System alert notifications to users |

## Infrastructure

### Receiving (Inbound)
- **Cloudflare Email Routing** forwards `hello@uptrack.app` → `hoangbytes@gmail.com`
- No mailbox needed — replies handled from Gmail

### Sending (Outbound)

**Transactional emails** (`team@`, `alerts@`):
- Stalwart SMTP relay on nbg1/nbg2 (localhost-only, no auth)
- DKIM signed: `stalwart._domainkey.uptrack.app`
- Elixir SMTP fleet dispatches via local Stalwart

**Human replies** (`hello@`):
- Gmail "Send mail as" (Option 2) — send as `hello@uptrack.app` through Gmail SMTP
- Requires `include:_spf.google.com` in SPF record

## DNS Records

| Type | Name | Value | Purpose |
|------|------|-------|---------|
| MX | `uptrack.app` | Cloudflare Email Routing | Inbound to hello@ |
| TXT | `uptrack.app` | `v=spf1 include:_spf.google.com ~all` | SPF for Gmail sending |
| TXT | `stalwart._domainkey.uptrack.app` | (DKIM public key) | DKIM for Stalwart |
| TXT | `_dmarc.uptrack.app` | `v=DMARC1; p=none; rua=mailto:hello@uptrack.app` | DMARC reporting |

## Where Each Address Is Used

| Address | Used in |
|---------|---------|
| `hello@uptrack.app` | Site footer, MCP directory form, support channel, security contact |
| `team@uptrack.app` | Invitation emails (from header), magic link emails |
| `alerts@uptrack.app` | Incident alert notifications to users |
