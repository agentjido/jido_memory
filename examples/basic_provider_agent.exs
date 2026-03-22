defmodule Example.BasicProviderAgent do
  alias Jido.Memory.Provider.Basic
  alias Jido.Memory.Runtime
  alias Jido.Memory.Store.ETS

  def plugin_config(prefix \\ "example_basic") do
    %{provider: :basic, provider_opts: [store: store(prefix), namespace: "agent:basic-example"]}
  end

  def provider(prefix \\ "example_basic") do
    {Basic, [store: store(prefix), namespace: "agent:basic-example"]}
  end

  def run_demo(agent_id \\ "basic-agent-1", prefix \\ "example_basic") do
    provider = provider(prefix)
    agent = %{id: agent_id}

    {:ok, record} =
      Runtime.remember(agent, %{class: :episodic, kind: :event, text: "Basic providers keep setup simple."},
        provider: provider
      )

    {:ok, records} =
      Runtime.retrieve(agent, %{text_contains: "Basic providers", limit: 10}, provider: provider)

    {:ok, %{provider: provider, record: record, records: records}}
  end

  defp store(prefix) do
    table = String.to_atom("#{prefix}_memory")
    {ETS, [table: table]}
  end
end
