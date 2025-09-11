defmodule UptrackWeb.StatusPageLive do
  use UptrackWeb, :live_view

  alias Uptrack.Monitoring
  alias Uptrack.Monitoring.StatusPage

  @impl true
  def mount(_params, _session, socket) do
    # TODO: Get user from session/auth
    # Placeholder - will be replaced with actual auth
    user_id = 1

    status_pages = Monitoring.list_status_pages(user_id)

    socket =
      socket
      |> assign(:user_id, user_id)
      |> assign(:status_pages, status_pages)
      |> assign(:page_title, "Status Pages")

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Status Pages")
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Status Page")
    |> assign(:status_page, %StatusPage{})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    status_page = Monitoring.get_status_page!(id)

    socket
    |> assign(:page_title, "Edit Status Page")
    |> assign(:status_page, status_page)
  end

  defp apply_action(socket, :widgets, %{"id" => id}) do
    status_page = Monitoring.get_status_page!(id)

    socket
    |> assign(:page_title, "Embed Widgets")
    |> assign(:status_page, status_page)
    |> assign(:selected_widget_type, "compact")
    |> assign(:selected_theme, "auto")
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    status_page = Monitoring.get_status_page!(id)
    {:ok, _} = Monitoring.delete_status_page(status_page)

    # Refresh the list
    status_pages = Monitoring.list_status_pages(socket.assigns.user_id)

    socket =
      socket
      |> assign(:status_pages, status_pages)
      |> put_flash(:info, "Status page deleted successfully")

    {:noreply, socket}
  end

  def handle_event("change_widget_type", %{"type" => type}, socket) do
    {:noreply, assign(socket, :selected_widget_type, type)}
  end

  def handle_event("change_theme", %{"theme" => theme}, socket) do
    {:noreply, assign(socket, :selected_theme, theme)}
  end

  @impl true
  def handle_info({UptrackWeb.StatusPageLive.FormComponent, {:saved, _status_page}}, socket) do
    # Refresh the data when a status page is saved
    status_pages = Monitoring.list_status_pages(socket.assigns.user_id)

    socket =
      socket
      |> assign(:status_pages, status_pages)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header -->
      <div class="flex justify-between items-center">
        <div>
          <h1 class="text-3xl font-bold">
            <%= if @live_action == :widgets do %>
              Embed Widgets - {@status_page.name}
            <% else %>
              Status Pages
            <% end %>
          </h1>
          <p class="text-base-content/70">
            <%= if @live_action == :widgets do %>
              Create embeddable widgets for your status page
            <% else %>
              Create public status pages for your services
            <% end %>
          </p>
        </div>
        <%= if @live_action == :widgets do %>
          <.link navigate={~p"/dashboard/status-pages"} class="btn btn-ghost">
            <.icon name="hero-arrow-left" class="w-4 h-4" /> Back to Status Pages
          </.link>
        <% else %>
          <.link patch={~p"/dashboard/status-pages/new"} class="btn btn-primary">
            <.icon name="hero-plus" class="w-4 h-4" /> New Status Page
          </.link>
        <% end %>
      </div>
      
    <!-- Navigation Tabs -->
      <div class="tabs tabs-bordered">
        <.link navigate={~p"/dashboard"} class="tab">
          <.icon name="hero-chart-bar" class="w-4 h-4" /> Dashboard
        </.link>
        <.link navigate={~p"/dashboard/alerts"} class="tab">
          <.icon name="hero-bell" class="w-4 h-4" /> Alert Channels
        </.link>
        <.link navigate={~p"/dashboard/status-pages"} class="tab tab-active">
          <.icon name="hero-globe-alt" class="w-4 h-4" /> Status Pages
        </.link>
        <.link navigate={~p"/dashboard/incidents"} class="tab">
          <.icon name="hero-exclamation-triangle" class="w-4 h-4" /> Incidents
        </.link>
      </div>
      
    <!-- Status Pages List -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <%= if Enum.empty?(@status_pages) do %>
          <div class="col-span-full">
            <div class="card bg-base-100 shadow p-12 text-center">
              <.icon name="hero-globe-alt" class="w-16 h-16 mx-auto text-base-content/30 mb-4" />
              <h3 class="text-lg font-medium mb-2">No status pages created</h3>
              <p class="text-base-content/70 mb-4">
                Create your first status page to share service status with your users.
              </p>
              <.link patch={~p"/dashboard/status-pages/new"} class="btn btn-primary">
                Create Status Page
              </.link>
            </div>
          </div>
        <% else %>
          <%= for status_page <- @status_pages do %>
            <div class="card bg-base-100 shadow">
              <div class="card-body">
                <div class="flex items-start justify-between">
                  <div class="flex-1">
                    <h3 class="font-semibold text-lg mb-1">{status_page.name}</h3>
                    <p class="text-sm text-base-content/70 mb-3">
                      <%= if status_page.description do %>
                        {status_page.description}
                      <% else %>
                        No description
                      <% end %>
                    </p>

                    <div class="flex items-center gap-2 mb-3">
                      <span class="text-sm font-medium">URL:</span>
                      <a
                        href={~p"/status/#{status_page.slug}"}
                        target="_blank"
                        class="text-sm text-primary hover:underline"
                      >
                        /status/{status_page.slug}
                        <.icon name="hero-arrow-top-right-on-square" class="w-3 h-3 inline ml-1" />
                      </a>
                    </div>

                    <div class="flex items-center gap-4 text-xs text-base-content/60">
                      <span class={[
                        "badge badge-sm",
                        if(status_page.is_public, do: "badge-success", else: "badge-neutral")
                      ]}>
                        {if status_page.is_public, do: "Public", else: "Private"}
                      </span>
                      <span>Created {format_date(status_page.inserted_at)}</span>
                    </div>
                  </div>

                  <div class="dropdown dropdown-end">
                    <label tabindex="0" class="btn btn-ghost btn-sm">
                      <.icon name="hero-ellipsis-vertical" class="w-4 h-4" />
                    </label>
                    <ul
                      tabindex="0"
                      class="dropdown-content menu p-2 shadow bg-base-100 rounded-box w-52"
                    >
                      <li>
                        <a href={~p"/status/#{status_page.slug}"} target="_blank" class="text-info">
                          <.icon name="hero-eye" class="w-4 h-4" /> View Page
                        </a>
                      </li>
                      <li>
                        <.link patch={~p"/dashboard/status-pages/#{status_page.id}/edit"}>
                          <.icon name="hero-pencil" class="w-4 h-4" /> Edit
                        </.link>
                      </li>
                      <li>
                        <.link patch={~p"/dashboard/status-pages/#{status_page.id}/widgets"} class="text-primary">
                          <.icon name="hero-code-bracket" class="w-4 h-4" /> Embed Widgets
                        </.link>
                      </li>
                      <li>
                        <button
                          phx-click="delete"
                          phx-value-id={status_page.id}
                          class="text-error"
                          data-confirm="Are you sure you want to delete this status page?"
                        >
                          <.icon name="hero-trash" class="w-4 h-4" /> Delete
                        </button>
                      </li>
                    </ul>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
      
    <!-- Quick Setup Guide -->
      <%= if Enum.empty?(@status_pages) do %>
        <div class="card bg-gradient-to-br from-blue-50 to-blue-100 border border-blue-200">
          <div class="card-body">
            <h3 class="font-semibold text-blue-900 mb-3">How to create a status page</h3>
            <ol class="list-decimal list-inside text-sm text-blue-800 space-y-2">
              <li>Click "New Status Page" to create your first status page</li>
              <li>Choose a name and URL slug for your status page</li>
              <li>Add monitors that you want to display publicly</li>
              <li>Customize the appearance and branding</li>
              <li>Share the public URL with your users</li>
            </ol>
          </div>
        </div>
      <% end %>
    </div>

    <!-- Form for new/edit status page -->
    <%= if @live_action in [:new, :edit] do %>
      <div class="card bg-base-100 shadow mt-6">
        <div class="card-body">
          <.live_component
            module={UptrackWeb.StatusPageLive.FormComponent}
            id={@status_page.id || :new}
            title={@page_title}
            action={@live_action}
            status_page={@status_page}
            user_id={@user_id}
            patch={~p"/dashboard/status-pages"}
          />
        </div>
      </div>
    <% end %>
    
    <!-- Widgets Configuration -->
    <%= if @live_action == :widgets do %>
      <.render_widgets_view assigns={assigns} />
    <% end %>
    """
  end

  defp render_widgets_view(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
      <!-- Widget Configuration -->
      <div class="space-y-6">
        <div class="card bg-base-100 shadow">
          <div class="card-body">
            <h3 class="card-title mb-4">Widget Configuration</h3>
            
            <div class="space-y-4">
              <!-- Widget Type Selection -->
              <div class="form-control w-full">
                <label class="label">
                  <span class="label-text font-medium">Widget Type</span>
                </label>
                <select 
                  class="select select-bordered w-full"
                  phx-change="change_widget_type"
                  name="type"
                >
                  <option value="badge" selected={@selected_widget_type == "badge"}>Badge</option>
                  <option value="compact" selected={@selected_widget_type == "compact"}>Compact</option>
                  <option value="summary" selected={@selected_widget_type == "summary"}>Summary</option>
                  <option value="detailed" selected={@selected_widget_type == "detailed"}>Detailed</option>
                </select>
                <div class="label">
                  <span class="label-text-alt">
                    <%= case @selected_widget_type do %>
                      <% "badge" -> %> Small inline status indicator
                      <% "compact" -> %> Compact status with service count
                      <% "summary" -> %> Shows overall status + top services
                      <% "detailed" -> %> Full status with all services
                    <% end %>
                  </span>
                </div>
              </div>
              
              <!-- Theme Selection -->
              <div class="form-control w-full">
                <label class="label">
                  <span class="label-text font-medium">Theme</span>
                </label>
                <select 
                  class="select select-bordered w-full"
                  phx-change="change_theme"
                  name="theme"
                >
                  <option value="auto" selected={@selected_theme == "auto"}>Auto (System)</option>
                  <option value="light" selected={@selected_theme == "light"}>Light</option>
                  <option value="dark" selected={@selected_theme == "dark"}>Dark</option>
                </select>
                <div class="label">
                  <span class="label-text-alt">Widget color theme preference</span>
                </div>
              </div>
            </div>
          </div>
        </div>
        
        <!-- Embed Code -->
        <div class="card bg-base-100 shadow">
          <div class="card-body">
            <h3 class="card-title mb-4">Embed Code</h3>
            
            <div class="tabs tabs-bordered mb-4">
              <a class="tab tab-active">HTML</a>
            </div>
            
            <div class="mockup-code">
              <pre><code id="embed-code" class="text-sm">{"<iframe 
  src=\"#{get_widget_url(@status_page.slug, @selected_widget_type, @selected_theme)}\"
  width=\"#{get_widget_width(@selected_widget_type)}\" 
  height=\"#{get_widget_height(@selected_widget_type)}\"
  frameborder=\"0\"
  scrolling=\"no\"
  title=\"#{@status_page.name} Status Widget\">
</iframe>"}</code></pre>
            </div>
            
            <div class="mt-4">
              <button 
                class="btn btn-primary btn-sm"
                onclick="navigator.clipboard.writeText(document.getElementById('embed-code').textContent)"
              >
                <.icon name="hero-clipboard-document" class="w-4 h-4" /> Copy Code
              </button>
            </div>
            
            <div class="mt-4">
              <h4 class="font-medium mb-2">Direct Widget URL:</h4>
              <div class="input input-bordered text-sm p-2">
                <a 
                  href={get_widget_url(@status_page.slug, @selected_widget_type, @selected_theme)} 
                  target="_blank"
                  class="link"
                >
                  {get_widget_url(@status_page.slug, @selected_widget_type, @selected_theme)}
                </a>
              </div>
            </div>
          </div>
        </div>
      </div>
      
      <!-- Widget Preview -->
      <div class="space-y-6">
        <div class="card bg-base-100 shadow">
          <div class="card-body">
            <h3 class="card-title mb-4">Widget Preview</h3>
            
            <div class="border border-base-300 rounded-lg p-6 bg-base-50">
              <iframe 
                src={get_widget_url(@status_page.slug, @selected_widget_type, @selected_theme)}
                width={get_widget_width(@selected_widget_type)} 
                height={get_widget_height(@selected_widget_type)}
                frameborder="0"
                scrolling="no"
                class="mx-auto"
                title={"#{@status_page.name} Status Widget Preview"}
              >
              </iframe>
            </div>
            
            <div class="mt-4 text-sm text-base-content/70">
              <p><strong>Responsive:</strong> Widgets automatically adapt to mobile devices</p>
              <p><strong>Real-time:</strong> Status updates automatically via LiveView</p>
              <p><strong>Customizable:</strong> Themes adapt to your website's design</p>
            </div>
          </div>
        </div>
        
        <!-- Usage Instructions -->
        <div class="card bg-gradient-to-br from-blue-50 to-blue-100 border border-blue-200">
          <div class="card-body">
            <h3 class="font-semibold text-blue-900 mb-3">How to use widgets</h3>
            <ol class="list-decimal list-inside text-sm text-blue-800 space-y-1">
              <li>Choose your preferred widget type and theme</li>
              <li>Copy the generated HTML embed code</li>
              <li>Paste it into your website, app, or documentation</li>
              <li>The widget will automatically show real-time status updates</li>
            </ol>
            
            <div class="mt-4 p-3 bg-blue-100 rounded border border-blue-300">
              <p class="text-xs text-blue-700">
                <strong>Note:</strong> Widgets work on any website and are mobile-responsive. 
                They update in real-time and don't require any JavaScript libraries.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
  
  defp get_widget_url(slug, type, theme) do
    base_url = "http://localhost:4000"  # TODO: Use proper domain in production
    "#{base_url}/widget/#{slug}?type=#{type}&theme=#{theme}"
  end
  
  defp get_widget_width("badge"), do: "200"
  defp get_widget_width("compact"), do: "300"
  defp get_widget_width("summary"), do: "400"
  defp get_widget_width("detailed"), do: "500"
  
  defp get_widget_height("badge"), do: "40"
  defp get_widget_height("compact"), do: "120"
  defp get_widget_height("summary"), do: "300"
  defp get_widget_height("detailed"), do: "400"

  defp format_date(datetime) do
    datetime
    |> DateTime.to_date()
    |> Date.to_string()
  end
end
