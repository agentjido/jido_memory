defmodule Jido.Memory.LongTermStoreFixtures do
  @moduledoc false

  alias Jido.Memory.LongTermStore.ETS, as: LongTermETS
  alias Jido.Memory.Store.ETS

  def backend(prefix \\ "jido_memory_long_term") do
    {LongTermETS, [store: store(prefix)]}
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
end
