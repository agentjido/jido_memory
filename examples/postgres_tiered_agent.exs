defmodule Example.PostgresTieredAgent do
  alias Jido.Memory.LongTermStore.Postgres
  alias Jido.Memory.Provider.Tiered
  alias Jido.Memory.Runtime
  alias Jido.Memory.Store.ETS

  def plugin_config(prefix \\ "example_postgres_tiered") do
    %{provider: :tiered, provider_opts: provider_opts(prefix)}
  end

  def provider(prefix \\ "example_postgres_tiered") do
    {Tiered, provider_opts(prefix)}
  end

  def run_demo(agent_id \\ "postgres-tiered-agent-1", prefix \\ "example_postgres_tiered") do
    provider = provider(prefix)
    agent = %{id: agent_id}

    {:ok, record} =
      Runtime.remember(
        agent,
        %{
          class: :semantic,
          kind: :fact,
          text: "Postgres-backed long-term memory can persist promoted records.",
          tags: ["important", "durable"],
          importance: 1.0,
          tier: :mid
        },
        provider: provider
      )

    {:ok, lifecycle_result} = Runtime.consolidate(agent, provider: provider, tier: :mid)

    {:ok, long_record} = Runtime.get(agent, record.id, provider: provider, tier: :long)

    {:ok, records} =
      Runtime.retrieve(
        agent,
        %{text_contains: "persist promoted", tiers: [:short, :mid, :long]},
        provider: provider
      )

    {:ok,
     %{
       provider: provider,
       record: record,
       lifecycle_result: lifecycle_result,
       long_record: long_record,
       records: records
     }}
  end

  defp provider_opts(prefix) do
    [
      short_store: store(prefix, "short"),
      mid_store: store(prefix, "mid"),
      long_term_store: {Postgres, postgres_opts(prefix)},
      lifecycle: [short_to_mid_threshold: 0.65, mid_to_long_threshold: 0.85]
    ]
  end

  defp postgres_opts(prefix) do
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
      table: "jido_memory_postgres_example_#{System.unique_integer([:positive])}_#{normalize_prefix(prefix)}"
    )
  end

  defp store(prefix, suffix) do
    table = String.to_atom("#{prefix}_#{suffix}")
    {ETS, [table: table]}
  end

  defp normalize_prefix(prefix) when is_binary(prefix) do
    prefix
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
    |> String.downcase()
  end
end
