defmodule Example.TieredProviderAgent do
  alias Jido.Memory.LongTermStore.ETS, as: LongTermETS
  alias Jido.Memory.Provider.Tiered
  alias Jido.Memory.Runtime
  alias Jido.Memory.Store.ETS

  def plugin_config(prefix \\ "example_tiered") do
    %{provider: :tiered, provider_opts: provider_opts(prefix)}
  end

  def provider(prefix \\ "example_tiered") do
    {Tiered, provider_opts(prefix)}
  end

  def run_demo(agent_id \\ "tiered-agent-1", prefix \\ "example_tiered") do
    provider = provider(prefix)
    agent = %{id: agent_id}

    {:ok, record} =
      Runtime.remember(
        agent,
        %{
          class: :semantic,
          kind: :fact,
          text: "Tiered providers promote high-value memories.",
          tags: ["tiered", "memory"],
          importance: 1.0
        },
        provider: provider
      )

    {:ok, initial_results} =
      Runtime.retrieve(
        agent,
        %{text_contains: "Tiered providers", tiers: [:short, :mid, :long]},
        provider: provider
      )

    {:ok, lifecycle_result} = Runtime.consolidate(agent, provider: provider, tier: :short)
    {:ok, promoted_record} = Runtime.get(agent, record.id, provider: provider, tier: :mid)

    {:ok,
     %{
       provider: provider,
       record: record,
       initial_results: initial_results,
       lifecycle_result: lifecycle_result,
       promoted_record: promoted_record
     }}
  end

  defp provider_opts(prefix) do
    [
      short_store: store(prefix, "short"),
      mid_store: store(prefix, "mid"),
      long_term_store: {LongTermETS, [store: store(prefix, "long")]},
      lifecycle: [short_to_mid_threshold: 0.65, mid_to_long_threshold: 0.85]
    ]
  end

  defp store(prefix, suffix) do
    table = String.to_atom("#{prefix}_#{suffix}")
    {ETS, [table: table]}
  end
end
