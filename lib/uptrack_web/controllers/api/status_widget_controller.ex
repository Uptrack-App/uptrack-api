defmodule UptrackWeb.Api.StatusWidgetController do
  @moduledoc """
  Generates embeddable status widgets for status pages.

  Provides JavaScript and HTML snippets that can be embedded in external websites
  to display real-time status information.
  """

  use UptrackWeb, :controller

  alias Uptrack.Monitoring

  @doc """
  Returns the widget JavaScript that can be embedded in external websites.
  """
  def script(conn, %{"slug" => slug} = params) do
    theme = params["theme"] || "light"

    case Monitoring.get_status_page_by_slug(slug) do
      nil ->
        conn
        |> put_resp_content_type("application/javascript")
        |> send_resp(404, "console.error('Uptrack: Status page not found');")

      _status_page ->
        base_url = get_base_url()
        script = widget_script(slug, base_url, theme)

        conn
        |> put_resp_content_type("application/javascript")
        |> put_resp_header("cache-control", "public, max-age=300, s-maxage=300")
        |> send_resp(200, script)
    end
  end

  @doc """
  Returns the widget data as JSON for dynamic updates.
  """
  def data(conn, %{"slug" => slug}) do
    case Monitoring.get_status_page_by_slug(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Status page not found"})

      status_page ->
        uptime = Monitoring.get_status_page_uptime(status_page.id, 30)
        status = Monitoring.get_status_page_status(status_page.id)

        conn
        |> put_resp_header("cache-control", "public, max-age=30, s-maxage=30")
        |> json(%{
          slug: slug,
          name: status_page.name,
          status: status,
          status_text: status_text(status),
          status_color: status_color(status),
          uptime: Float.round(uptime, 2),
          uptime_text: "#{Float.round(uptime, 2)}%",
          updated_at: DateTime.to_iso8601(DateTime.utc_now())
        })
    end
  end

  defp status_text(:operational), do: "All Systems Operational"
  defp status_text(:degraded), do: "Degraded Performance"
  defp status_text(:partial_outage), do: "Partial Outage"
  defp status_text(:major_outage), do: "Major Outage"
  defp status_text(_), do: "Unknown"

  defp status_color(:operational), do: "#22c55e"
  defp status_color(:degraded), do: "#eab308"
  defp status_color(:partial_outage), do: "#f97316"
  defp status_color(:major_outage), do: "#ef4444"
  defp status_color(_), do: "#9ca3af"

  defp get_base_url do
    Application.get_env(:uptrack, :app_url, "http://localhost:4000")
  end

  defp widget_script(slug, base_url, theme) do
    ~s"""
    (function() {
      'use strict';

      const UPTRACK_CONFIG = {
        slug: '#{escape_js(slug)}',
        baseUrl: '#{escape_js(base_url)}',
        theme: '#{escape_js(theme)}',
        refreshInterval: 60000
      };

      const styles = `
        .uptrack-widget {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          border-radius: 8px;
          padding: 16px;
          display: inline-flex;
          align-items: center;
          gap: 12px;
          text-decoration: none;
          transition: box-shadow 0.2s;
          ${UPTRACK_CONFIG.theme === 'dark' ? 'background: #1f2937; color: #f9fafb;' : 'background: #f9fafb; color: #111827; border: 1px solid #e5e7eb;'}
        }
        .uptrack-widget:hover {
          box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
        }
        .uptrack-status-dot {
          width: 12px;
          height: 12px;
          border-radius: 50%;
          animation: uptrack-pulse 2s infinite;
        }
        .uptrack-status-text {
          font-weight: 500;
          font-size: 14px;
        }
        .uptrack-uptime {
          font-size: 12px;
          opacity: 0.7;
        }
        @keyframes uptrack-pulse {
          0%, 100% { opacity: 1; }
          50% { opacity: 0.6; }
        }
      `;

      function createWidget(container) {
        // Add styles to document head
        const styleEl = document.createElement('style');
        styleEl.textContent = styles;
        document.head.appendChild(styleEl);

        // Build widget using safe DOM methods (no innerHTML with user content)
        const widget = document.createElement('a');
        widget.className = 'uptrack-widget';
        widget.href = UPTRACK_CONFIG.baseUrl + '/status/' + UPTRACK_CONFIG.slug;
        widget.target = '_blank';
        widget.rel = 'noopener';

        const dot = document.createElement('span');
        dot.className = 'uptrack-status-dot';
        dot.style.background = '#9ca3af';
        widget.appendChild(dot);

        const textContainer = document.createElement('span');

        const statusText = document.createElement('div');
        statusText.className = 'uptrack-status-text';
        statusText.textContent = 'Loading...';
        textContainer.appendChild(statusText);

        const uptimeText = document.createElement('div');
        uptimeText.className = 'uptrack-uptime';
        textContainer.appendChild(uptimeText);

        widget.appendChild(textContainer);
        container.appendChild(widget);

        return widget;
      }

      function updateWidget(widget, data) {
        const dot = widget.querySelector('.uptrack-status-dot');
        const statusText = widget.querySelector('.uptrack-status-text');
        const uptimeText = widget.querySelector('.uptrack-uptime');

        // Use textContent for safe text updates (no XSS risk)
        dot.style.background = data.status_color;
        statusText.textContent = data.status_text;
        uptimeText.textContent = data.uptime_text + ' uptime (30d)';
      }

      async function fetchStatus() {
        try {
          const response = await fetch(UPTRACK_CONFIG.baseUrl + '/api/widget/' + UPTRACK_CONFIG.slug + '/data');
          if (!response.ok) throw new Error('Failed to fetch status');
          return await response.json();
        } catch (error) {
          console.error('Uptrack widget error:', error);
          return null;
        }
      }

      async function init() {
        const containers = document.querySelectorAll('[data-uptrack-widget="' + UPTRACK_CONFIG.slug + '"]');
        if (containers.length === 0) {
          console.warn('Uptrack: No widget container found. Add data-uptrack-widget="' + UPTRACK_CONFIG.slug + '" to an element.');
          return;
        }

        const widgets = [];
        containers.forEach(function(container) {
          widgets.push(createWidget(container));
        });

        const data = await fetchStatus();
        if (data) {
          widgets.forEach(function(widget) { updateWidget(widget, data); });
        }

        // Refresh periodically
        setInterval(async function() {
          const data = await fetchStatus();
          if (data) {
            widgets.forEach(function(widget) { updateWidget(widget, data); });
          }
        }, UPTRACK_CONFIG.refreshInterval);
      }

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
      } else {
        init();
      }
    })();
    """
  end

  defp escape_js(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
  end
end
