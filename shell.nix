{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    # Erlang and Elixir
    erlang_27
    elixir_1_17

    # Database
    postgresql_16

    # Build tools
    git
    gnumake
    gcc

    # Node.js for assets
    nodejs_22

    # Development tools
    inotify-tools  # For file watching
  ];

  shellHook = ''
    echo "🚀 Uptrack Development Environment"
    echo ""
    echo "Elixir: $(elixir --version | head -1)"
    echo "Erlang: $(erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell)"
    echo "Node: $(node --version)"
    echo "PostgreSQL: $(postgres --version)"
    echo ""
    echo "Available commands:"
    echo "  mix deps.get       - Install dependencies"
    echo "  mix compile        - Compile application"
    echo "  mix phx.server     - Start Phoenix server"
    echo "  iex -S mix         - Start IEx with application"
    echo ""

    # Set up PostgreSQL data directory if needed
    export PGDATA="$PWD/postgres_data"
    export DATABASE_URL="postgresql://postgres:postgres@localhost/uptrack_dev"

    echo "Environment configured!"
    echo ""
  '';
}
