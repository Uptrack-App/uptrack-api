defmodule UptrackWeb.StatusPageLive.FormComponent do
  use UptrackWeb, :live_component

  alias Uptrack.Monitoring

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.header>
        {@title}
        <:subtitle>Configure your public status page</:subtitle>
      </.header>

      <form
        for={@form}
        id="status-page-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <!-- Basic Information -->
        <div class="space-y-4">
          <h3 class="text-lg font-medium">Basic Information</h3>

          <.input
            field={@form[:name]}
            type="text"
            label="Status Page Name"
            placeholder="e.g., My Company Status"
            required
          />

          <.input
            field={@form[:slug]}
            type="text"
            label="URL Slug"
            placeholder="my-company"
            required
          />
          <p class="text-sm text-base-content/60 mt-1">
            Your status page will be available at: /status/<span class="font-mono"><%= @form[:slug].value || "your-slug" %></span>
          </p>

          <.input
            field={@form[:description]}
            type="textarea"
            label="Description"
            placeholder="Status page for our services"
            rows="3"
          />
        </div>
        
    <!-- Visibility Settings -->
        <div class="space-y-4">
          <h3 class="text-lg font-medium">Visibility</h3>

          <.input
            field={@form[:is_public]}
            type="checkbox"
            label="Make this status page public"
            checked={@form[:is_public].value}
          />
        </div>
        
    <!-- Branding -->
        <div class="space-y-4">
          <h3 class="text-lg font-medium">Branding</h3>

          <.input
            field={@form[:logo_url]}
            type="url"
            label="Logo URL"
            placeholder="https://example.com/logo.png"
          />

          <.input
            field={@form[:custom_domain]}
            type="text"
            label="Custom Domain"
            placeholder="status.example.com"
          />
          <p class="text-sm text-base-content/60 mt-1">
            Optional: Use your own domain instead of our subdomain
          </p>
        </div>
        
    <!-- Monitor Selection -->
        <%= if @action == :edit and @monitors do %>
          <div class="space-y-4">
            <h3 class="text-lg font-medium">Monitors to Display</h3>
            <p class="text-sm text-base-content/70">
              Select which monitors should be visible on this status page.
            </p>

            <div class="grid gap-3">
              <%= for monitor <- @monitors do %>
                <label class="flex items-center gap-3 p-3 bg-base-200 rounded-lg cursor-pointer hover:bg-base-300">
                  <input
                    type="checkbox"
                    class="checkbox checkbox-primary"
                    checked={monitor.id in @selected_monitor_ids}
                    phx-click="toggle_monitor"
                    phx-value-monitor-id={monitor.id}
                    phx-target={@myself}
                  />
                  <div class="flex-1">
                    <div class="font-medium">{monitor.name}</div>
                    <div class="text-sm text-base-content/60">{monitor.url}</div>
                  </div>
                  <div class={["badge badge-sm", monitor_status_badge(monitor)]}>
                    {monitor_status_text(monitor)}
                  </div>
                </label>
              <% end %>
            </div>
          </div>
        <% end %>

        <div class="flex justify-end gap-2">
          <.link patch={@patch} class="btn btn-ghost">Cancel</.link>
          <.button phx-disable-with="Saving...">Save Status Page</.button>
        </div>
      </form>
    </div>
    """
  end

  @impl true
  def update(%{status_page: status_page} = assigns, socket) do
    changeset = Monitoring.change_status_page(status_page, %{})

    # Get user monitors for selection
    monitors = Monitoring.list_monitors(assigns.user_id)

    # Get currently selected monitors if editing
    selected_monitor_ids =
      if status_page.id do
        status_page
        |> Monitoring.get_status_page_monitors()
        |> Enum.map(& &1.monitor_id)
      else
        []
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:monitors, monitors)
     |> assign(:selected_monitor_ids, selected_monitor_ids)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"status_page" => status_page_params}, socket) do
    changeset =
      socket.assigns.status_page
      |> Monitoring.change_status_page(status_page_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("toggle_monitor", %{"monitor-id" => monitor_id}, socket) do
    monitor_id = String.to_integer(monitor_id)

    selected_monitor_ids =
      if monitor_id in socket.assigns.selected_monitor_ids do
        List.delete(socket.assigns.selected_monitor_ids, monitor_id)
      else
        [monitor_id | socket.assigns.selected_monitor_ids]
      end

    {:noreply, assign(socket, :selected_monitor_ids, selected_monitor_ids)}
  end

  def handle_event("save", %{"status_page" => status_page_params}, socket) do
    save_status_page(socket, socket.assigns.action, status_page_params)
  end

  defp save_status_page(socket, :edit, status_page_params) do
    # Add user_id to params
    status_page_params = Map.put(status_page_params, "user_id", socket.assigns.user_id)

    case Monitoring.update_status_page(socket.assigns.status_page, status_page_params) do
      {:ok, status_page} ->
        # Update monitor associations
        update_status_page_monitors(status_page, socket.assigns.selected_monitor_ids)

        notify_parent({:saved, status_page})

        {:noreply,
         socket
         |> put_flash(:info, "Status page updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_status_page(socket, :new, status_page_params) do
    # Add user_id to params
    status_page_params = Map.put(status_page_params, "user_id", socket.assigns.user_id)

    case Monitoring.create_status_page(status_page_params) do
      {:ok, status_page} ->
        # Add monitor associations
        update_status_page_monitors(status_page, socket.assigns.selected_monitor_ids)

        notify_parent({:saved, status_page})

        {:noreply,
         socket
         |> put_flash(:info, "Status page created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp update_status_page_monitors(status_page, monitor_ids) do
    # Remove existing associations
    current_monitors = Monitoring.get_status_page_monitors(status_page)

    Enum.each(current_monitors, fn spm ->
      Monitoring.remove_monitor_from_status_page(status_page.id, spm.monitor_id)
    end)

    # Add new associations
    monitor_ids
    |> Enum.with_index()
    |> Enum.each(fn {monitor_id, index} ->
      Monitoring.add_monitor_to_status_page(status_page.id, monitor_id, %{sort_order: index})
    end)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp monitor_status_badge(monitor) do
    # TODO: Implement actual status checking
    "badge-success"
  end

  defp monitor_status_text(monitor) do
    # TODO: Implement actual status checking
    "Operational"
  end
end
