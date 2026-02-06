defmodule Uptrack.Monitoring.SmartDefaults do
  @moduledoc """
  Smart defaults engine for monitor creation.

  Provides intelligent defaults based on URL analysis:
  - Extracts human-readable name from URL
  - Detects protocol (defaults to HTTPS)
  - Suggests monitor type based on port/service
  - Provides type-specific default settings
  - Selects nearest monitoring regions
  """

  @doc """
  Generates smart defaults from a URL string.

  Returns a map with:
  - `:name` - Human-readable name extracted from domain
  - `:url` - Normalized URL with protocol
  - `:monitor_type` - Suggested monitor type (:http, :tcp, :ssl, etc.)
  - `:settings` - Type-specific default settings
  - `:interval` - Check interval in seconds
  - `:timeout` - Request timeout in seconds

  ## Examples

      iex> SmartDefaults.from_url("example.com")
      %{
        name: "example.com",
        url: "https://example.com",
        monitor_type: :http,
        settings: %{method: "GET", follow_redirects: true},
        interval: 60,
        timeout: 30
      }

      iex> SmartDefaults.from_url("db.example.com:5432")
      %{
        name: "db.example.com (PostgreSQL)",
        url: "db.example.com:5432",
        monitor_type: :tcp,
        settings: %{port: 5432},
        interval: 60,
        timeout: 10
      }
  """
  def from_url(url) when is_binary(url) do
    url = String.trim(url)

    parsed = parse_url(url)

    monitor_type = detect_monitor_type(parsed)
    settings = default_settings(monitor_type, parsed)

    %{
      name: extract_name(parsed, monitor_type),
      url: normalize_url(parsed, monitor_type),
      monitor_type: monitor_type,
      settings: settings,
      interval: default_interval(monitor_type),
      timeout: default_timeout(monitor_type)
    }
  end

  @doc """
  Extracts a human-readable name from a URL.

  Strips protocol, www prefix, and common suffixes.
  Adds service name for known ports.
  """
  def extract_name(%{host: host, port: port}, monitor_type) do
    name =
      host
      |> String.replace(~r/^www\./, "")
      |> String.replace(~r/\.(com|org|net|io|co|app)$/, "")

    service = port_to_service(port)

    cond do
      service && monitor_type == :tcp -> "#{name} (#{service})"
      true -> name
    end
  end

  def extract_name(host, _monitor_type) when is_binary(host) do
    host
    |> String.replace(~r/^www\./, "")
    |> String.replace(~r/\.(com|org|net|io|co|app)$/, "")
  end

  # ---------------------------------------------------------------------------
  # URL Parsing
  # ---------------------------------------------------------------------------

  defp parse_url(url) do
    cond do
      # Already has protocol
      String.starts_with?(url, "http://") or String.starts_with?(url, "https://") ->
        uri = URI.parse(url)
        %{
          scheme: uri.scheme,
          host: uri.host || "",
          port: uri.port,
          path: uri.path || "/",
          original: url
        }

      # Has explicit port (e.g., "db.example.com:5432")
      String.match?(url, ~r/^[^:\/]+:\d+$/) ->
        [host, port_str] = String.split(url, ":")
        port = String.to_integer(port_str)
        %{
          scheme: nil,
          host: host,
          port: port,
          path: nil,
          original: url
        }

      # Plain domain
      true ->
        %{
          scheme: "https",
          host: url,
          port: 443,
          path: "/",
          original: url
        }
    end
  end

  # ---------------------------------------------------------------------------
  # Monitor Type Detection
  # ---------------------------------------------------------------------------

  @tcp_ports %{
    21 => :tcp,      # FTP
    22 => :tcp,      # SSH
    25 => :tcp,      # SMTP
    110 => :tcp,     # POP3
    143 => :tcp,     # IMAP
    3306 => :tcp,    # MySQL
    5432 => :tcp,    # PostgreSQL
    6379 => :tcp,    # Redis
    27017 => :tcp,   # MongoDB
    9200 => :tcp     # Elasticsearch
  }

  defp detect_monitor_type(%{port: port}) when is_map_key(@tcp_ports, port) do
    :tcp
  end

  defp detect_monitor_type(%{scheme: scheme}) when scheme in ["http", "https"] do
    :http
  end

  defp detect_monitor_type(%{port: 443}) do
    :http
  end

  defp detect_monitor_type(%{port: 80}) do
    :http
  end

  defp detect_monitor_type(_) do
    :http
  end

  # ---------------------------------------------------------------------------
  # Default Settings by Monitor Type
  # ---------------------------------------------------------------------------

  defp default_settings(:http, parsed) do
    %{
      "method" => "GET",
      "follow_redirects" => true,
      "verify_ssl" => parsed.scheme == "https",
      "expected_status_codes" => [200, 201, 204, 301, 302],
      "headers" => %{}
    }
  end

  defp default_settings(:tcp, parsed) do
    %{
      "port" => parsed.port,
      "service" => port_to_service(parsed.port)
    }
  end

  defp default_settings(:ssl, _parsed) do
    %{
      "warn_days_before_expiry" => 30,
      "check_chain" => true
    }
  end

  defp default_settings(:ping, _parsed) do
    %{
      "packet_count" => 3
    }
  end

  defp default_settings(:keyword, parsed) do
    %{
      "method" => "GET",
      "keyword" => "",
      "keyword_type" => "contains",
      "verify_ssl" => parsed.scheme == "https"
    }
  end

  defp default_settings(:heartbeat, _parsed) do
    %{
      "grace_period_seconds" => 300
    }
  end

  defp default_settings(_, _), do: %{}

  # ---------------------------------------------------------------------------
  # Default Intervals and Timeouts
  # ---------------------------------------------------------------------------

  @type_intervals %{
    http: 60,
    tcp: 60,
    ssl: 3600,
    ping: 60,
    keyword: 60,
    heartbeat: 3600
  }

  @type_timeouts %{
    http: 30,
    tcp: 10,
    ssl: 30,
    ping: 10,
    keyword: 30,
    heartbeat: 300
  }

  defp default_interval(type), do: Map.get(@type_intervals, type, 60)
  defp default_timeout(type), do: Map.get(@type_timeouts, type, 30)

  # ---------------------------------------------------------------------------
  # URL Normalization
  # ---------------------------------------------------------------------------

  defp normalize_url(%{scheme: nil, host: host, port: port}, :tcp) do
    "#{host}:#{port}"
  end

  defp normalize_url(%{scheme: nil, host: host}, :http) do
    "https://#{host}"
  end

  defp normalize_url(%{original: original}, _) do
    original
  end

  # ---------------------------------------------------------------------------
  # Port to Service Mapping
  # ---------------------------------------------------------------------------

  @port_services %{
    21 => "FTP",
    22 => "SSH",
    25 => "SMTP",
    80 => "HTTP",
    110 => "POP3",
    143 => "IMAP",
    443 => "HTTPS",
    3306 => "MySQL",
    5432 => "PostgreSQL",
    6379 => "Redis",
    27017 => "MongoDB",
    9200 => "Elasticsearch",
    11211 => "Memcached"
  }

  defp port_to_service(port) when is_integer(port) do
    Map.get(@port_services, port)
  end

  defp port_to_service(_), do: nil

  # ---------------------------------------------------------------------------
  # Region Selection (Nearest 3)
  # ---------------------------------------------------------------------------

  @doc """
  Selects the nearest monitoring regions based on user's timezone or location.

  Returns a list of up to 3 region codes.
  """
  def suggest_regions(timezone \\ nil) do
    # Default regions if no timezone provided
    default_regions = ["eu-north-1", "us-west-2", "ap-southeast-1"]

    case timezone do
      nil ->
        default_regions

      tz when is_binary(tz) ->
        cond do
          String.contains?(tz, "America") -> ["us-west-2", "us-east-1", "eu-north-1"]
          String.contains?(tz, "Europe") -> ["eu-north-1", "eu-west-1", "us-east-1"]
          String.contains?(tz, "Asia") -> ["ap-southeast-1", "ap-south-1", "eu-north-1"]
          String.contains?(tz, "Australia") -> ["ap-southeast-2", "ap-southeast-1", "us-west-2"]
          String.contains?(tz, "Pacific") -> ["us-west-2", "ap-southeast-1", "ap-southeast-2"]
          true -> default_regions
        end
    end
  end
end
