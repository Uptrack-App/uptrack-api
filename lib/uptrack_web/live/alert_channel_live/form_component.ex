defmodule UptrackWeb.AlertChannelLive.FormComponent do
  use UptrackWeb, :live_component

  alias Uptrack.Alerting

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.header>
        {@title}
        <:subtitle>Configure how you want to receive notifications</:subtitle>
      </.header>

      <form
        for={@form}
        id="alert-channel-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
        <.input
          field={@form[:name]}
          type="text"
          label="Channel Name"
          placeholder="e.g., My Email Alerts"
          required
        />

        <.input
          field={@form[:type]}
          type="select"
          label="Alert Type"
          options={[
            {"Email", "email"},
            {"Slack", "slack"},
            {"Webhook", "webhook"}
          ]}
          required
        />
        
    <!-- Email Configuration -->
        <%= if @selected_type == "email" do %>
          <div class="bg-blue-50 border border-blue-200 rounded-lg p-4">
            <h4 class="font-medium text-blue-900 mb-2">Email Configuration</h4>
            <.input
              field={@form[:email]}
              type="email"
              label="Email Address"
              placeholder="alerts@example.com"
              required
            />
            <p class="text-sm text-blue-700 mt-2">
              You'll receive incident notifications and resolution alerts at this email address.
            </p>
          </div>
        <% end %>
        
    <!-- Slack Configuration -->
        <%= if @selected_type == "slack" do %>
          <div class="bg-green-50 border border-green-200 rounded-lg p-4">
            <h4 class="font-medium text-green-900 mb-2">Slack Configuration</h4>
            <.input
              field={@form[:webhook_url]}
              type="url"
              label="Slack Webhook URL"
              placeholder="https://hooks.slack.com/services/..."
              required
            />
            <div class="mt-3 p-3 bg-green-100 rounded text-sm text-green-800">
              <strong>Setup Instructions:</strong>
              <ol class="list-decimal list-inside mt-1 space-y-1">
                <li>Go to your Slack workspace settings</li>
                <li>Create a new incoming webhook</li>
                <li>Choose the channel where you want alerts</li>
                <li>Copy the webhook URL and paste it above</li>
              </ol>
            </div>
          </div>
        <% end %>
        
    <!-- Webhook Configuration -->
        <%= if @selected_type == "webhook" do %>
          <div class="bg-purple-50 border border-purple-200 rounded-lg p-4">
            <h4 class="font-medium text-purple-900 mb-2">Webhook Configuration</h4>
            <.input
              field={@form[:webhook_url]}
              type="url"
              label="Webhook URL"
              placeholder="https://your-service.com/webhooks/uptrack"
              required
            />
            <div class="mt-3 p-3 bg-purple-100 rounded text-sm text-purple-800">
              <strong>Webhook Format:</strong>
              JSON POST requests will be sent with incident details including monitor info, timestamps, and event type.
            </div>
          </div>
        <% end %>

        <.input
          field={@form[:is_active]}
          type="checkbox"
          label="Active"
          checked={@form[:is_active].value}
        />

        <div class="flex justify-end gap-2">
          <.link patch={@patch} class="btn btn-ghost">Cancel</.link>
          <.button phx-disable-with="Saving...">Save Alert Channel</.button>
        </div>
      </form>
    </div>
    """
  end

  @impl true
  def update(%{alert_channel: alert_channel} = assigns, socket) do
    changeset = Alerting.change_alert_channel(alert_channel)

    # Determine selected type and extract config values
    selected_type = alert_channel.type || "email"
    config = alert_channel.config || %{}

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:selected_type, selected_type)
     |> assign_form(changeset)
     |> assign_config_fields(config)}
  end

  @impl true
  def handle_event("validate", %{"alert_channel" => alert_channel_params}, socket) do
    # Extract config parameters based on type
    {alert_channel_params, config} = extract_config_params(alert_channel_params)
    alert_channel_params = Map.put(alert_channel_params, "config", config)

    changeset =
      socket.assigns.alert_channel
      |> Alerting.change_alert_channel(alert_channel_params)
      |> Map.put(:action, :validate)

    selected_type = Map.get(alert_channel_params, "type", "email")

    {:noreply,
     socket
     |> assign(:selected_type, selected_type)
     |> assign_form(changeset)}
  end

  def handle_event("save", %{"alert_channel" => alert_channel_params}, socket) do
    save_alert_channel(socket, socket.assigns.action, alert_channel_params)
  end

  defp save_alert_channel(socket, :edit, alert_channel_params) do
    # Extract config parameters based on type
    {alert_channel_params, config} = extract_config_params(alert_channel_params)
    alert_channel_params = Map.put(alert_channel_params, "config", config)

    case Alerting.update_alert_channel(socket.assigns.alert_channel, alert_channel_params) do
      {:ok, alert_channel} ->
        notify_parent({:saved, alert_channel})

        {:noreply,
         socket
         |> put_flash(:info, "Alert channel updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_alert_channel(socket, :new, alert_channel_params) do
    # Add user_id to params
    # TODO: Get from session
    alert_channel_params = Map.put(alert_channel_params, "user_id", 1)

    # Extract config parameters based on type
    {alert_channel_params, config} = extract_config_params(alert_channel_params)
    alert_channel_params = Map.put(alert_channel_params, "config", config)

    case Alerting.create_alert_channel(alert_channel_params) do
      {:ok, alert_channel} ->
        notify_parent({:saved, alert_channel})

        {:noreply,
         socket
         |> put_flash(:info, "Alert channel created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp assign_config_fields(socket, config) do
    socket
    |> assign(:email, Map.get(config, "email", ""))
    |> assign(:webhook_url, Map.get(config, "webhook_url", ""))
  end

  defp extract_config_params(params) do
    type = Map.get(params, "type", "email")

    config =
      case type do
        "email" ->
          %{"email" => Map.get(params, "email", "")}

        "slack" ->
          %{"webhook_url" => Map.get(params, "webhook_url", "")}

        "webhook" ->
          %{"url" => Map.get(params, "webhook_url", "")}

        _ ->
          %{}
      end

    # Remove config fields from main params
    clean_params = Map.drop(params, ["email", "webhook_url"])

    {clean_params, config}
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
