defmodule Jido.Memory.LongTermStoreFixtures do
  @moduledoc false

  alias Jido.Memory.LongTermStore.ETS, as: LongTermETS
  alias Jido.Memory.LongTermStore.Postgres
  alias Jido.Memory.Store.ETS

  def backend(prefix \\ "jido_memory_long_term") do
    {LongTermETS, [store: store(prefix)]}
  end

  def postgres_backend(prefix \\ "jido_memory_long_term_pg") do
    {Postgres, postgres_opts(prefix)}
  end

  def postgres_opts(prefix \\ "jido_memory_long_term_pg") do
    base =
      case System.get_env("JIDO_MEMORY_PG_URL") do
        url when is_binary(url) and url != "" ->
          [url: url]

        _other ->
          [
            database: System.get_env("JIDO_MEMORY_PG_DATABASE", "postgres"),
            username: System.get_env("JIDO_MEMORY_PG_USERNAME", System.get_env("USER")),
            socket_dir: System.get_env("JIDO_MEMORY_PG_SOCKET_DIR", "/tmp")
          ]
      end

    Keyword.merge(base,
      schema: "public",
      table: "jido_memory_long_term_#{System.unique_integer([:positive])}_#{normalize_prefix(prefix)}"
    )
  end

  def store(prefix) do
    table = String.to_atom("#{prefix}_#{System.unique_integer([:positive])}")
    opts = [table: table]
    :ok = ETS.ensure_ready(opts)
    {ETS, opts}
  end

  def namespace(prefix \\ "long_term") do
    "long-term:#{prefix}:#{System.unique_integer([:positive])}"
  end

  def target(prefix \\ "long_term_agent") do
    %{id: "#{prefix}-#{System.unique_integer([:positive])}"}
  end

  def durable_attrs(text, extra \\ %{}) do
    Map.merge(
      %{
        class: :semantic,
        kind: :fact,
        text: text,
        tags: ["important", "durable"],
        observed_at: 2_000_000_000,
        metadata: %{
          importance: 1.0,
          tiered: %{
            tier: :long,
            promotion_count: 2,
            promoted_from: :mid
          }
        }
      },
      extra
    )
  end

  def expired_attrs(text, now) do
    durable_attrs(text, %{expires_at: now - 1_000})
  end

  def active_attrs(text, now) do
    durable_attrs(text, %{expires_at: now + 60_000})
  end

  def postgres_available? do
    case Code.ensure_loaded(Postgrex) do
      {:module, Postgrex} ->
        case Postgrex.start_link(postgres_connection_check_opts()) do
          {:ok, pid} ->
            GenServer.stop(pid)
            true

          {:error, _reason} ->
            false
        end

      {:error, _reason} ->
        false
    end
  end

  defp postgres_connection_check_opts do
    postgres_opts("availability_check")
    |> Keyword.drop([:schema, :table])
  end

  defp normalize_prefix(prefix) when is_binary(prefix) do
    prefix
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
    |> String.downcase()
  end
end
