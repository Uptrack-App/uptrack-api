# Implementation Tasks

## Phase 1: Project Setup

### 1.1 Frontend Directory
- [ ] Create `web/` directory
- [ ] Initialize TanStack Start: `npx create-tanstack-start@latest`
- [ ] Configure TypeScript (`tsconfig.json`)
- [ ] Add Tailwind CSS
- [ ] Add shadcn/ui components

### 1.2 GraphQL Setup
- [ ] Create `schema.graphql` at repo root
- [ ] Add `graphql-codegen` to `web/package.json`
- [ ] Configure codegen (`web/codegen.ts`)
- [ ] Add npm script: `"codegen": "graphql-codegen"`
- [ ] Generate initial types

### 1.3 Root Scripts
- [ ] Create root `package.json` with scripts:
  ```json
  {
    "scripts": {
      "web:dev": "cd web && npm run dev",
      "web:build": "cd web && npm run build",
      "web:deploy": "cd web && wrangler deploy",
      "codegen": "cd web && npm run codegen"
    }
  }
  ```

## Phase 2: GraphQL API (Phoenix)

### 2.1 Absinthe Setup
- [ ] Add deps to `mix.exs`:
  ```elixir
  {:absinthe, "~> 1.7"},
  {:absinthe_plug, "~> 1.5"},
  {:absinthe_phoenix, "~> 2.0"}
  ```
- [ ] Run `mix deps.get`
- [ ] Create `lib/uptrack_graphql/` directory

### 2.2 Schema Definition
- [ ] Create `lib/uptrack_graphql/schema.ex` (root schema)
- [ ] Create types:
  - [ ] `types/monitor.ex`
  - [ ] `types/user.ex`
  - [ ] `types/organization.ex`
  - [ ] `types/alert.ex`
  - [ ] `types/metrics.ex`
- [ ] Create queries:
  - [ ] `queries/monitor_queries.ex`
  - [ ] `queries/user_queries.ex`
- [ ] Create mutations:
  - [ ] `mutations/monitor_mutations.ex`
  - [ ] `mutations/alert_mutations.ex`

### 2.3 Resolvers
- [ ] Create `lib/uptrack_graphql/resolvers/`
- [ ] Implement resolvers:
  - [ ] `monitor_resolver.ex`
  - [ ] `user_resolver.ex`
  - [ ] `metrics_resolver.ex`

### 2.4 GraphQL Endpoint
- [ ] Add route in `router.ex`:
  ```elixir
  forward "/api/graphql", Absinthe.Plug, schema: UptrackGraphQL.Schema
  ```
- [ ] Add GraphiQL for development:
  ```elixir
  forward "/graphiql", Absinthe.Plug.GraphiQL, schema: UptrackGraphQL.Schema
  ```
- [ ] Test with sample query

## Phase 3: Frontend Core

### 3.1 GraphQL Client
- [ ] Install urql: `npm install urql graphql`
- [ ] Create `web/app/lib/graphql-client.ts`
- [ ] Configure urql with auth headers
- [ ] Add TanStack Query integration

### 3.2 Routing Structure
- [ ] Create routes:
  ```
  web/app/routes/
  ├── __root.tsx           # Root layout
  ├── index.tsx            # Landing/redirect
  ├── login.tsx            # Auth
  ├── dashboard/
  │   └── index.tsx        # Main dashboard
  ├── monitors/
  │   ├── index.tsx        # Monitor list
  │   └── $id.tsx          # Monitor detail
  ├── alerts/
  │   └── index.tsx        # Alert list
  └── settings/
      └── index.tsx        # Settings
  ```

### 3.3 Core Components
- [ ] Layout components:
  - [ ] `components/layout/sidebar.tsx`
  - [ ] `components/layout/header.tsx`
  - [ ] `components/layout/page-container.tsx`
- [ ] UI components (shadcn):
  - [ ] Button, Input, Card
  - [ ] Table (TanStack Table)
  - [ ] Dialog, Dropdown
  - [ ] Toast notifications
- [ ] Domain components:
  - [ ] `components/monitors/monitor-card.tsx`
  - [ ] `components/monitors/monitor-table.tsx`
  - [ ] `components/monitors/status-badge.tsx`
  - [ ] `components/charts/uptime-chart.tsx`

### 3.4 Authentication
- [ ] Create auth context/hooks
- [ ] Login page with form
- [ ] Protected route wrapper
- [ ] Token storage (httpOnly cookie preferred)
- [ ] Auto-refresh token logic

## Phase 4: Real-time

### 4.1 Phoenix Channels
- [ ] Create `lib/uptrack_web/channels/user_socket.ex`
- [ ] Create channels:
  - [ ] `monitor_channel.ex` - monitor status updates
  - [ ] `alert_channel.ex` - new alert notifications
- [ ] Add authentication to socket

### 4.2 Frontend WebSocket
- [ ] Install phoenix.js: `npm install phoenix`
- [ ] Create `web/app/lib/socket.ts`
- [ ] Connect directly to Phoenix (bypass Worker):
  ```typescript
  const socket = new Socket("wss://api.uptrack.io/socket");
  ```
- [ ] Create hooks:
  - [ ] `useMonitorChannel(monitorId)`
  - [ ] `useAlertsChannel(orgId)`
- [ ] Integrate with TanStack Query (invalidate on updates)

### 4.3 Real-time UI
- [ ] Live status badge updates
- [ ] Toast for new alerts
- [ ] Dashboard auto-refresh
- [ ] Connection status indicator

## Phase 5: Deployment

### 5.1 Cloudflare Workers
- [ ] Create `web/wrangler.toml`:
  ```toml
  name = "uptrack-web"
  main = ".output/server/index.mjs"
  compatibility_date = "2024-01-01"

  [vars]
  API_URL = "https://api.uptrack.io"
  ```
- [ ] Test locally: `wrangler dev`
- [ ] Deploy: `wrangler deploy`

### 5.2 Environment Configuration
- [ ] Create `.dev.vars` for local secrets
- [ ] Configure Workers secrets:
  - [ ] `API_URL`
  - [ ] `SESSION_SECRET`
- [ ] Setup custom domain in Cloudflare

### 5.3 CI/CD (GitHub Actions)
- [ ] Create `.github/workflows/deploy-web.yml`:
  ```yaml
  on:
    push:
      branches: [main]
      paths: ['web/**']
  jobs:
    deploy:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - uses: actions/setup-node@v4
        - run: cd web && npm ci && npm run build
        - run: cd web && wrangler deploy
          env:
            CLOUDFLARE_API_TOKEN: ${{ secrets.CF_API_TOKEN }}
  ```
- [ ] Add preview deployments for PRs

### 5.4 Phoenix API Deployment
- [ ] Update existing NixOS config for GraphQL endpoint
- [ ] Ensure CORS configured for Workers domain
- [ ] Configure WebSocket CORS for direct connection

## Validation Checklist

### Functional Tests
- [ ] GraphQL queries return data
- [ ] GraphQL mutations work (create/update/delete)
- [ ] Authentication flow (login → protected routes)
- [ ] Real-time updates (WebSocket connection)
- [ ] Codegen produces valid types

### Performance Tests
- [ ] TTFB < 100ms (edge)
- [ ] Lighthouse Performance > 90
- [ ] GraphQL query latency < 200ms
- [ ] WebSocket reconnection < 5s

### Deployment Tests
- [ ] Workers deployment successful
- [ ] Preview deployments work
- [ ] Custom domain configured
- [ ] SSL working

## Development Workflow

```bash
# Terminal 1: Phoenix API
mix phx.server

# Terminal 2: TanStack Start (dev)
cd web && npm run dev

# Terminal 3: GraphQL codegen (watch)
cd web && npm run codegen -- --watch

# Deploy frontend
npm run web:deploy

# Deploy API
mix release && # deploy to Netcup
```
