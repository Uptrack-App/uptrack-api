defmodule UptrackWeb.MonitorLive.FormComponent do
  use UptrackWeb, :live_component

  alias Uptrack.Monitoring

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.header>
        {@title}
        <:subtitle>Configure your monitor settings</:subtitle>
      </.header>

      <form
        for={@form}
        id="monitor-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
        <.input field={@form[:name]} type="text" label="Monitor Name" required />
        <.input
          field={@form[:url]}
          type="url"
          label="URL to Monitor"
          placeholder="https://example.com"
          required
        />
        <.input field={@form[:description]} type="textarea" label="Description" />

        <.input
          field={@form[:monitor_type]}
          type="select"
          label="Monitor Type"
          options={Enum.map(Uptrack.Monitoring.Monitor.monitor_types(), &{String.upcase(&1), &1})}
          required
        />

        <div class="grid grid-cols-2 gap-4">
          <.input
            field={@form[:interval]}
            type="number"
            label="Check Interval (seconds)"
            min="60"
            required
          />
          <.input
            field={@form[:timeout]}
            type="number"
            label="Timeout (seconds)"
            min="5"
            max="300"
            required
          />
        </div>

        <.input
          field={@form[:status]}
          type="select"
          label="Status"
          options={Enum.map(Uptrack.Monitoring.Monitor.statuses(), &{String.upcase(&1), &1})}
          required
        />

        <div class="flex justify-end">
          <.button phx-disable-with="Saving...">Save Monitor</.button>
        </div>
      </form>
    </div>
    """
  end

  @impl true
  def update(%{monitor: monitor} = assigns, socket) do
    changeset = Monitoring.change_monitor(monitor)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"monitor" => monitor_params}, socket) do
    changeset =
      socket.assigns.monitor
      |> Monitoring.change_monitor(monitor_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"monitor" => monitor_params}, socket) do
    save_monitor(socket, socket.assigns.action, monitor_params)
  end

  defp save_monitor(socket, :edit_monitor, monitor_params) do
    case Monitoring.update_monitor(socket.assigns.monitor, monitor_params) do
      {:ok, monitor} ->
        notify_parent({:saved, monitor})

        {:noreply,
         socket
         |> put_flash(:info, "Monitor updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_monitor(socket, :new_monitor, monitor_params) do
    # Add organization_id and user_id to monitor params
    monitor_params =
      monitor_params
      |> Map.put("organization_id", socket.assigns.organization_id)
      |> Map.put("user_id", socket.assigns.user_id)

    case Monitoring.create_monitor(monitor_params) do
      {:ok, monitor} ->
        notify_parent({:saved, monitor})

        {:noreply,
         socket
         |> put_flash(:info, "Monitor created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
