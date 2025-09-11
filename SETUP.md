# Uptrack - UptimeRobot Clone

A Phoenix LiveView application that provides uptime monitoring services similar to UptimeRobot.

## Features Implemented

### ✅ Authentication System
- **Sign up with multiple options:**
  - GitHub OAuth
  - Google OAuth
  - Email/Password registration
- User accounts with secure password hashing (Bcrypt)
- Session-based authentication

### ✅ User Interface
- **Landing Page:** Beautiful gradient landing page with feature highlights
- **Sign-up Page:** Clean interface with OAuth buttons and email form
- **Dashboard:** Basic dashboard layout for authenticated users

### ✅ Core Infrastructure
- Phoenix LiveView for reactive UI
- PostgreSQL database with Ecto
- Tailwind CSS for styling
- OAuth integration with Ueberauth

## Current Setup

The application is running at: http://localhost:4000

### Routes Available:
- `/` - Landing page
- `/auth/signup` - Sign up page
- `/dashboard` - User dashboard (requires authentication)
- `/auth/github` - GitHub OAuth
- `/auth/google` - Google OAuth
- `/auth/logout` - Sign out

## OAuth Configuration

To enable OAuth providers, set these environment variables:

```bash
export GITHUB_CLIENT_ID="your_github_client_id"
export GITHUB_CLIENT_SECRET="your_github_client_secret"
export GOOGLE_CLIENT_ID="your_google_client_id"
export GOOGLE_CLIENT_SECRET="your_google_client_secret"
```

## Next Steps for Full UptimeRobot Functionality

### 🚧 Pending Features

1. **Monitor Management**
   - Create/Edit/Delete monitors
   - Support for HTTP, HTTPS, Ping, Port monitoring
   - SSL certificate monitoring
   - Keyword monitoring

2. **Check System**
   - Background workers for performing checks
   - Configurable check intervals
   - Response time tracking
   - Uptime statistics

3. **Alerting**
   - Email notifications
   - SMS alerts (via providers like Twilio)
   - Slack/Discord webhooks
   - Custom webhook support

4. **Status Pages**
   - Public status pages
   - Incident management
   - Status history

5. **Reporting**
   - Uptime reports
   - Performance metrics
   - Downtime analysis

## Technology Stack

- **Backend:** Elixir/Phoenix
- **Frontend:** Phoenix LiveView + Tailwind CSS
- **Database:** PostgreSQL
- **Authentication:** Ueberauth (GitHub/Google) + Bcrypt
- **Real-time:** Phoenix LiveView + PubSub

## Database Schema

Currently implemented:
- `users` table with OAuth and email authentication support

## Development Commands

```bash
# Install dependencies
mix deps.get

# Create database
mix ecto.create

# Run migrations
mix ecto.migrate

# Start server
mix phx.server

# Run tests
mix test
```

The foundation is now ready for building the complete monitoring functionality!