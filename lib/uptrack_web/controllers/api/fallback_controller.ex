defmodule UptrackWeb.Api.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.
  """
  use UptrackWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: UptrackWeb.Api.ErrorJSON)
    |> render(:error, changeset: changeset)
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: UptrackWeb.Api.ErrorJSON)
    |> render(:error, message: "Resource not found")
  end

  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> put_view(json: UptrackWeb.Api.ErrorJSON)
    |> render(:error, message: "You don't have permission to perform this action")
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: UptrackWeb.Api.ErrorJSON)
    |> render(:error, message: "Authentication required")
  end

  def call(conn, {:error, :member_not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: UptrackWeb.Api.ErrorJSON)
    |> render(:error, message: "Team member not found")
  end

  def call(conn, {:error, :cannot_remove_last_owner}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: UptrackWeb.Api.ErrorJSON)
    |> render(:error, message: "Cannot remove or demote the last owner. Transfer ownership first.")
  end

  def call(conn, {:error, :already_member}) do
    conn
    |> put_status(:conflict)
    |> put_view(json: UptrackWeb.Api.ErrorJSON)
    |> render(:error, message: "User is already a member of this organization")
  end

  def call(conn, {:error, :invitation_not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: UptrackWeb.Api.ErrorJSON)
    |> render(:error, message: "Invitation not found")
  end

  def call(conn, {:error, :invitation_expired}) do
    conn
    |> put_status(:gone)
    |> put_view(json: UptrackWeb.Api.ErrorJSON)
    |> render(:error, message: "This invitation has expired")
  end

  def call(conn, {:error, :not_owner}) do
    conn
    |> put_status(:forbidden)
    |> put_view(json: UptrackWeb.Api.ErrorJSON)
    |> render(:error, message: "Only the organization owner can perform this action")
  end
end
