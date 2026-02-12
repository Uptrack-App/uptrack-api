defmodule UptrackWeb.Api.StatusBadgeController do
  @moduledoc """
  Generates SVG status badges for status pages.

  Badges can be embedded in READMEs, documentation, and landing pages
  to show real-time uptime status.
  """

  use UptrackWeb, :controller

  alias Uptrack.Monitoring

  @doc """
  Serves the default uptime badge for a status page.
  """
  def show(conn, %{"slug" => slug} = params) do
    style = params["style"] || "flat"
    label = params["label"] || "uptime"

    case Monitoring.get_status_page_by_slug(slug) do
      nil ->
        conn
        |> put_resp_content_type("image/svg+xml")
        |> send_resp(404, error_badge("Not Found", style))

      status_page ->
        uptime = Monitoring.get_status_page_uptime(status_page.id, 30)
        badge_svg = uptime_badge(label, uptime, style)

        conn
        |> put_resp_content_type("image/svg+xml")
        |> put_resp_header("cache-control", "public, max-age=60, s-maxage=60")
        |> send_resp(200, badge_svg)
    end
  end

  @doc """
  Serves a status badge showing current operational status.
  """
  def status(conn, %{"slug" => slug} = params) do
    style = params["style"] || "flat"

    case Monitoring.get_status_page_by_slug(slug) do
      nil ->
        conn
        |> put_resp_content_type("image/svg+xml")
        |> send_resp(404, error_badge("Not Found", style))

      status_page ->
        {status_text, color} = get_overall_status(status_page.id)
        badge_svg = status_badge(status_text, color, style)

        conn
        |> put_resp_content_type("image/svg+xml")
        |> put_resp_header("cache-control", "public, max-age=30, s-maxage=30")
        |> send_resp(200, badge_svg)
    end
  end

  @doc """
  Serves an uptime percentage badge with custom time range.
  """
  def uptime(conn, %{"slug" => slug} = params) do
    style = params["style"] || "flat"
    days = parse_days(params["days"])

    case Monitoring.get_status_page_by_slug(slug) do
      nil ->
        conn
        |> put_resp_content_type("image/svg+xml")
        |> send_resp(404, error_badge("Not Found", style))

      status_page ->
        uptime = Monitoring.get_status_page_uptime(status_page.id, days)
        label = "uptime (#{days}d)"
        badge_svg = uptime_badge(label, uptime, style)

        conn
        |> put_resp_content_type("image/svg+xml")
        |> put_resp_header("cache-control", "public, max-age=60, s-maxage=60")
        |> send_resp(200, badge_svg)
    end
  end

  # Badge generation functions

  defp uptime_badge(label, uptime, style) do
    value = "#{Float.round(uptime, 2)}%"
    color = uptime_color(uptime)
    generate_badge(label, value, color, style)
  end

  defp status_badge(status_text, color, style) do
    generate_badge("status", status_text, color, style)
  end

  defp error_badge(message, style) do
    generate_badge("status", message, "#9f9f9f", style)
  end

  defp uptime_color(uptime) when uptime >= 99.9, do: "#4c1"      # Green
  defp uptime_color(uptime) when uptime >= 99.0, do: "#97ca00"   # Light green
  defp uptime_color(uptime) when uptime >= 95.0, do: "#dfb317"   # Yellow
  defp uptime_color(uptime) when uptime >= 90.0, do: "#fe7d37"   # Orange
  defp uptime_color(_uptime), do: "#e05d44"                       # Red

  defp get_overall_status(status_page_id) do
    case Monitoring.get_status_page_status(status_page_id) do
      :operational -> {"operational", "#4c1"}
      :degraded -> {"degraded", "#dfb317"}
      :partial_outage -> {"partial outage", "#fe7d37"}
      :major_outage -> {"major outage", "#e05d44"}
      _ -> {"unknown", "#9f9f9f"}
    end
  end

  defp parse_days(nil), do: 30
  defp parse_days(days) when is_binary(days) do
    case Integer.parse(days) do
      {n, _} when n > 0 and n <= 365 -> n
      _ -> 30
    end
  end

  defp generate_badge(label, value, color, style) do
    label_width = estimate_text_width(label)
    value_width = estimate_text_width(value)
    total_width = label_width + value_width + 20  # 10px padding on each side

    case style do
      "flat-square" -> flat_square_badge(label, value, color, label_width, value_width, total_width)
      "plastic" -> plastic_badge(label, value, color, label_width, value_width, total_width)
      "for-the-badge" -> for_the_badge(label, value, color, label_width, value_width, total_width)
      _ -> flat_badge(label, value, color, label_width, value_width, total_width)
    end
  end

  defp flat_badge(label, value, color, label_width, value_width, total_width) do
    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{total_width}" height="20" role="img" aria-label="#{label}: #{value}">
      <title>#{label}: #{value}</title>
      <linearGradient id="s" x2="0" y2="100%">
        <stop offset="0" stop-color="#bbb" stop-opacity=".1"/>
        <stop offset="1" stop-opacity=".1"/>
      </linearGradient>
      <clipPath id="r">
        <rect width="#{total_width}" height="20" rx="3" fill="#fff"/>
      </clipPath>
      <g clip-path="url(#r)">
        <rect width="#{label_width + 10}" height="20" fill="#555"/>
        <rect x="#{label_width + 10}" width="#{value_width + 10}" height="20" fill="#{color}"/>
        <rect width="#{total_width}" height="20" fill="url(#s)"/>
      </g>
      <g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" text-rendering="geometricPrecision" font-size="110">
        <text aria-hidden="true" x="#{(label_width + 10) * 5}" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="#{label_width * 10}">#{escape_xml(label)}</text>
        <text x="#{(label_width + 10) * 5}" y="140" transform="scale(.1)" fill="#fff" textLength="#{label_width * 10}">#{escape_xml(label)}</text>
        <text aria-hidden="true" x="#{(label_width + 10 + value_width / 2 + 5) * 10}" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="#{value_width * 10}">#{escape_xml(value)}</text>
        <text x="#{(label_width + 10 + value_width / 2 + 5) * 10}" y="140" transform="scale(.1)" fill="#fff" textLength="#{value_width * 10}">#{escape_xml(value)}</text>
      </g>
    </svg>
    """
  end

  defp flat_square_badge(label, value, color, label_width, value_width, total_width) do
    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{total_width}" height="20" role="img" aria-label="#{label}: #{value}">
      <title>#{label}: #{value}</title>
      <g shape-rendering="crispEdges">
        <rect width="#{label_width + 10}" height="20" fill="#555"/>
        <rect x="#{label_width + 10}" width="#{value_width + 10}" height="20" fill="#{color}"/>
      </g>
      <g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" text-rendering="geometricPrecision" font-size="110">
        <text x="#{(label_width + 10) * 5}" y="140" transform="scale(.1)" fill="#fff" textLength="#{label_width * 10}">#{escape_xml(label)}</text>
        <text x="#{(label_width + 10 + value_width / 2 + 5) * 10}" y="140" transform="scale(.1)" fill="#fff" textLength="#{value_width * 10}">#{escape_xml(value)}</text>
      </g>
    </svg>
    """
  end

  defp plastic_badge(label, value, color, label_width, value_width, total_width) do
    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{total_width}" height="18" role="img" aria-label="#{label}: #{value}">
      <title>#{label}: #{value}</title>
      <linearGradient id="s" x2="0" y2="100%">
        <stop offset="0" stop-color="#fff" stop-opacity=".7"/>
        <stop offset=".1" stop-color="#aaa" stop-opacity=".1"/>
        <stop offset=".9" stop-color="#000" stop-opacity=".3"/>
        <stop offset="1" stop-color="#000" stop-opacity=".5"/>
      </linearGradient>
      <clipPath id="r">
        <rect width="#{total_width}" height="18" rx="4" fill="#fff"/>
      </clipPath>
      <g clip-path="url(#r)">
        <rect width="#{label_width + 10}" height="18" fill="#555"/>
        <rect x="#{label_width + 10}" width="#{value_width + 10}" height="18" fill="#{color}"/>
        <rect width="#{total_width}" height="18" fill="url(#s)"/>
      </g>
      <g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" text-rendering="geometricPrecision" font-size="110">
        <text x="#{(label_width + 10) * 5}" y="130" transform="scale(.1)" fill="#fff" textLength="#{label_width * 10}">#{escape_xml(label)}</text>
        <text x="#{(label_width + 10 + value_width / 2 + 5) * 10}" y="130" transform="scale(.1)" fill="#fff" textLength="#{value_width * 10}">#{escape_xml(value)}</text>
      </g>
    </svg>
    """
  end

  defp for_the_badge(label, value, color, _label_width, _value_width, _total_width) do
    # for-the-badge style uses larger text and uppercase
    label = String.upcase(label)
    value = String.upcase(value)
    label_width = estimate_text_width(label) * 1.2
    value_width = estimate_text_width(value) * 1.2
    total_width = label_width + value_width + 30

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{total_width}" height="28" role="img" aria-label="#{label}: #{value}">
      <title>#{label}: #{value}</title>
      <clipPath id="r">
        <rect width="#{total_width}" height="28" rx="3" fill="#fff"/>
      </clipPath>
      <g clip-path="url(#r)">
        <rect width="#{label_width + 15}" height="28" fill="#555"/>
        <rect x="#{label_width + 15}" width="#{value_width + 15}" height="28" fill="#{color}"/>
      </g>
      <g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" font-weight="bold" text-rendering="geometricPrecision" font-size="100">
        <text x="#{(label_width + 15) * 5}" y="175" transform="scale(.1)" fill="#fff" textLength="#{label_width * 10}">#{escape_xml(label)}</text>
        <text x="#{(label_width + 15 + value_width / 2 + 7.5) * 10}" y="175" transform="scale(.1)" fill="#fff" textLength="#{value_width * 10}">#{escape_xml(value)}</text>
      </g>
    </svg>
    """
  end

  # Estimate text width based on character count (approximate)
  defp estimate_text_width(text) do
    # Average character width is about 6 pixels for 11px font
    String.length(text) * 6 + 4
  end

  defp escape_xml(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
