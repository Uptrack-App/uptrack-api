defmodule UptrackWeb.StatusLive do
  use UptrackWeb, :live_view

  alias Uptrack.Monitoring
  alias Uptrack.Monitoring.StatusPage
  alias Uptrack.StatusPageTranslations, as: T

  @impl true
  def mount(%{"slug" => slug} = params, session, socket) do
    try do
      status_page = Monitoring.get_status_page_with_status!(slug)

      # Detect language: URL param > status page default > Accept-Language header > "en"
      lang = detect_language(params, status_page, socket)

      # Check if password is required and if already authenticated
      session_key = "status_page_auth_#{status_page.id}"
      authenticated = Map.get(session, session_key, false)

      if StatusPage.requires_password?(status_page) && !authenticated do
        # Show password form
        socket =
          socket
          |> assign(:status_page, status_page)
          |> assign(:lang, lang)
          |> assign(:password_required, true)
          |> assign(:password_error, nil)
          |> assign(:page_title, "#{status_page.name} - #{T.t(:enter_password, lang)}")

        {:ok, socket}
      else
        # Show status page content
        {:ok, mount_status_page(socket, status_page, lang)}
      end
    rescue
      Ecto.NoResultsError ->
        {:ok, redirect(socket, to: ~p"/")}
    end
  end

  defp detect_language(params, status_page, socket) do
    cond do
      # URL param takes precedence
      params["lang"] ->
        T.normalize_language(params["lang"])

      # Then status page default
      status_page.default_language && status_page.default_language != "en" ->
        T.normalize_language(status_page.default_language)

      # Then Accept-Language header
      true ->
        accept_language = get_connect_params(socket)["accept_language"] || ""
        T.detect_language(accept_language)
    end
  end

  defp mount_status_page(socket, status_page, lang) do
    # Calculate overall status
    overall_status = calculate_overall_status(status_page.monitors)

    # Get recent incidents for this status page's monitors
    monitor_ids = Enum.map(status_page.monitors, & &1.id)

    recent_incidents =
      if Enum.any?(monitor_ids) do
        # Use user_id 1 for now
        Monitoring.list_recent_incidents(1, 10)
        |> Enum.filter(&(&1.monitor_id in monitor_ids))
      else
        []
      end

    socket
    |> assign(:status_page, status_page)
    |> assign(:lang, lang)
    |> assign(:password_required, false)
    |> assign(:overall_status, overall_status)
    |> assign(:recent_incidents, recent_incidents)
    |> assign(:page_title, status_page.name)
    |> assign(:subscribe_email, "")
    |> assign(:subscribe_status, nil)
    |> assign(:subscribe_message, nil)
  end

  @impl true
  def handle_event("verify_password", %{"password" => password}, socket) do
    status_page = socket.assigns.status_page
    lang = socket.assigns.lang

    if StatusPage.verify_password(status_page, password) do
      # Password correct - reload with full content
      # Note: In production, you'd set a session cookie here
      {:noreply, mount_status_page(socket, status_page, lang)}
    else
      {:noreply, assign(socket, :password_error, T.t(:incorrect_password, lang))}
    end
  end

  @impl true
  def handle_event("subscribe", %{"email" => email}, socket) do
    status_page = socket.assigns.status_page
    lang = socket.assigns.lang

    case Monitoring.subscribe_to_status_page(status_page.id, email) do
      {:ok, subscriber} ->
        # Send verification email
        send_verification_email(subscriber, status_page)

        socket =
          socket
          |> assign(:subscribe_status, :success)
          |> assign(:subscribe_message, T.t(:check_email_verify, lang))
          |> assign(:subscribe_email, "")

        {:noreply, socket}

      {:error, changeset} ->
        message =
          case changeset.errors[:email] do
            {"already subscribed to this status page", _} ->
              T.t(:already_subscribed, lang)

            {msg, _} ->
              "Invalid email: #{msg}"

            nil ->
              "Could not subscribe. Please try again."
          end

        socket =
          socket
          |> assign(:subscribe_status, :error)
          |> assign(:subscribe_message, message)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("change_language", %{"lang" => lang}, socket) do
    lang = T.normalize_language(lang)
    {:noreply, assign(socket, :lang, lang)}
  end

  defp send_verification_email(subscriber, status_page) do
    alias Uptrack.Emails.SubscriberEmail
    alias Uptrack.Mailer

    subscriber
    |> SubscriberEmail.verification_email(status_page)
    |> Mailer.deliver()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="container mx-auto px-4 py-8 max-w-4xl">
        <%= if @password_required do %>
          <!-- Password Protection -->
          <div class="flex items-center justify-center min-h-[60vh]">
            <div class="card bg-base-100 shadow-lg max-w-md w-full">
              <div class="card-body text-center">
                <%= if @status_page.logo_url do %>
                  <img src={@status_page.logo_url} alt={@status_page.name} class="h-12 mx-auto mb-4" />
                <% end %>
                <h1 class="text-2xl font-bold mb-2">{@status_page.name}</h1>
                <p class="text-base-content/70 mb-6">
                  {t(:password_protected, @lang)}
                </p>

                <form phx-submit="verify_password" class="space-y-4">
                  <div class="form-control">
                    <input
                      type="password"
                      name="password"
                      placeholder={t(:enter_password, @lang)}
                      class={"input input-bordered w-full #{if @password_error, do: "input-error"}"}
                      required
                    />
                    <%= if @password_error do %>
                      <label class="label">
                        <span class="label-text-alt text-error">{@password_error}</span>
                      </label>
                    <% end %>
                  </div>
                  <button type="submit" class="btn btn-primary w-full">
                    {t(:view_status, @lang)}
                  </button>
                </form>
              </div>
            </div>
          </div>
        <% else %>
          <!-- Language Selector -->
          <div class="flex justify-end mb-4">
            <.language_selector lang={@lang} />
          </div>

          <!-- Header -->
          <div class="text-center mb-8">
            <%= if @status_page.logo_url do %>
              <img src={@status_page.logo_url} alt={@status_page.name} class="h-16 mx-auto mb-4" />
            <% end %>
            <h1 class="text-4xl font-bold mb-2">{@status_page.name}</h1>
            <%= if @status_page.description do %>
              <p class="text-lg text-base-content/70">{@status_page.description}</p>
            <% end %>
          </div>

          <!-- Overall Status -->
          <div class="card bg-base-100 shadow-lg mb-8">
            <div class="card-body text-center">
              <div class="flex items-center justify-center gap-3 mb-2">
                <div class={["w-4 h-4 rounded-full", status_color(@overall_status)]}></div>
                <h2 class="text-2xl font-semibold">
                  {status_text(@overall_status, @lang)}
                </h2>
              </div>
              <p class="text-base-content/70">
                {status_description(@overall_status, length(@status_page.monitors), @lang)}
              </p>
            </div>
          </div>

          <!-- Services -->
          <%= if Enum.any?(@status_page.monitors) do %>
            <div class="card bg-base-100 shadow-lg mb-8">
              <div class="card-body">
                <h3 class="card-title text-xl mb-4">{t(:services, @lang)}</h3>
                <div class="space-y-3">
                  <%= for monitor <- @status_page.monitors do %>
                    <div class="flex items-center justify-between p-4 rounded-lg bg-base-200">
                      <div class="flex items-center gap-3">
                        <div class={["w-3 h-3 rounded-full", monitor_status_color(monitor)]}></div>
                        <div>
                          <h4 class="font-medium">
                            {display_name(monitor)}
                          </h4>
                          <p class="text-sm text-base-content/60">
                            {monitor.url}
                          </p>
                        </div>
                      </div>
                      <div class="text-right">
                        <div class={["badge", monitor_status_badge(monitor)]}>
                          {monitor_status_text(monitor, @lang)}
                        </div>
                        <%= if latest_check = get_latest_check(monitor) do %>
                          <p class="text-xs text-base-content/50 mt-1">
                            <%= if latest_check.response_time do %>
                              {latest_check.response_time}ms
                            <% end %>
                            · {time_ago(latest_check.checked_at)}
                          </p>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% else %>
            <div class="card bg-base-100 shadow-lg mb-8">
              <div class="card-body text-center">
                <h3 class="text-lg font-medium mb-2">{t(:no_services_configured, @lang)}</h3>
                <p class="text-base-content/70">
                  {t(:no_services_message, @lang)}
                </p>
              </div>
            </div>
          <% end %>

          <!-- Recent Incidents -->
          <%= if Enum.any?(@recent_incidents) do %>
            <div class="card bg-base-100 shadow-lg mb-8">
              <div class="card-body">
                <h3 class="card-title text-xl mb-4">{t(:recent_incidents, @lang)}</h3>
                <div class="space-y-4">
                  <%= for incident <- @recent_incidents do %>
                    <div class="border-l-4 border-primary pl-4 py-3">
                      <div class="flex items-center gap-2 mb-2">
                        <div class={["w-3 h-3 rounded-full", incident_status_color(incident.status)]}>
                        </div>
                        <h4 class="font-medium">{incident.monitor.name}</h4>
                        <div class={["badge badge-sm", incident_status_badge(incident.status)]}>
                          {incident_status_text(incident.status, @lang)}
                        </div>
                        <span class="text-sm text-base-content/60">
                          {format_date(incident.started_at)}
                        </span>
                      </div>

                      <%= if incident.cause do %>
                        <p class="text-base-content/80 mb-2">{incident.cause}</p>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>

          <!-- Subscribe Section -->
          <%= if @status_page.allow_subscriptions do %>
            <div class="card bg-base-100 shadow-lg mb-8">
              <div class="card-body">
                <h3 class="card-title text-xl mb-2">{t(:subscribe_to_updates, @lang)}</h3>
                <p class="text-base-content/70 mb-4">
                  {t(:subscribe_description, @lang)}
                </p>

                <%= if @subscribe_status == :success do %>
                  <div class="alert alert-success">
                    <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                    <span>{@subscribe_message}</span>
                  </div>
                <% else %>
                  <form phx-submit="subscribe" class="flex flex-col sm:flex-row gap-3">
                    <input
                      type="email"
                      name="email"
                      placeholder={t(:email_placeholder, @lang)}
                      value={@subscribe_email}
                      class={"input input-bordered flex-1 #{if @subscribe_status == :error, do: "input-error"}"}
                      required
                    />
                    <button type="submit" class="btn btn-primary">
                      {t(:subscribe_button, @lang)}
                    </button>
                  </form>
                  <%= if @subscribe_status == :error do %>
                    <p class="text-error text-sm mt-2">{@subscribe_message}</p>
                  <% end %>
                <% end %>
              </div>
            </div>
          <% end %>

          <!-- Footer -->
          <div class="text-center text-sm text-base-content/50">
            <p>{t(:last_updated, @lang)} {DateTime.utc_now() |> format_datetime()}</p>
            <%= if @status_page.theme_config["show_powered_by"] != false do %>
              <p class="mt-2">
                {t(:powered_by, @lang)} <a href="/" class="link">Uptrack</a>
              </p>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Language selector component
  defp language_selector(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <label tabindex="0" class="btn btn-ghost btn-sm gap-1">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 5h12M9 3v2m1.048 9.5A18.022 18.022 0 016.412 9m6.088 9h7M11 21l5-10 5 10M12.751 5C11.783 10.77 8.07 15.61 3 18.129" />
        </svg>
        {language_name(@lang)}
      </label>
      <ul tabindex="0" class="dropdown-content z-[1] menu p-2 shadow bg-base-100 rounded-box w-40">
        <%= for lang_code <- T.supported_languages() do %>
          <li>
            <button phx-click="change_language" phx-value-lang={lang_code} class={if lang_code == @lang, do: "active"}>
              {language_name(lang_code)}
            </button>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  defp language_name("en"), do: "English"
  defp language_name("de"), do: "Deutsch"
  defp language_name("fr"), do: "Francais"
  defp language_name("es"), do: "Espanol"
  defp language_name("pt"), do: "Portugues"
  defp language_name("ja"), do: "日本語"
  defp language_name("zh"), do: "中文"
  defp language_name(code), do: code

  # Translation helper
  defp t(key, lang), do: T.t(key, lang)

  # Helper functions

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

  defp status_color(:operational), do: "bg-success"
  defp status_color(:partial_outage), do: "bg-warning"
  defp status_color(:major_outage), do: "bg-error"
  defp status_color(_), do: "bg-base-content/30"

  defp status_text(:operational, lang), do: T.t(:all_systems_operational, lang)
  defp status_text(:partial_outage, lang), do: T.t(:partial_system_outage, lang)
  defp status_text(:major_outage, lang), do: T.t(:major_system_outage, lang)
  defp status_text(_, lang), do: T.t(:system_status_unknown, lang)

  defp status_description(:operational, count, lang) do
    T.t(:all_services_running, lang, %{count: count})
  end

  defp status_description(:partial_outage, count, lang) do
    T.t(:some_services_issues, lang, %{count: count})
  end

  defp status_description(:major_outage, count, lang) do
    T.t(:all_services_down, lang, %{count: count})
  end

  defp status_description(_, count, lang) do
    T.t(:unable_to_determine, lang, %{count: count})
  end

  defp monitor_status_color(monitor) do
    case get_latest_check(monitor) do
      nil ->
        "bg-base-content/30"

      check ->
        case check.status do
          "up" -> "bg-success"
          "down" -> "bg-error"
          _ -> "bg-warning"
        end
    end
  end

  defp monitor_status_badge(monitor) do
    case get_latest_check(monitor) do
      nil ->
        "badge-neutral"

      check ->
        case check.status do
          "up" -> "badge-success"
          "down" -> "badge-error"
          _ -> "badge-warning"
        end
    end
  end

  defp monitor_status_text(monitor, lang) do
    case get_latest_check(monitor) do
      nil ->
        T.t(:unknown, lang)

      check ->
        case check.status do
          "up" -> T.t(:operational, lang)
          "down" -> T.t(:down, lang)
          _ -> T.t(:issues, lang)
        end
    end
  end

  defp get_latest_check(monitor) do
    case monitor.monitor_checks do
      [check | _] -> check
      [] -> nil
    end
  end

  defp display_name(monitor) do
    monitor.name
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

  defp format_datetime(datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_string()
    |> String.replace("T", " ")
    |> String.replace("Z", " UTC")
  end

  defp format_date(datetime) do
    datetime
    |> DateTime.to_date()
    |> Date.to_string()
  end

  defp incident_status_color("ongoing"), do: "bg-error"
  defp incident_status_color("resolved"), do: "bg-success"
  defp incident_status_color(_), do: "bg-base-content/30"

  defp incident_status_badge("ongoing"), do: "badge-error"
  defp incident_status_badge("resolved"), do: "badge-success"
  defp incident_status_badge(_), do: "badge-neutral"

  defp incident_status_text("ongoing", lang), do: T.t(:ongoing, lang)
  defp incident_status_text("resolved", lang), do: T.t(:resolved, lang)
  defp incident_status_text(_, lang), do: T.t(:unknown, lang)
end
