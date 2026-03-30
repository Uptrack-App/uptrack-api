defmodule Uptrack.Auth.BackupCodesTest do
  use ExUnit.Case, async: true

  alias Uptrack.Auth.BackupCodes

  describe "generate/0" do
    test "returns 10 codes" do
      codes = BackupCodes.generate()
      assert length(codes) == 10
    end

    test "each code is 8 hex characters" do
      codes = BackupCodes.generate()

      for code <- codes do
        assert String.length(code) == 8
        assert String.match?(code, ~r/^[0-9a-f]+$/)
      end
    end

    test "codes are unique" do
      codes = BackupCodes.generate()
      assert length(Enum.uniq(codes)) == 10
    end
  end

  describe "hash_all/1" do
    test "returns hashed entries with used: false" do
      codes = BackupCodes.generate()
      hashed = BackupCodes.hash_all(codes)

      assert length(hashed) == 10

      for entry <- hashed do
        assert %{hash: hash, used: false} = entry
        assert String.starts_with?(hash, "$2b$")
      end
    end
  end

  describe "verify/2" do
    test "matches a valid unused code" do
      codes = BackupCodes.generate()
      hashed = BackupCodes.hash_all(codes)

      assert {:ok, 0} = BackupCodes.verify(Enum.at(codes, 0), hashed)
      assert {:ok, 5} = BackupCodes.verify(Enum.at(codes, 5), hashed)
    end

    test "rejects an invalid code" do
      codes = BackupCodes.generate()
      hashed = BackupCodes.hash_all(codes)

      assert {:error, :invalid} = BackupCodes.verify("notacode", hashed)
    end

    test "rejects a used code" do
      codes = BackupCodes.generate()
      hashed = BackupCodes.hash_all(codes)

      # Mark first code as used
      hashed = List.update_at(hashed, 0, &Map.put(&1, :used, true))

      assert {:error, :invalid} = BackupCodes.verify(Enum.at(codes, 0), hashed)
    end

    test "rejects nil input" do
      assert {:error, :invalid} = BackupCodes.verify(nil, [])
    end
  end
end
