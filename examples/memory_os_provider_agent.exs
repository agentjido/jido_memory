defmodule Example.MemoryOSProviderAgent do
  use Jido.Agent,
    name: "memory_os_provider_agent",
    default_plugins: %{__memory__: false},
    plugins: [
      {Jido.Memory.Plugin,
       %{
         provider:
           {Jido.MemoryOS.Provider,
            [
              server: Example.MemoryManager,
              app_config: %{
                tiers: %{
                  short: %{store: {Jido.Memory.Store.ETS, [table: :example_memory_os_short]}},
                  mid: %{store: {Jido.Memory.Store.ETS, [table: :example_memory_os_mid]}},
                  long: %{store: {Jido.Memory.Store.ETS, [table: :example_memory_os_long]}}
                }
              }
            ]}
       }}
    ]
end

provider =
  {Jido.MemoryOS.Provider,
   [
     server: Example.MemoryManager,
     app_config: %{
       tiers: %{
         short: %{store: {Jido.Memory.Store.ETS, [table: :example_memory_os_short]}},
         mid: %{store: {Jido.Memory.Store.ETS, [table: :example_memory_os_mid]}},
         long: %{store: {Jido.Memory.Store.ETS, [table: :example_memory_os_long]}}
       }
     }
   ]}

agent = %{id: "memory-os-agent-1"}

{:ok, explain} =
  Jido.Memory.Runtime.explain_retrieval(agent, %{text_contains: "memory", tier_mode: :short},
    provider: provider
  )

IO.inspect(explain, label: "memory_os provider explain")
