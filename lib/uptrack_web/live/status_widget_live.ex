defmodule UptrackWeb.StatusWidgetLive do
  @moduledoc """
  LiveView for embeddable status widgets that can be used on external websites.
  Provides mobile-responsive status widgets in different sizes and formats.
  """

  use UptrackWeb, :live_view

  alias Uptrack.Monitoring

  @impl true
  def mount(%{"slug" => slug} = params, _session, socket) do
    try do
      status_page = Monitoring.get_status_page_with_status!(slug)
      
      # Get widget configuration from params
      widget_type = Map.get(params, "type", "compact")
      theme = Map.get(params, "theme", "auto")
      
      # Calculate overall status
      overall_status = calculate_overall_status(status_page.monitors)
      
      socket =
        socket
        |> assign(:status_page, status_page)
        |> assign(:overall_status, overall_status)
        |> assign(:widget_type, widget_type)
        |> assign(:theme, theme)
        |> assign(:page_title, "#{status_page.name} Status Widget")

      {:ok, socket}
    rescue
      Ecto.NoResultsError ->
        {:ok, assign(socket, :error, "Status page not found")}
    end
  end

  @impl true
  def render(assigns) do
    if Map.has_key?(assigns, :error) do
      render_error(assigns)
    else
      case assigns.widget_type do
        "badge" -> render_badge_widget(assigns)
        "summary" -> render_summary_widget(assigns)
        "detailed" -> render_detailed_widget(assigns)
        _ -> render_compact_widget(assigns)
      end
    end
  end

  # Error state
  defp render_error(assigns) do
    ~H"""
    <div class="uptrack-widget uptrack-error" data-theme={@theme}>
      <div class="error-message">
        Status page not found
      </div>
      <style>
        .uptrack-widget.uptrack-error {
          padding: 12px;
          background: #fee2e2;
          border: 1px solid #fecaca;
          border-radius: 8px;
          color: #dc2626;
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 14px;
          max-width: 400px;
        }
      </style>
    </div>
    """
  end

  # Badge widget - minimal status indicator
  defp render_badge_widget(assigns) do
    ~H"""
    <div class="uptrack-widget uptrack-badge" data-theme={@theme} data-status={@overall_status}>
      <div class="status-indicator">
        <span class="status-dot"></span>
        <span class="status-text">{status_text(@overall_status)}</span>
      </div>
      
      <style>
        .uptrack-widget {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 14px;
          line-height: 1.4;
        }
        
        .uptrack-badge {
          display: inline-flex;
          align-items: center;
          padding: 8px 12px;
          background: var(--bg-color, #ffffff);
          border: 1px solid var(--border-color, #e5e7eb);
          border-radius: 20px;
          box-shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.1);
          transition: all 0.2s ease;
        }
        
        .uptrack-badge:hover {
          box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
        }
        
        .status-indicator {
          display: flex;
          align-items: center;
          gap: 8px;
        }
        
        .status-dot {
          width: 8px;
          height: 8px;
          border-radius: 50%;
          flex-shrink: 0;
        }
        
        .status-text {
          font-weight: 500;
          color: var(--text-color, #374151);
          white-space: nowrap;
        }
        
        /* Status colors */
        .uptrack-badge[data-status="operational"] .status-dot {
          background-color: #10b981;
        }
        
        .uptrack-badge[data-status="partial_outage"] .status-dot {
          background-color: #f59e0b;
        }
        
        .uptrack-badge[data-status="major_outage"] .status-dot {
          background-color: #ef4444;
        }
        
        .uptrack-badge[data-status="unknown"] .status-dot {
          background-color: #6b7280;
        }
        
        /* Theme variations */
        .uptrack-badge[data-theme="dark"] {
          --bg-color: #1f2937;
          --border-color: #374151;
          --text-color: #f9fafb;
        }
        
        .uptrack-badge[data-theme="light"] {
          --bg-color: #ffffff;
          --border-color: #e5e7eb;
          --text-color: #374151;
        }
        
        /* Auto theme based on system preference */
        @media (prefers-color-scheme: dark) {
          .uptrack-badge[data-theme="auto"] {
            --bg-color: #1f2937;
            --border-color: #374151;
            --text-color: #f9fafb;
          }
        }
      </style>
    </div>
    """
  end

  # Compact widget - status + service count
  defp render_compact_widget(assigns) do
    ~H"""
    <div class="uptrack-widget uptrack-compact" data-theme={@theme} data-status={@overall_status}>
      <div class="widget-header">
        <div class="status-info">
          <span class="status-dot"></span>
          <span class="status-text">{status_text(@overall_status)}</span>
        </div>
        <div class="service-count">
          {length(@status_page.monitors)} services
        </div>
      </div>
      
      <div class="widget-footer">
        <span class="powered-by">
          <a href={~p"/"} target="_blank">Uptrack</a>
        </span>
        <span class="last-updated">
          Updated {format_relative_time(DateTime.utc_now())}
        </span>
      </div>
      
      <style>
        .uptrack-compact {
          width: 100%;
          max-width: 300px;
          padding: 16px;
          background: var(--bg-color, #ffffff);
          border: 1px solid var(--border-color, #e5e7eb);
          border-radius: 12px;
          box-shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.1);
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
        }
        
        .widget-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 12px;
        }
        
        .status-info {
          display: flex;
          align-items: center;
          gap: 8px;
        }
        
        .status-dot {
          width: 12px;
          height: 12px;
          border-radius: 50%;
          flex-shrink: 0;
        }
        
        .status-text {
          font-weight: 600;
          font-size: 16px;
          color: var(--text-primary, #111827);
        }
        
        .service-count {
          font-size: 14px;
          color: var(--text-secondary, #6b7280);
        }
        
        .widget-footer {
          display: flex;
          justify-content: space-between;
          align-items: center;
          font-size: 12px;
          color: var(--text-tertiary, #9ca3af);
        }
        
        .powered-by a {
          color: var(--link-color, #3b82f6);
          text-decoration: none;
        }
        
        .powered-by a:hover {
          text-decoration: underline;
        }
        
        /* Status colors */
        .uptrack-compact[data-status="operational"] .status-dot {
          background-color: #10b981;
        }
        
        .uptrack-compact[data-status="partial_outage"] .status-dot {
          background-color: #f59e0b;
        }
        
        .uptrack-compact[data-status="major_outage"] .status-dot {
          background-color: #ef4444;
        }
        
        .uptrack-compact[data-status="unknown"] .status-dot {
          background-color: #6b7280;
        }
        
        /* Theme variations */
        .uptrack-compact[data-theme="dark"] {
          --bg-color: #1f2937;
          --border-color: #374151;
          --text-primary: #f9fafb;
          --text-secondary: #d1d5db;
          --text-tertiary: #9ca3af;
          --link-color: #60a5fa;
        }
        
        .uptrack-compact[data-theme="light"] {
          --bg-color: #ffffff;
          --border-color: #e5e7eb;
          --text-primary: #111827;
          --text-secondary: #6b7280;
          --text-tertiary: #9ca3af;
          --link-color: #3b82f6;
        }
        
        /* Auto theme */
        @media (prefers-color-scheme: dark) {
          .uptrack-compact[data-theme="auto"] {
            --bg-color: #1f2937;
            --border-color: #374151;
            --text-primary: #f9fafb;
            --text-secondary: #d1d5db;
            --text-tertiary: #9ca3af;
            --link-color: #60a5fa;
          }
        }
        
        /* Mobile responsive */
        @media (max-width: 480px) {
          .uptrack-compact {
            max-width: 100%;
            margin: 0 auto;
          }
          
          .widget-footer {
            flex-direction: column;
            gap: 4px;
            align-items: flex-start;
          }
        }
      </style>
    </div>
    """
  end

  # Summary widget - includes service list
  defp render_summary_widget(assigns) do
    ~H"""
    <div class="uptrack-widget uptrack-summary" data-theme={@theme} data-status={@overall_status}>
      <div class="widget-header">
        <h3 class="widget-title">{@status_page.name} Status</h3>
        <div class="overall-status">
          <span class="status-dot"></span>
          <span class="status-text">{status_text(@overall_status)}</span>
        </div>
      </div>
      
      <%= if Enum.any?(@status_page.monitors) do %>
        <div class="services-list">
          <%= for monitor <- Enum.take(@status_page.monitors, 5) do %>
            <div class="service-item" data-status={get_monitor_status(monitor)}>
              <div class="service-info">
                <span class="service-dot"></span>
                <span class="service-name">{monitor.name}</span>
              </div>
              <span class="service-status">{monitor_status_text(monitor)}</span>
            </div>
          <% end %>
          
          <%= if length(@status_page.monitors) > 5 do %>
            <div class="more-services">
              +{length(@status_page.monitors) - 5} more services
            </div>
          <% end %>
        </div>
      <% end %>
      
      <div class="widget-footer">
        <a href={~p"/status/#{@status_page.slug}"} target="_blank" class="view-full">
          View Full Status
        </a>
        <span class="last-updated">
          Updated {format_relative_time(DateTime.utc_now())}
        </span>
      </div>
      
      <style>
        .uptrack-summary {
          width: 100%;
          max-width: 400px;
          padding: 20px;
          background: var(--bg-color, #ffffff);
          border: 1px solid var(--border-color, #e5e7eb);
          border-radius: 12px;
          box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
        }
        
        .widget-header {
          margin-bottom: 16px;
        }
        
        .widget-title {
          font-size: 18px;
          font-weight: 700;
          margin: 0 0 8px 0;
          color: var(--text-primary, #111827);
        }
        
        .overall-status {
          display: flex;
          align-items: center;
          gap: 8px;
        }
        
        .status-dot, .service-dot {
          width: 10px;
          height: 10px;
          border-radius: 50%;
          flex-shrink: 0;
        }
        
        .status-text {
          font-weight: 600;
          color: var(--text-primary, #111827);
        }
        
        .services-list {
          margin-bottom: 16px;
        }
        
        .service-item {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: 8px 0;
          border-bottom: 1px solid var(--border-light, #f3f4f6);
        }
        
        .service-item:last-child {
          border-bottom: none;
        }
        
        .service-info {
          display: flex;
          align-items: center;
          gap: 8px;
        }
        
        .service-name {
          font-size: 14px;
          color: var(--text-primary, #111827);
        }
        
        .service-status {
          font-size: 12px;
          color: var(--text-secondary, #6b7280);
          font-weight: 500;
        }
        
        .more-services {
          text-align: center;
          padding: 8px;
          font-size: 12px;
          color: var(--text-secondary, #6b7280);
          font-style: italic;
        }
        
        .widget-footer {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding-top: 12px;
          border-top: 1px solid var(--border-light, #f3f4f6);
          font-size: 12px;
        }
        
        .view-full {
          color: var(--link-color, #3b82f6);
          text-decoration: none;
          font-weight: 500;
        }
        
        .view-full:hover {
          text-decoration: underline;
        }
        
        .last-updated {
          color: var(--text-tertiary, #9ca3af);
        }
        
        /* Status colors for overall status */
        .uptrack-summary[data-status="operational"] .status-dot {
          background-color: #10b981;
        }
        
        .uptrack-summary[data-status="partial_outage"] .status-dot {
          background-color: #f59e0b;
        }
        
        .uptrack-summary[data-status="major_outage"] .status-dot {
          background-color: #ef4444;
        }
        
        .uptrack-summary[data-status="unknown"] .status-dot {
          background-color: #6b7280;
        }
        
        /* Service status colors */
        .service-item[data-status="up"] .service-dot {
          background-color: #10b981;
        }
        
        .service-item[data-status="down"] .service-dot {
          background-color: #ef4444;
        }
        
        .service-item[data-status="unknown"] .service-dot {
          background-color: #6b7280;
        }
        
        /* Theme variations */
        .uptrack-summary[data-theme="dark"] {
          --bg-color: #1f2937;
          --border-color: #374151;
          --border-light: #374151;
          --text-primary: #f9fafb;
          --text-secondary: #d1d5db;
          --text-tertiary: #9ca3af;
          --link-color: #60a5fa;
        }
        
        .uptrack-summary[data-theme="light"] {
          --bg-color: #ffffff;
          --border-color: #e5e7eb;
          --border-light: #f3f4f6;
          --text-primary: #111827;
          --text-secondary: #6b7280;
          --text-tertiary: #9ca3af;
          --link-color: #3b82f6;
        }
        
        /* Auto theme */
        @media (prefers-color-scheme: dark) {
          .uptrack-summary[data-theme="auto"] {
            --bg-color: #1f2937;
            --border-color: #374151;
            --border-light: #374151;
            --text-primary: #f9fafb;
            --text-secondary: #d1d5db;
            --text-tertiary: #9ca3af;
            --link-color: #60a5fa;
          }
        }
        
        /* Mobile responsive */
        @media (max-width: 480px) {
          .uptrack-summary {
            max-width: 100%;
            padding: 16px;
          }
          
          .widget-footer {
            flex-direction: column;
            gap: 8px;
            align-items: flex-start;
          }
          
          .service-item {
            flex-direction: column;
            align-items: flex-start;
            gap: 4px;
          }
          
          .service-info {
            width: 100%;
          }
          
          .service-status {
            align-self: flex-end;
          }
        }
      </style>
    </div>
    """
  end

  # Detailed widget - full service list with response times
  defp render_detailed_widget(assigns) do
    ~H"""
    <div class="uptrack-widget uptrack-detailed" data-theme={@theme} data-status={@overall_status}>
      <div class="widget-header">
        <%= if @status_page.logo_url do %>
          <img src={@status_page.logo_url} alt={@status_page.name} class="widget-logo" />
        <% end %>
        <h3 class="widget-title">{@status_page.name}</h3>
        <div class="overall-status">
          <span class="status-dot"></span>
          <span class="status-text">{status_text(@overall_status)}</span>
        </div>
        <%= if @status_page.description do %>
          <p class="widget-description">{@status_page.description}</p>
        <% end %>
      </div>
      
      <%= if Enum.any?(@status_page.monitors) do %>
        <div class="services-detailed">
          <%= for monitor <- @status_page.monitors do %>
            <div class="service-detailed" data-status={get_monitor_status(monitor)}>
              <div class="service-header">
                <div class="service-info">
                  <span class="service-dot"></span>
                  <div>
                    <div class="service-name">{monitor.name}</div>
                    <div class="service-url">{monitor.url}</div>
                  </div>
                </div>
                <div class="service-metrics">
                  <span class="service-status">{monitor_status_text(monitor)}</span>
                  <%= if latest_check = get_latest_check(monitor) do %>
                    <%= if latest_check.response_time do %>
                      <span class="response-time">{latest_check.response_time}ms</span>
                    <% end %>
                    <span class="last-check">{time_ago(latest_check.checked_at)}</span>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% else %>
        <div class="no-services">
          <p>No services configured for monitoring.</p>
        </div>
      <% end %>
      
      <div class="widget-footer">
        <a href={~p"/status/#{@status_page.slug}"} target="_blank" class="view-full">
          View Full Status Page
        </a>
        <span class="last-updated">
          Last updated: {format_relative_time(DateTime.utc_now())}
        </span>
      </div>
      
      <style>
        .uptrack-detailed {
          width: 100%;
          max-width: 500px;
          padding: 24px;
          background: var(--bg-color, #ffffff);
          border: 1px solid var(--border-color, #e5e7eb);
          border-radius: 16px;
          box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1);
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
        }
        
        .widget-header {
          text-align: center;
          margin-bottom: 20px;
        }
        
        .widget-logo {
          height: 32px;
          margin-bottom: 8px;
        }
        
        .widget-title {
          font-size: 20px;
          font-weight: 700;
          margin: 0 0 12px 0;
          color: var(--text-primary, #111827);
        }
        
        .widget-description {
          font-size: 14px;
          color: var(--text-secondary, #6b7280);
          margin: 8px 0 0 0;
          line-height: 1.4;
        }
        
        .overall-status {
          display: inline-flex;
          align-items: center;
          gap: 8px;
          padding: 8px 16px;
          background: var(--status-bg, #f3f4f6);
          border-radius: 20px;
        }
        
        .status-dot, .service-dot {
          width: 12px;
          height: 12px;
          border-radius: 50%;
          flex-shrink: 0;
        }
        
        .status-text {
          font-weight: 600;
          font-size: 14px;
          color: var(--text-primary, #111827);
        }
        
        .services-detailed {
          margin-bottom: 20px;
        }
        
        .service-detailed {
          margin-bottom: 12px;
          padding: 16px;
          background: var(--service-bg, #f9fafb);
          border: 1px solid var(--border-light, #f3f4f6);
          border-radius: 12px;
        }
        
        .service-header {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          gap: 16px;
        }
        
        .service-info {
          display: flex;
          align-items: flex-start;
          gap: 12px;
          flex: 1;
        }
        
        .service-name {
          font-size: 16px;
          font-weight: 600;
          color: var(--text-primary, #111827);
          margin-bottom: 2px;
        }
        
        .service-url {
          font-size: 12px;
          color: var(--text-tertiary, #9ca3af);
          font-family: monospace;
        }
        
        .service-metrics {
          display: flex;
          flex-direction: column;
          align-items: flex-end;
          gap: 2px;
          text-align: right;
        }
        
        .service-status {
          font-size: 12px;
          font-weight: 600;
          padding: 4px 8px;
          border-radius: 8px;
        }
        
        .response-time {
          font-size: 11px;
          color: var(--text-secondary, #6b7280);
          font-weight: 500;
        }
        
        .last-check {
          font-size: 10px;
          color: var(--text-tertiary, #9ca3af);
        }
        
        .no-services {
          text-align: center;
          padding: 40px 20px;
          color: var(--text-secondary, #6b7280);
        }
        
        .widget-footer {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding-top: 16px;
          border-top: 1px solid var(--border-light, #f3f4f6);
          font-size: 12px;
        }
        
        .view-full {
          color: var(--link-color, #3b82f6);
          text-decoration: none;
          font-weight: 600;
          padding: 8px 12px;
          border-radius: 8px;
          background: var(--link-bg, #eff6ff);
        }
        
        .view-full:hover {
          background: var(--link-bg-hover, #dbeafe);
        }
        
        .last-updated {
          color: var(--text-tertiary, #9ca3af);
        }
        
        /* Status colors for overall status */
        .uptrack-detailed[data-status="operational"] .status-dot {
          background-color: #10b981;
        }
        
        .uptrack-detailed[data-status="operational"] .overall-status {
          background-color: #ecfdf5;
          color: #065f46;
        }
        
        .uptrack-detailed[data-status="partial_outage"] .status-dot {
          background-color: #f59e0b;
        }
        
        .uptrack-detailed[data-status="partial_outage"] .overall-status {
          background-color: #fffbeb;
          color: #92400e;
        }
        
        .uptrack-detailed[data-status="major_outage"] .status-dot {
          background-color: #ef4444;
        }
        
        .uptrack-detailed[data-status="major_outage"] .overall-status {
          background-color: #fef2f2;
          color: #991b1b;
        }
        
        .uptrack-detailed[data-status="unknown"] .status-dot {
          background-color: #6b7280;
        }
        
        /* Service status colors and styling */
        .service-detailed[data-status="up"] .service-dot {
          background-color: #10b981;
        }
        
        .service-detailed[data-status="up"] .service-status {
          background-color: #ecfdf5;
          color: #065f46;
        }
        
        .service-detailed[data-status="down"] .service-dot {
          background-color: #ef4444;
        }
        
        .service-detailed[data-status="down"] .service-status {
          background-color: #fef2f2;
          color: #991b1b;
        }
        
        .service-detailed[data-status="unknown"] .service-dot {
          background-color: #6b7280;
        }
        
        .service-detailed[data-status="unknown"] .service-status {
          background-color: #f3f4f6;
          color: #4b5563;
        }
        
        /* Theme variations */
        .uptrack-detailed[data-theme="dark"] {
          --bg-color: #1f2937;
          --border-color: #374151;
          --border-light: #374151;
          --service-bg: #374151;
          --status-bg: #374151;
          --text-primary: #f9fafb;
          --text-secondary: #d1d5db;
          --text-tertiary: #9ca3af;
          --link-color: #60a5fa;
          --link-bg: #1e3a8a;
          --link-bg-hover: #1e40af;
        }
        
        .uptrack-detailed[data-theme="light"] {
          --bg-color: #ffffff;
          --border-color: #e5e7eb;
          --border-light: #f3f4f6;
          --service-bg: #f9fafb;
          --status-bg: #f3f4f6;
          --text-primary: #111827;
          --text-secondary: #6b7280;
          --text-tertiary: #9ca3af;
          --link-color: #3b82f6;
          --link-bg: #eff6ff;
          --link-bg-hover: #dbeafe;
        }
        
        /* Auto theme */
        @media (prefers-color-scheme: dark) {
          .uptrack-detailed[data-theme="auto"] {
            --bg-color: #1f2937;
            --border-color: #374151;
            --border-light: #374151;
            --service-bg: #374151;
            --status-bg: #374151;
            --text-primary: #f9fafb;
            --text-secondary: #d1d5db;
            --text-tertiary: #9ca3af;
            --link-color: #60a5fa;
            --link-bg: #1e3a8a;
            --link-bg-hover: #1e40af;
          }
        }
        
        /* Mobile responsive */
        @media (max-width: 480px) {
          .uptrack-detailed {
            max-width: 100%;
            padding: 20px;
          }
          
          .service-header {
            flex-direction: column;
            align-items: flex-start;
            gap: 12px;
          }
          
          .service-metrics {
            align-items: flex-start;
            text-align: left;
            width: 100%;
          }
          
          .widget-footer {
            flex-direction: column;
            gap: 12px;
            align-items: flex-start;
          }
          
          .view-full {
            align-self: stretch;
            text-align: center;
          }
        }
      </style>
    </div>
    """
  end

  # Helper functions (reuse from StatusLive)
  
  defp calculate_overall_status(monitors) do
    if Enum.empty?(monitors) do
      :unknown
    else
      down_count =
        Enum.count(monitors, fn monitor ->
          case get_latest_check(monitor) do
            nil -> false
            check -> check.status == "down"
          end
        end)

      cond do
        down_count == 0 -> :operational
        down_count == length(monitors) -> :major_outage
        true -> :partial_outage
      end
    end
  end

  defp status_text(:operational), do: "All Systems Operational"
  defp status_text(:partial_outage), do: "Partial Outage"
  defp status_text(:major_outage), do: "Major Outage"
  defp status_text(_), do: "Unknown Status"

  defp get_monitor_status(monitor) do
    case get_latest_check(monitor) do
      nil -> :unknown
      check ->
        case check.status do
          "up" -> :up
          "down" -> :down
          _ -> :unknown
        end
    end
  end

  defp monitor_status_text(monitor) do
    case get_latest_check(monitor) do
      nil -> "Unknown"
      check ->
        case check.status do
          "up" -> "Operational"
          "down" -> "Down"
          _ -> "Issues"
        end
    end
  end

  defp get_latest_check(monitor) do
    case monitor.monitor_checks do
      [check | _] -> check
      [] -> nil
    end
  end

  defp time_ago(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end

  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end
end