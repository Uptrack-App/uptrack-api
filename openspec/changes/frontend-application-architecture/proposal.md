# Frontend Application Architecture

## Summary

Establish the frontend application architecture for Uptrack using:
- **TanStack Start** as the React meta-framework
- **GraphQL API** for data fetching (queries/mutations)
- **Cloudflare Workers** for edge deployment (~$5/mo)
- **Direct WebSocket to Phoenix** for real-time features
- **Single repo** with `web/` directory for frontend

## Why

Uptrack needs a modern, performant frontend that:
- Loads fast globally (edge deployment)
- Has excellent type safety (end-to-end with GraphQL)
- Supports real-time updates (monitor status, alerts)
- Is cost-effective to operate (~$5/month)
- Integrates well with existing Elixir/Phoenix backend

### Why TanStack Start over alternatives

| Requirement | TanStack Start | Next.js | Remix |
|-------------|---------------|---------|-------|
| Workers/Edge native | ✅ Excellent | ⚠️ Limited | ✅ Good |
| Bundle size | Small | Large | Medium |
| Type safety | Excellent | Good | Good |
| TanStack Query built-in | ✅ | Manual | Manual |
| Self-host friendly | ✅ | ⚠️ Vercel-isms | ✅ |
| Maturity | Beta | Stable | Stable |

### Why GraphQL over REST

| Requirement | GraphQL | REST |
|-------------|---------|------|
| Type generation | ✅ Codegen | Manual |
| Flexible queries | ✅ Client decides | Server decides |
| Real-time (subscriptions) | ✅ Built-in | Manual |
| Caching | TanStack Query | Manual |
| Over-fetching | ✅ Avoided | Common |

### Why Workers over self-hosted Node.js

| Aspect | Cloudflare Workers | Self-hosted Node.js |
|--------|-------------------|---------------------|
| Cost | ~$5/month | €0 (uses VPS) |
| Global latency | ~20ms (edge) | ~100-200ms (single region) |
| Maintenance | Zero | Node.js updates |
| Scaling | Automatic | Manual |
| Cold starts | ~0ms | ~500ms |

## What

### Technology Stack

| Layer | Technology |
|-------|------------|
| Framework | TanStack Start |
| Routing | TanStack Router |
| Data fetching | TanStack Query + GraphQL |
| Forms | TanStack Form |
| Tables | TanStack Table |
| Styling | Tailwind CSS |
| GraphQL client | urql or graphql-request |
| Codegen | graphql-codegen |
| Deployment | Cloudflare Workers |
| Real-time | Phoenix WebSocket (direct) |

### Repository Structure (Single Repo)

```
uptrack/
├── lib/                          # Phoenix/Elixir
│   ├── uptrack/                  # Business logic
│   ├── uptrack_web/              # Web layer
│   └── uptrack_graphql/          # GraphQL schema (Absinthe)
│
├── web/                          # TanStack Start frontend
│   ├── app/
│   │   ├── routes/               # File-based routing
│   │   ├── components/           # React components
│   │   └── lib/                  # Utilities, GraphQL client
│   ├── public/                   # Static assets
│   ├── package.json
│   ├── tsconfig.json
│   ├── wrangler.toml             # Cloudflare Workers config
│   └── codegen.ts                # GraphQL codegen config
│
├── priv/                         # Phoenix priv (existing)
├── config/                       # Phoenix config (existing)
├── infra/                        # NixOS configs (existing)
├── openspec/                     # Specs (existing)
├── mix.exs                       # Elixir deps
├── package.json                  # Root (scripts only)
└── schema.graphql                # GraphQL schema (source of truth)
```

**Why single repo:**
- Simpler than monorepo tooling (no Turborepo/pnpm workspaces)
- GraphQL schema at root, shared by both
- Single `git clone`, easy onboarding
- Deploy separately: `mix release` for API, `wrangler deploy` for frontend

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│  BROWSER                                                                │
│                                                                         │
│  TanStack Start App                                                     │
│  ├─ GraphQL queries/mutations ───┐                                      │
│  └─ WebSocket (real-time) ───────┼──────────────────┐                   │
│                                  │                  │                   │
└──────────────────────────────────┼──────────────────┼───────────────────┘
                                   │                  │
                                   ▼                  │
┌──────────────────────────────────────────────┐      │
│  CLOUDFLARE WORKERS (Edge)                   │      │
│                                              │      │
│  TanStack Start SSR                          │      │
│  ├─ Server functions                         │      │
│  └─ GraphQL proxy/BFF ───────────────────────┼──┐   │
│                                              │  │   │
│  Cost: ~$5/month                             │  │   │
└──────────────────────────────────────────────┘  │   │
                                                  │   │
                              ┌────────────────────┘   │
                              │                        │
                              ▼                        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  YOUR INFRASTRUCTURE (Netcup/HostHatch)                                 │
│                                                                         │
│  Phoenix API (nbg-1, nbg-2)                                             │
│  ├─ GraphQL endpoint (/api/graphql)                                     │
│  ├─ WebSocket endpoint (/socket) ◄── Direct from browser                │
│  ├─ Authentication (OAuth, API keys)                                    │
│  └─ Business logic                                                      │
│                                                                         │
│  PostgreSQL ← VictoriaMetrics                                           │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Real-time Strategy

**Problem:** Cloudflare Workers don't support WebSocket pass-through for subscriptions.

**Solution:** Hybrid approach

```
┌─────────────────────────────────────────────────────────────┐
│  Data Type        │ Method           │ Path                 │
├───────────────────┼──────────────────┼──────────────────────┤
│  Initial load     │ GraphQL Query    │ Browser → Worker → API │
│  User actions     │ GraphQL Mutation │ Browser → Worker → API │
│  Real-time updates│ WebSocket        │ Browser → API (direct) │
└─────────────────────────────────────────────────────────────┘
```

**Phoenix Channels for real-time:**
```elixir
# Monitor status updates
socket "/socket", UptrackWeb.UserSocket
channel "monitors:*", UptrackWeb.MonitorChannel
channel "alerts:*", UptrackWeb.AlertChannel
```

**Frontend WebSocket (direct to Phoenix):**
```typescript
// Connect directly to Phoenix, bypassing Worker
import { Socket } from "phoenix";

const socket = new Socket("wss://api.uptrack.io/socket", {
  params: { token: userToken }
});

const channel = socket.channel(`monitors:${orgId}`);
channel.on("status_change", (payload) => {
  queryClient.invalidateQueries(["monitors"]);
});
```

### GraphQL Schema (Example)

```graphql
# packages/graphql/schema.graphql

type Query {
  monitors(orgId: ID!): [Monitor!]!
  monitor(id: ID!): Monitor
  metrics(monitorId: ID!, range: TimeRange!): MetricsSeries!
}

type Mutation {
  createMonitor(input: CreateMonitorInput!): Monitor!
  updateMonitor(id: ID!, input: UpdateMonitorInput!): Monitor!
  deleteMonitor(id: ID!): Boolean!
}

type Monitor {
  id: ID!
  name: String!
  url: String!
  status: MonitorStatus!
  lastCheckedAt: DateTime
  uptime24h: Float!
  responseTime: Int
}

enum MonitorStatus {
  UP
  DOWN
  DEGRADED
  PENDING
}
```

### In Scope

- TanStack Start application setup
- GraphQL API design and implementation (Phoenix)
- Cloudflare Workers deployment configuration
- Real-time WebSocket integration
- Monorepo structure with pnpm workspaces
- GraphQL codegen for type safety
- Authentication flow (OAuth)
- Core pages: Dashboard, Monitors, Alerts, Settings

### Out of Scope

- Marketing site / landing pages (can be separate)
- Mobile app
- Email templates
- Billing integration (Stripe) - separate spec

## Implementation Strategy

### Phase 1: Project Setup
- Create `web/` directory with TanStack Start
- Add root `package.json` with scripts
- Setup `schema.graphql` at root
- Configure GraphQL codegen

### Phase 2: GraphQL API (Phoenix)
- Add Absinthe to Phoenix (`mix.exs`)
- Define schema in `lib/uptrack_graphql/`
- Implement resolvers (monitors, users, alerts)
- Setup GraphQL endpoint at `/api/graphql`

### Phase 3: Frontend Core
- TanStack Start with file-based routing
- TanStack Query + urql for GraphQL
- Authentication flow (Phoenix sessions + JWT)
- Core components (layout, navigation, tables)

### Phase 4: Real-time
- Phoenix Channels setup (`/socket`)
- WebSocket connection from frontend (direct)
- Real-time monitor status updates
- Alert notifications (toast/badge)

### Phase 5: Deployment
- Cloudflare Workers config (`wrangler.toml`)
- CI/CD: GitHub Actions
  - `mix release` → deploy to Netcup
  - `wrangler deploy` → deploy to Workers
- Preview deployments for PRs

## Cost Analysis

| Service | Monthly Cost |
|---------|--------------|
| Cloudflare Workers | $0-5 |
| Cloudflare R2 (assets) | $0 |
| Domain (existing) | $0 |
| **Total Frontend** | **~$5/month** |

Combined with infrastructure (~€27/mo):
**Total: ~€32/month**

## Open Questions

1. **GraphQL library**: urql vs Apollo Client vs graphql-request?
   - Proposal: urql (lightweight, good DX)

2. **State management**: TanStack Query only or add Zustand?
   - Proposal: TanStack Query for server state, Zustand only if needed

3. **Component library**: Build custom or use shadcn/ui?
   - Proposal: shadcn/ui (copy-paste, customizable)

4. **Auth provider**: Custom or Clerk/Auth0?
   - Proposal: Custom with Phoenix (keep costs down)

## Success Criteria

- [ ] `web/` directory with TanStack Start initialized
- [ ] GraphQL API running on Phoenix (Absinthe)
- [ ] GraphQL codegen generating TypeScript types
- [ ] TanStack Start deployed to Cloudflare Workers
- [ ] Real-time updates via Phoenix WebSocket (direct)
- [ ] Authentication flow complete (login, logout, sessions)
- [ ] Core pages functional (Dashboard, Monitors, Settings)
- [ ] < 100ms TTFB globally (edge deployment)
- [ ] Lighthouse score > 90

## References

- [TanStack Start Documentation](https://tanstack.com/start/latest)
- [TanStack Query Documentation](https://tanstack.com/query/latest)
- [Cloudflare Workers Documentation](https://developers.cloudflare.com/workers/)
- [Absinthe GraphQL](https://hexdocs.pm/absinthe/)
- [Phoenix Channels](https://hexdocs.pm/phoenix/channels.html)
- [pnpm Workspaces](https://pnpm.io/workspaces)
