defmodule Uptrack.Auth.BackupCodes do
  @moduledoc """
  Pure backup code operations — no database, no side effects.

  Generates, hashes, and verifies one-time backup codes for 2FA recovery.
  """

  @code_count 10
  @code_length 8

  @doc """
  Generates a list of plaintext backup codes.

  Returns `@code_count` codes, each `@code_length` hex characters.
  These should be displayed to the user once and never stored in plaintext.
  """
  def generate do
    Enum.map(1..@code_count, fn _ ->
      :crypto.strong_rand_bytes(div(@code_length, 2))
      |> Base.encode16(case: :lower)
    end)
  end

  @doc """
  Hashes a list of plaintext codes for storage.

  Returns a list of `{hash, used: false}` tuples.
  """
  def hash_all(codes) do
    Enum.map(codes, fn code ->
      %{hash: Bcrypt.hash_pwd_salt(code), used: false}
    end)
  end

  @doc """
  Verifies a plaintext code against a list of hashed codes.

  Returns `{:ok, index}` if the code matches an unused code,
  or `{:error, :invalid}` if no match.
  """
  def verify(code, hashed_codes) when is_binary(code) and is_list(hashed_codes) do
    hashed_codes
    |> Enum.with_index()
    |> Enum.find(fn {entry, _idx} ->
      hash = Map.get(entry, :hash) || Map.get(entry, "hash")
      used = Map.get(entry, :used, Map.get(entry, "used", false))
      not used and Bcrypt.verify_pass(code, hash)
    end)
    |> case do
      {_entry, index} -> {:ok, index}
      nil -> {:error, :invalid}
    end
  end

  def verify(_code, _hashed_codes), do: {:error, :invalid}
end
