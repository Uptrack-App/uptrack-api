defmodule UptrackWeb.SettingsLive do
  use UptrackWeb, :live_view

  alias Uptrack.Accounts
  alias Uptrack.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    %{current_user: user} = socket.assigns

    preferences = User.get_notification_preferences(user)
    changeset = User.notification_preferences_changeset(user, %{})

    socket =
      socket
      |> assign(:user, user)
      |> assign(:preferences, preferences)
      |> assign(:changeset, changeset)
      |> assign(:page_title, "Settings")
      |> assign(:active_tab, "notifications")
      |> assign(:profile_name, user.name)
      |> assign(:profile_saved, false)
      |> assign(:password_error, nil)
      |> assign(:password_saved, false)
      |> assign(:show_delete_modal, false)
      |> assign(:delete_error, nil)

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

  def handle_event("save_profile", %{"name" => name}, socket) do
    case Accounts.update_user(socket.assigns.user, %{name: name}) do
      {:ok, user} ->
        socket =
          socket
          |> assign(:user, user)
          |> assign(:profile_name, user.name)
          |> assign(:profile_saved, true)
          |> put_flash(:info, "Profile updated successfully")

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update profile")}
    end
  end

  def handle_event("change_password", params, socket) do
    current = params["current_password"]
    new_pass = params["new_password"]
    confirm = params["confirm_password"]

    cond do
      new_pass != confirm ->
        {:noreply, assign(socket, :password_error, "New passwords don't match")}

      String.length(new_pass) < 12 ->
        {:noreply, assign(socket, :password_error, "New password must be at least 12 characters")}

      true ->
        case Accounts.change_password(socket.assigns.user, current, new_pass) do
          {:ok, user} ->
            socket =
              socket
              |> assign(:user, user)
              |> assign(:password_error, nil)
              |> assign(:password_saved, true)
              |> put_flash(:info, "Password changed successfully")

            {:noreply, socket}

          {:error, :invalid_password} ->
            {:noreply, assign(socket, password_error: "Current password is incorrect", password_saved: false)}

          {:error, _changeset} ->
            {:noreply, assign(socket, password_error: "Failed to change password", password_saved: false)}
        end
    end
  end

  def handle_event("show_delete_modal", _params, socket) do
    {:noreply, assign(socket, show_delete_modal: true, delete_error: nil)}
  end

  def handle_event("hide_delete_modal", _params, socket) do
    {:noreply, assign(socket, show_delete_modal: false, delete_error: nil)}
  end

  def handle_event("delete_account", params, socket) do
    password = params["password"]

    case Accounts.delete_user_and_organization(socket.assigns.user, password) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Account deleted successfully")
         |> redirect(to: ~p"/")}

      {:error, :invalid_password} ->
        {:noreply, assign(socket, :delete_error, "Password is incorrect")}

      {:error, _} ->
        {:noreply, assign(socket, :delete_error, "Failed to delete account")}
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
    <div class="space-y-6">
      <!-- Profile Section -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h3 class="card-title text-lg mb-4">Profile</h3>

          <form phx-submit="save_profile" class="space-y-4">
            <div class="form-control">
              <label class="label">
                <span class="label-text">Name</span>
              </label>
              <input
                type="text"
                name="name"
                class="input input-bordered"
                value={@profile_name}
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
              <div class="label">
                <span class="label-text-alt text-base-content/60">
                  Contact support to change your email address
                </span>
              </div>
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

            <div class="card-actions justify-end">
              <button type="submit" class="btn btn-primary">Save Profile</button>
            </div>
          </form>
        </div>
      </div>

      <!-- Password Change (only for email/password users) -->
      <%= if is_nil(@user.provider) do %>
        <div class="card bg-base-100 shadow">
          <div class="card-body">
            <h3 class="card-title text-lg mb-4">Change Password</h3>

            <form phx-submit="change_password" class="space-y-4">
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Current Password</span>
                </label>
                <input
                  type="password"
                  name="current_password"
                  class="input input-bordered"
                  required
                  autocomplete="current-password"
                />
              </div>

              <div class="form-control">
                <label class="label">
                  <span class="label-text">New Password</span>
                </label>
                <input
                  type="password"
                  name="new_password"
                  class="input input-bordered"
                  required
                  minlength="12"
                  autocomplete="new-password"
                />
                <div class="label">
                  <span class="label-text-alt text-base-content/60">
                    Minimum 12 characters
                  </span>
                </div>
              </div>

              <div class="form-control">
                <label class="label">
                  <span class="label-text">Confirm New Password</span>
                </label>
                <input
                  type="password"
                  name="confirm_password"
                  class="input input-bordered"
                  required
                  minlength="12"
                  autocomplete="new-password"
                />
              </div>

              <%= if @password_error do %>
                <div class="alert alert-error">
                  <.icon name="hero-exclamation-circle" class="w-5 h-5" />
                  <span>{@password_error}</span>
                </div>
              <% end %>

              <%= if @password_saved do %>
                <div class="alert alert-success">
                  <.icon name="hero-check-circle" class="w-5 h-5" />
                  <span>Password changed successfully</span>
                </div>
              <% end %>

              <div class="card-actions justify-end">
                <button type="submit" class="btn btn-primary">Change Password</button>
              </div>
            </form>
          </div>
        </div>
      <% end %>

      <!-- Danger Zone -->
      <div class="card bg-base-100 shadow border border-error/30">
        <div class="card-body">
          <h3 class="card-title text-lg text-error mb-4">Danger Zone</h3>

          <div class="flex items-center justify-between p-4 rounded-lg border border-error/20">
            <div>
              <p class="font-medium">Delete Account</p>
              <p class="text-sm text-base-content/60">
                Permanently delete your account, organization, and all associated data.
                This action cannot be undone.
              </p>
            </div>
            <button
              phx-click="show_delete_modal"
              class="btn btn-error btn-outline"
            >
              Delete Account
            </button>
          </div>
        </div>
      </div>

      <!-- Delete Confirmation Modal -->
      <%= if @show_delete_modal do %>
        <div class="modal modal-open">
          <div class="modal-box">
            <h3 class="font-bold text-lg text-error">Delete Account</h3>
            <p class="py-4">
              This will permanently delete your account, your organization, and all monitors, alert channels,
              incidents, and status pages. This action <strong>cannot be undone</strong>.
            </p>

            <form phx-submit="delete_account">
              <%= if is_nil(@user.provider) do %>
                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text">Enter your password to confirm</span>
                  </label>
                  <input
                    type="password"
                    name="password"
                    class="input input-bordered"
                    required
                    autocomplete="current-password"
                  />
                </div>
              <% end %>

              <%= if @delete_error do %>
                <div class="alert alert-error mb-4">
                  <.icon name="hero-exclamation-circle" class="w-5 h-5" />
                  <span>{@delete_error}</span>
                </div>
              <% end %>

              <div class="modal-action">
                <button type="button" phx-click="hide_delete_modal" class="btn">Cancel</button>
                <button type="submit" class="btn btn-error">Delete My Account</button>
              </div>
            </form>
          </div>
          <div class="modal-backdrop" phx-click="hide_delete_modal"></div>
        </div>
      <% end %>
    </div>
    """
  end
end
