defmodule Jido.Memory.ProviderFixtures do
  @moduledoc false

  alias Jido.Memory.LongTermStore.ETS, as: LongTermETS
  alias Jido.Memory.ProviderRef
  alias Jido.Memory.Store.ETS

  def unique_store(prefix) do
    table = String.to_atom("#{prefix}_#{System.unique_integer([:positive])}")
    opts = [table: table]
    :ok = ETS.ensure_ready(opts)
    {ETS, opts}
  end

  def basic_provider(prefix \\ "jido_memory_basic") do
    {:basic, [store: unique_store("#{prefix}_store"), namespace: "agent:#{prefix}"]}
  end

  def tiered_provider(prefix \\ "jido_memory_tiered") do
    {:tiered,
     [
       short_store: unique_store("#{prefix}_short"),
       mid_store: unique_store("#{prefix}_mid"),
       long_term_store: {LongTermETS, [store: unique_store("#{prefix}_long")]},
       lifecycle: [short_to_mid_threshold: 0.65, mid_to_long_threshold: 0.85]
     ]}
  end

  def plugin_state(provider, overrides \\ %{}) do
    {:ok, provider_ref} = ProviderRef.normalize(provider)

    Map.merge(
      %{
        provider: provider_ref,
        auto_capture: true,
        capture_signal_patterns: []
      },
      overrides
    )
  end

  def agent(agent_id, provider, overrides \\ %{}) do
    %{id: agent_id, state: %{__memory__: plugin_state(provider, overrides)}}
  end

  def important_attrs(text, extra \\ %{}) do
    Map.merge(
      %{
        class: :semantic,
        kind: :fact,
        text: text,
        tags: ["important"],
        importance: 1.0
      },
      extra
    )
  end
end
