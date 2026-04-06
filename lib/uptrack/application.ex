defmodule Uptrack.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        UptrackWeb.Telemetry,
        # Database repos - AppRepo handles migrations, ObanRepo has separate pool
        Uptrack.AppRepo,
        Uptrack.ObanRepo,
        {DNSCluster, query: Application.get_env(:uptrack, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Uptrack.PubSub},
        # In-app cache for expensive queries
        {Uptrack.Cache, []},
        # Metrics write batcher (flushes to VictoriaMetrics every 1s)
        {Uptrack.Metrics.Batcher, []},
        # Oban job processing
        {Oban, Application.fetch_env!(:uptrack, Oban)},
        # Finch HTTP pool for monitoring checks (connection reuse)
        {Finch, name: Uptrack.Finch, pools: %{
          default: [size: 200, count: 4, protocols: [:http1]]
        }},
        # Task supervisor for monitoring checks
        {Task.Supervisor, name: Uptrack.TaskSupervisor},
        # pg scopes for multi-region consensus and config sync to workers
        %{id: :monitor_checks_pg, start: {:pg, :start_link, [:monitor_checks]}},
        %{id: :monitor_config_pg, start: {:pg, :start_link, [:monitor_config]}},
        # Registry for monitor process lookup
        Uptrack.Monitoring.MonitorRegistry,
        # DynamicSupervisor for per-monitor GenServer processes
        Uptrack.Monitoring.MonitorSupervisor,
        # OAuth state storage for Slack/Discord integrations
        Uptrack.Integrations.OAuthState,
        # Start to serve requests, typically the last entry
        UptrackWeb.Endpoint
      ] ++ idle_prevention_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Uptrack.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Boot loader: start all active monitor processes after supervision tree is ready
    if Application.get_env(:uptrack, :start_monitor_processes, true) do
      Task.start(fn ->
        # Small delay to ensure everything is initialized
        Process.sleep(2_000)
        Uptrack.Monitoring.MonitorSupervisor.start_all_active()
      end)
    end

    result
  end

  # Only run idle prevention on Oracle Cloud instances to prevent reclamation
  defp idle_prevention_children do
    if System.get_env("NODE_PROVIDER") == "oracle" do
      [Uptrack.Health.IdlePrevention]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    UptrackWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
