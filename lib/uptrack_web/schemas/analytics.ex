defmodule UptrackWeb.Schemas.Analytics do
  @moduledoc """
  OpenAPI schemas for analytics endpoints.
  """

  require OpenApiSpex
  alias OpenApiSpex.Schema

  defmodule DashboardStats do
    @moduledoc false
    OpenApiSpex.schema(%{
      title: "DashboardStats",
      description: "Dashboard statistics summary",
      type: :object,
      properties: %{
        total_monitors: %Schema{type: :integer, description: "Total number of monitors"},
        active_monitors: %Schema{type: :integer, description: "Number of active monitors"},
        ongoing_incidents: %Schema{type: :integer, description: "Current ongoing incidents"},
        recent_incidents: %Schema{type: :integer, description: "Incidents in the last 7 days"}
      },
      example: %{
        total_monitors: 12,
        active_monitors: 10,
        ongoing_incidents: 1,
        recent_incidents: 3
      }
    })
  end

  defmodule UptimeTrendPoint do
    @moduledoc false
    OpenApiSpex.schema(%{
      title: "UptimeTrendPoint",
      description: "Single data point in uptime trend",
      type: :object,
      properties: %{
        date: %Schema{type: :string, format: :date, description: "Date"},
        uptime: %Schema{type: :number, format: :float, description: "Uptime percentage"},
        total_checks: %Schema{type: :integer, description: "Total checks on this day"}
      }
    })
  end

  defmodule DashboardResponse do
    @moduledoc false
    OpenApiSpex.schema(%{
      title: "DashboardResponse",
      description: "Dashboard overview response",
      type: :object,
      required: [:stats, :overall_uptime, :period_days],
      properties: %{
        stats: DashboardStats,
        overall_uptime: %Schema{
          type: :number,
          format: :float,
          description: "Overall uptime percentage"
        },
        uptime_trend: %Schema{
          type: :array,
          items: UptimeTrendPoint,
          description: "Daily uptime trend"
        },
        period_days: %Schema{type: :integer, description: "Period in days"}
      }
    })
  end

  defmodule ResponseTimePoint do
    @moduledoc false
    OpenApiSpex.schema(%{
      title: "ResponseTimePoint",
      description: "Response time data point",
      type: :object,
      properties: %{
        date: %Schema{type: :string, format: :date},
        avg: %Schema{type: :number, description: "Average response time (ms)"},
        min: %Schema{type: :integer, description: "Minimum response time (ms)"},
        max: %Schema{type: :integer, description: "Maximum response time (ms)"},
        total_checks: %Schema{type: :integer, description: "Number of checks"}
      }
    })
  end

  defmodule IncidentStats do
    @moduledoc false
    OpenApiSpex.schema(%{
      title: "IncidentStats",
      description: "Incident statistics",
      type: :object,
      properties: %{
        total_incidents: %Schema{type: :integer, description: "Total incidents"},
        ongoing_incidents: %Schema{type: :integer, description: "Currently ongoing"},
        resolved_incidents: %Schema{type: :integer, description: "Resolved incidents"},
        mttr_minutes: %Schema{
          type: :number,
          description: "Mean Time To Recovery in minutes"
        }
      },
      example: %{
        total_incidents: 5,
        ongoing_incidents: 0,
        resolved_incidents: 5,
        mttr_minutes: 12.5
      }
    })
  end

  defmodule MonitorAnalyticsResponse do
    @moduledoc false
    OpenApiSpex.schema(%{
      title: "MonitorAnalyticsResponse",
      description: "Detailed analytics for a single monitor",
      type: :object,
      required: [:monitor_id, :period_days],
      properties: %{
        monitor_id: %Schema{type: :integer, description: "Monitor ID"},
        period_days: %Schema{type: :integer, description: "Analysis period in days"},
        uptime_chart: %Schema{
          type: :array,
          items: UptimeTrendPoint,
          description: "Daily uptime data for charts"
        },
        response_times: %Schema{
          type: :array,
          items: ResponseTimePoint,
          description: "Daily response time trends"
        },
        incident_stats: IncidentStats
      }
    })
  end

  defmodule IncidentFrequencyPoint do
    @moduledoc false
    OpenApiSpex.schema(%{
      title: "IncidentFrequencyPoint",
      description: "Daily incident count",
      type: :object,
      properties: %{
        date: %Schema{type: :string, format: :date},
        count: %Schema{type: :integer, description: "Number of incidents"}
      }
    })
  end

  defmodule TopOffender do
    @moduledoc false
    OpenApiSpex.schema(%{
      title: "TopOffender",
      description: "Monitor with most incidents",
      type: :object,
      properties: %{
        monitor_id: %Schema{type: :integer},
        monitor_name: %Schema{type: :string},
        incident_count: %Schema{type: :integer, description: "Number of incidents"},
        total_downtime_seconds: %Schema{type: :integer, description: "Total downtime in seconds"}
      }
    })
  end

  defmodule OrganizationTrendsResponse do
    @moduledoc false
    OpenApiSpex.schema(%{
      title: "OrganizationTrendsResponse",
      description: "Organization-wide analytics trends",
      type: :object,
      required: [:period_days, :overall_uptime],
      properties: %{
        period_days: %Schema{type: :integer, description: "Analysis period in days"},
        overall_uptime: %Schema{type: :number, description: "Overall uptime percentage"},
        uptime_trends: %Schema{
          type: :array,
          items: UptimeTrendPoint,
          description: "Daily uptime trends"
        },
        incident_frequency: %Schema{
          type: :array,
          items: IncidentFrequencyPoint,
          description: "Daily incident counts"
        },
        top_offenders: %Schema{
          type: :array,
          items: TopOffender,
          description: "Monitors with most incidents"
        }
      }
    })
  end
end
