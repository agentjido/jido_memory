defmodule Example.ExternalProvider do
  @behaviour Jido.Memory.Provider

  alias Jido.Memory.Provider.Basic

  def validate_config(opts), do: Basic.validate_config(opts)

  def child_specs(opts) do
    id = Keyword.get(opts, :bootstrap_id, {__MODULE__, :bootstrap})

    [
      Supervisor.child_spec(
        {Agent, fn -> %{provider: __MODULE__, namespace: Keyword.get(opts, :namespace)} end},
        id: id
      )
    ]
  end

  def init(opts) do
    with {:ok, meta} <- Basic.init(opts) do
      {:ok,
       meta
       |> Map.put(:provider, __MODULE__)
       |> Map.put(:external?, true)
       |> Map.put(:bootstrap, %{ownership: :caller, child_specs: length(child_specs(opts))})}
    end
  end

  def capabilities(meta) do
    meta
    |> Basic.capabilities()
    |> Map.put(:interop, %{external: true, caller_bootstrap: true})
  end

  def remember(target, attrs, opts), do: Basic.remember(target, attrs, opts)
  def get(target, id, opts), do: Basic.get(target, id, opts)
  def retrieve(target, query, opts), do: Basic.retrieve(target, query, opts)
  def forget(target, id, opts), do: Basic.forget(target, id, opts)
  def prune(target, opts), do: Basic.prune(target, opts)
  def info(meta, fields), do: Basic.info(meta, fields)
end

defmodule Example.ExternalProviderAgent do
  alias Jido.Memory.Plugin
  alias Jido.Memory.ProviderBootstrap
  alias Jido.Memory.Runtime
  alias Jido.Memory.Store.ETS

  def provider_aliases do
    %{external_demo: Example.ExternalProvider}
  end

  def plugin_config(prefix \\ "example_external") do
    %{
      provider: :external_demo,
      provider_aliases: provider_aliases(),
      provider_opts: [store: store(prefix), namespace: "provider:external-demo"]
    }
  end

  def bootstrap(prefix \\ "example_external") do
    ProviderBootstrap.describe({Example.ExternalProvider, [store: store(prefix), namespace: "provider:external-demo"]})
  end

  def run_demo(agent_id \\ "external-agent-1", prefix \\ "example_external") do
    {:ok, plugin_state} = Plugin.mount(%{id: agent_id}, plugin_config(prefix))
    agent = %{id: agent_id, state: %{__memory__: plugin_state}}

    {:ok, record} =
      Runtime.remember(agent, %{class: :episodic, kind: :event, text: "External providers plug into the same facade."}, [])

    {:ok, records} =
      Runtime.retrieve(agent, %{text_contains: "External providers", limit: 10}, [])

    {:ok, bootstrap} = bootstrap(prefix)

    {:ok, %{plugin_state: plugin_state, record: record, records: records, bootstrap: bootstrap}}
  end

  defp store(prefix) do
    table = String.to_atom("#{prefix}_memory")
    {ETS, [table: table]}
  end
end
