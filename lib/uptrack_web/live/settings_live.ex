defmodule UptrackWeb.SettingsLive do
  use UptrackWeb, :live_view

  alias Uptrack.Accounts
  alias Uptrack.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    # TODO: Get user from session/auth
    # Placeholder - will be replaced with actual auth
    user_id = 1
    user = Accounts.get_user!(user_id)

    preferences = User.get_notification_preferences(user)
    changeset = User.notification_preferences_changeset(user, %{})

    socket =
      socket
      |> assign(:user, user)
      |> assign(:preferences, preferences)
      |> assign(:changeset, changeset)
      |> assign(:page_title, "Settings")
      |> assign(:active_tab, "notifications")

    {:ok, socket}
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      socket.assigns.user
      |> User.notification_preferences_changeset(user_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.update_user_preferences(socket.assigns.user, user_params) do
      {:ok, user} ->
        preferences = User.get_notification_preferences(user)
        changeset = User.notification_preferences_changeset(user, %{})

        socket =
          socket
          |> assign(:user, user)
          |> assign(:preferences, preferences)
          |> assign(:changeset, changeset)
          |> put_flash(:info, "Notification preferences updated successfully")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header -->
      <div class="flex justify-between items-center">
        <div>
          <h1 class="text-3xl font-bold">Settings</h1>
          <p class="text-base-content/70">Manage your account and notification preferences</p>
        </div>
      </div>
      
    <!-- Navigation Tabs -->
      <div class="tabs tabs-bordered">
        <.link navigate={~p"/dashboard"} class="tab">
          <.icon name="hero-chart-bar" class="w-4 h-4" /> Dashboard
        </.link>
        <.link navigate={~p"/dashboard/alerts"} class="tab">
          <.icon name="hero-bell" class="w-4 h-4" /> Alert Channels
        </.link>
        <.link navigate={~p"/dashboard/status-pages"} class="tab">
          <.icon name="hero-globe-alt" class="w-4 h-4" /> Status Pages
        </.link>
        <.link navigate={~p"/dashboard/incidents"} class="tab">
          <.icon name="hero-exclamation-triangle" class="w-4 h-4" /> Incidents
        </.link>
        <.link navigate={~p"/dashboard/settings"} class="tab tab-active">
          <.icon name="hero-cog-6-tooth" class="w-4 h-4" /> Settings
        </.link>
      </div>
      
    <!-- Settings Tabs -->
      <div class="tabs tabs-boxed">
        <button
          phx-click="change_tab"
          phx-value-tab="notifications"
          class={["tab", if(@active_tab == "notifications", do: "tab-active", else: "")]}
        >
          <.icon name="hero-bell" class="w-4 h-4" /> Notifications
        </button>
        <button
          phx-click="change_tab"
          phx-value-tab="account"
          class={["tab", if(@active_tab == "account", do: "tab-active", else: "")]}
        >
          <.icon name="hero-user" class="w-4 h-4" /> Account
        </button>
      </div>
      
    <!-- Content -->
      <%= if @active_tab == "notifications" do %>
        <.render_notifications_settings assigns={assigns} />
      <% else %>
        <.render_account_settings assigns={assigns} />
      <% end %>
    </div>
    """
  end

  defp render_notifications_settings(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <!-- Email Notifications -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h3 class="card-title text-lg mb-4">Email Notifications</h3>

          <form
            phx-change="validate"
            phx-submit="save"
          >
            <div class="space-y-4">
              <!-- Master Email Toggle -->
              <div class="form-control">
                <label class="label cursor-pointer">
                  <span class="label-text font-medium">Enable Email Notifications</span>
                  <input
                    type="checkbox"
                    name="user[notification_preferences][email_enabled]"
                    class="checkbox checkbox-primary"
                    checked={@preferences["email_enabled"]}
                  />
                </label>
                <div class="label">
                  <span class="label-text-alt text-base-content/60">
                    Turn off to stop all email notifications
                  </span>
                </div>
              </div>

              <div class="divider"></div>
              
    <!-- Incident Notifications -->
              <div class="space-y-3">
                <h4 class="font-medium text-base">Incident Notifications</h4>

                <div class="form-control">
                  <label class="label cursor-pointer">
                    <span class="label-text">Incident Started</span>
                    <input
                      type="checkbox"
                      name="user[notification_preferences][email_on_incident_started]"
                      class="checkbox checkbox-sm"
                      checked={@preferences["email_on_incident_started"]}
                    />
                  </label>
                </div>

                <div class="form-control">
                  <label class="label cursor-pointer">
                    <span class="label-text">Incident Resolved</span>
                    <input
                      type="checkbox"
                      name="user[notification_preferences][email_on_incident_resolved]"
                      class="checkbox checkbox-sm"
                      checked={@preferences["email_on_incident_resolved"]}
                    />
                  </label>
                </div>
              </div>

              <div class="divider"></div>
              
    <!-- Monitor Notifications -->
              <div class="space-y-3">
                <h4 class="font-medium text-base">Monitor Notifications</h4>

                <div class="form-control">
                  <label class="label cursor-pointer">
                    <span class="label-text">Monitor Down</span>
                    <input
                      type="checkbox"
                      name="user[notification_preferences][email_on_monitor_down]"
                      class="checkbox checkbox-sm"
                      checked={@preferences["email_on_monitor_down"]}
                    />
                  </label>
                </div>

                <div class="form-control">
                  <label class="label cursor-pointer">
                    <span class="label-text">Monitor Up</span>
                    <input
                      type="checkbox"
                      name="user[notification_preferences][email_on_monitor_up]"
                      class="checkbox checkbox-sm"
                      checked={@preferences["email_on_monitor_up"]}
                    />
                  </label>
                </div>
              </div>

              <div class="card-actions justify-end mt-6">
                <button type="submit" class="btn btn-primary">
                  Save Preferences
                </button>
              </div>
            </div>
          </form>
        </div>
      </div>
      
    <!-- Notification Timing -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h3 class="card-title text-lg mb-4">Notification Timing</h3>

          <form
            phx-change="validate"
            phx-submit="save"
          >
            <div class="space-y-4">
              <!-- Notification Frequency -->
              <div class="form-control w-full">
                <label class="label">
                  <span class="label-text font-medium">Notification Frequency</span>
                </label>
                <select
                  name="user[notification_preferences][notification_frequency]"
                  class="select select-bordered w-full"
                >
                  <option
                    value="immediate"
                    selected={@preferences["notification_frequency"] == "immediate"}
                  >
                    Immediate
                  </option>
                  <option value="hourly" selected={@preferences["notification_frequency"] == "hourly"}>
                    Hourly Digest
                  </option>
                  <option value="daily" selected={@preferences["notification_frequency"] == "daily"}>
                    Daily Digest
                  </option>
                </select>
                <div class="label">
                  <span class="label-text-alt text-base-content/60">
                    How often to send notifications
                  </span>
                </div>
              </div>

              <div class="divider"></div>
              
    <!-- Quiet Hours -->
              <div class="space-y-3">
                <div class="form-control">
                  <label class="label cursor-pointer">
                    <span class="label-text font-medium">Enable Quiet Hours</span>
                    <input
                      type="checkbox"
                      name="user[notification_preferences][quiet_hours_enabled]"
                      class="checkbox checkbox-primary"
                      checked={@preferences["quiet_hours_enabled"]}
                    />
                  </label>
                  <div class="label">
                    <span class="label-text-alt text-base-content/60">
                      Suppress non-critical notifications during specified hours
                    </span>
                  </div>
                </div>

                <%= if @preferences["quiet_hours_enabled"] do %>
                  <div class="grid grid-cols-2 gap-4">
                    <div class="form-control">
                      <label class="label">
                        <span class="label-text">Start Time</span>
                      </label>
                      <input
                        type="time"
                        name="user[notification_preferences][quiet_hours_start]"
                        class="input input-bordered"
                        value={@preferences["quiet_hours_start"]}
                      />
                    </div>

                    <div class="form-control">
                      <label class="label">
                        <span class="label-text">End Time</span>
                      </label>
                      <input
                        type="time"
                        name="user[notification_preferences][quiet_hours_end]"
                        class="input input-bordered"
                        value={@preferences["quiet_hours_end"]}
                      />
                    </div>
                  </div>
                <% end %>
              </div>

              <div class="divider"></div>
              
    <!-- Summary Reports -->
              <div class="space-y-3">
                <h4 class="font-medium text-base">Summary Reports</h4>

                <div class="form-control">
                  <label class="label cursor-pointer">
                    <span class="label-text">Weekly Summary</span>
                    <input
                      type="checkbox"
                      name="user[notification_preferences][weekly_summary_enabled]"
                      class="checkbox checkbox-sm"
                      checked={@preferences["weekly_summary_enabled"]}
                    />
                  </label>
                </div>

                <div class="form-control">
                  <label class="label cursor-pointer">
                    <span class="label-text">Monthly Summary</span>
                    <input
                      type="checkbox"
                      name="user[notification_preferences][monthly_summary_enabled]"
                      class="checkbox checkbox-sm"
                      checked={@preferences["monthly_summary_enabled"]}
                    />
                  </label>
                </div>
              </div>

              <div class="card-actions justify-end mt-6">
                <button type="submit" class="btn btn-primary">
                  Save Preferences
                </button>
              </div>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  defp render_account_settings(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow">
      <div class="card-body">
        <h3 class="card-title text-lg mb-4">Account Information</h3>

        <div class="space-y-4">
          <div class="form-control">
            <label class="label">
              <span class="label-text">Name</span>
            </label>
            <input
              type="text"
              class="input input-bordered"
              value={@user.name}
              readonly
            />
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text">Email</span>
            </label>
            <input
              type="email"
              class="input input-bordered"
              value={@user.email}
              readonly
            />
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text">Account Type</span>
            </label>
            <input
              type="text"
              class="input input-bordered"
              value={if @user.provider, do: String.capitalize(@user.provider), else: "Email"}
              readonly
            />
          </div>

          <div class="alert alert-info">
            <.icon name="hero-information-circle" class="w-5 h-5" />
            <span>Account management features coming soon!</span>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
