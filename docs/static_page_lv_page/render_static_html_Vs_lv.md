 ---
  The Pattern: Dashbit's Full Stack

  Here's how Dashbit structures their entire site:

  | Page Type         | Technology                 | Why
         |
  |-------------------|----------------------------|-------------------------------------
  -------|
  | Homepage (/)      | Phoenix templates (static) | Marketing content, no interactivity
  needed |
  | Blog (/blog)      | Phoenix + NimblePublisher  | Git-based content, compile-time
  rendering  |
  | Interactive tools | Phoenix LiveView           | Where real-time is valuable
         |

  ---
  What This Means for Uptrack

  You should follow the exact same pattern:

  1. Homepage (Marketing) - NO LiveView

  # lib/uptrack_web/router.ex
  scope "/", UptrackWeb do
    pipe_through :browser

    # Static Phoenix template (NO LiveView)
    get "/", PageController, :index
  end

  # lib/uptrack_web/controllers/page_controller.ex
  defmodule UptrackWeb.PageController do
    use UptrackWeb, :controller

    def index(conn, _params) do
      # Just render static template
      render(conn, :index)
    end
  end

  <!-- lib/uptrack_web/controllers/page_html/index.html.heex -->
  <div class="hero">
    <h1>Monitor Your APIs with Confidence</h1>
    <p>Uptime monitoring from 10+ global locations</p>
    <a href="/app/signup" class="cta-button">Start Free Trial</a>
  </div>

  <div class="features">
    <!-- Static marketing content -->
  </div>

  Result:
  - ⚡ Super fast (no WebSocket overhead)
  - 💰 Zero server resources per visitor
  - 📈 Scales infinitely (can CDN cache)
  - 🎯 SEO-friendly (static HTML)

  ---
  2. App Dashboard - YES LiveView

  # lib/uptrack_web/router.ex
  scope "/app", UptrackWeb do
    pipe_through [:browser, :require_auth]

    # LiveView for authenticated users
    live "/dashboard", DashboardLive
    live "/monitors", MonitorsLive
  end

  Result:
  - ⚡ Real-time updates (monitor status changes)
  - 🎯 Interactive UI (instant feedback)
  - 💎 Worth the cost (paying customers only)

  ---
  Resource Usage Comparison

  Scenario: 1,000 homepage visitors + 100 active app users

  Option 1: LiveView Everywhere ❌

  Homepage: 1,000 visitors × 50KB = 50MB RAM
  App: 100 users × 50KB = 5MB RAM
  Total: 55MB RAM for 1,100 connections

  Option 2: Static Homepage + LiveView App ✅

  Homepage: 1,000 visitors × 0KB = 0MB RAM
  App: 100 users × 50KB = 5MB RAM
  Total: 5MB RAM for 100 connections

  Savings: 91% less memory for the same traffic!

  ---
  Bottom Line for Uptrack

  Homepage: Use what Dashbit uses → Regular Phoenix templates (static HTML)Blog/Docs (if
  needed): Use NimblePublisher (compile-time Markdown)App Dashboard: Use LiveView
  (real-time monitoring features)

  This gives you:
  - Marketing pages that scale to millions (static)
  - App features with great UX (LiveView)
  - Efficient resource usage (RAM only for paying users)

  Want me to help you implement this architecture in Uptrack? I can show you how to set
  up a static homepage while keeping LiveView for your dashboard.


  ## how about tidewave
    Based on my analysis, here's what tidewave.ai uses:

  Technology Stack

  Framework: Likely Phoenix (given it's a Dashbit product)Frontend: Static HTML + Vanilla
   JavaScriptLiveView: NO (not used for the marketing homepage)Approach: Pre-rendered
  templates with progressive enhancement

  Evidence

  From the page source analysis:
  - ✅ Vanilla JavaScript (no React/Vue/frameworks)
  - ✅ Static HTML (pre-rendered content)
  - ✅ No WebSockets (no LiveView)
  - ✅ Asset versioning (?vsn=d) - typical Phoenix asset pipeline
  - ✅ Simple interactivity (scroll effects, video playback via IntersectionObserver)

  What This Tells Us

  Tidewave is a Dashbit product → They follow the same pattern:
  - Marketing site: Regular Phoenix or static HTML (fast, simple)
  - Product itself: Phoenix + LiveView (for Tidewave Web's interactive features)

  ---
  The Pattern is Clear: Dashbit's Philosophy

  All Dashbit properties follow the same architecture:

  | Site             | Homepage Tech              | Interactive Features      |
  |------------------|----------------------------|---------------------------|
  | dashbit.co       | Phoenix templates (static) | None needed               |
  | tidewave.ai      | Phoenix templates (static) | None on homepage          |
  | Dashbit blog     | Phoenix + NimblePublisher  | Tag filtering, pagination |
  | Tidewave Web app | Phoenix + LiveView         | AI coding agent interface |

  ---
  Key Insight: Tidewave Homepage

  What they DON'T use:
  - ❌ LiveView (no WebSockets)
  - ❌ React/Vue/heavy JS frameworks
  - ❌ Client-side rendering
  - ❌ Database queries per request

  What they DO use:
  - ✅ Static HTML (fast first paint)
  - ✅ Vanilla JS (minimal, progressive)
  - ✅ Phoenix asset pipeline (versioning)
  - ✅ CDN-friendly output

  Lighthouse Performance: Likely 95-100 (like Dashbit's blog)

  ---
  Why This Matters for Uptrack

  Tidewave.ai proves the pattern:

  1. Marketing homepage → Keep it simple (static/Phoenix templates)
  2. Product features → Use LiveView where it adds value
  3. Don't waste resources → No WebSockets for static content

  Real Resource Comparison

  If Uptrack had 10k marketing visitors + 1k app users:

  | Approach                       | Memory Usage | Connection Cost   |
  |--------------------------------|--------------|-------------------|
  | LiveView everywhere            | 550MB        | 11,000 WebSockets |
  | Static homepage + LiveView app | 50MB         | 1,000 WebSockets  |
  | Savings                        | 91% less     | 91% fewer         |

  ---
  Recommendation for Uptrack Homepage

  Follow the exact Dashbit/Tidewave pattern:

  # lib/uptrack_web/router.ex
  scope "/", UptrackWeb do
    pipe_through :browser

    # Static Phoenix controller (NO LiveView)
    get "/", PageController, :home
    get "/pricing", PageController, :pricing
    get "/features", PageController, :features
    get "/about", PageController, :about
  end

  scope "/app", UptrackWeb do
    pipe_through [:browser, :require_auth]

    # LiveView for authenticated dashboard
    live "/dashboard", DashboardLive
    live "/monitors", MonitorsLive
    live "/alerts", AlertsLive
  end

  Homepage Template (Static Phoenix)

  <!-- lib/uptrack_web/controllers/page_html/home.html.heex -->
  <div class="hero">
    <h1>Monitor Your APIs from 10+ Global Locations</h1>
    <p>Real-time uptime monitoring with instant alerts</p>
    <a href="/app/signup" class="cta-button">Start Free Trial</a>
  </div>

  <div class="features">
    <div class="feature">
      <h3>🌍 Global Monitoring</h3>
      <p>Check uptime from multiple continents</p>
    </div>
    <!-- More static content... -->
  </div>

  <script>
    // Vanilla JS for simple interactions (like Tidewave)
    document.querySelectorAll('.feature').forEach(el => {
      el.addEventListener('mouseenter', () => {
        el.classList.add('highlighted');
      });
    });
  </script>

  Result:
  - ⚡ Blazing fast (no WebSocket overhead)
  - 💰 Zero memory cost for visitors
  - 📈 Infinite scalability (static content)
  - 🎯 SEO optimized (pre-rendered HTML)

  ---
  Bottom Line

  Tidewave.ai homepage = Static HTML + vanilla JS (NO LiveView)Tidewave.ai product =
  Phoenix + LiveView (where it matters)

  Uptrack should do the same:
  - Homepage → Static/Phoenix templates
  - Dashboard → LiveView for real-time features

  This is the proven Dashbit pattern used across all their products.

