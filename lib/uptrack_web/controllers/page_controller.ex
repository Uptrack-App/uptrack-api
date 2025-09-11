defmodule UptrackWeb.PageController do
  use UptrackWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
