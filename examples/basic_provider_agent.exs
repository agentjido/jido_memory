defmodule Example.BasicProviderAgent do
  use Jido.Agent,
    name: "basic_provider_agent",
    default_plugins: %{__memory__: false},
    plugins: [
      {Jido.Memory.Plugin,
       %{
         provider:
           {Jido.Memory.Provider.Basic,
            [store: {Jido.Memory.Store.ETS, [table: :example_basic_provider_memory]}}}
       }}
    ]
end

agent = %{id: "basic-agent-1"}
provider = {Jido.Memory.Provider.Basic, [store: {Jido.Memory.Store.ETS, [table: :example_basic_provider_memory]}]}

{:ok, _record} =
  Jido.Memory.Runtime.remember(agent, %{class: :episodic, kind: :event, text: "remember me"},
    provider: provider
  )

{:ok, records} = Jido.Memory.Runtime.retrieve(agent, %{text_contains: "remember"}, provider: provider)
IO.inspect(records, label: "basic provider records")
