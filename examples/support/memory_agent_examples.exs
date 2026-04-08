defmodule Jido.Memory.Examples.Actions.RetrieveNotes do
  @moduledoc false

  use Jido.Action,
    name: "example_retrieve_notes",
    description: "Retrieve stored notes from Jido.Memory for a running agent",
    schema: [
      query: [type: :string, required: true, doc: "Case-insensitive text to retrieve"],
      namespace: [type: :string, required: false, doc: "Optional explicit namespace override"],
      limit: [type: :integer, required: false, default: 5, doc: "Maximum notes to return"]
    ]

  alias Jido.Memory.{RetrieveResult, Runtime}

  @impl true
  def run(params, context) do
    query =
      %{
        text_contains: params[:query],
        limit: params[:limit] || 5,
        order: :asc
      }
      |> maybe_put_namespace(params[:namespace])

    case Runtime.retrieve(context, query) do
      {:ok, result} ->
        records = RetrieveResult.records(result)
        texts = Enum.map(records, & &1.text)

        {:ok,
         %{
           retrieved_texts: texts,
           retrieved_count: length(texts),
           memory_result: result
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_put_namespace(query, nil), do: query
  defp maybe_put_namespace(query, ""), do: query
  defp maybe_put_namespace(query, namespace), do: Map.put(query, :namespace, namespace)
end

defmodule Jido.Memory.Examples.JidoAgent do
  @moduledoc false

  use Jido.Agent,
    name: "jido_memory_examples_agent",
    description: "Example Jido agent using Jido.Memory.BasicPlugin",
    default_plugins: %{__memory__: false},
    plugins: [
      {Jido.Memory.BasicPlugin,
       %{
         store: {Jido.Memory.Store.ETS, [table: :jido_memory_examples_agent]},
         namespace_mode: :per_agent,
         auto_capture: true
       }}
    ],
    signal_routes: [
      {"demo.retrieve", Jido.Memory.Examples.Actions.RetrieveNotes}
    ],
    schema: [
      retrieved_texts: [type: :any, default: []],
      retrieved_count: [type: :integer, default: 0]
    ]
end

defmodule Jido.Memory.Examples.AIEnabledAgent do
  @moduledoc false

  @strategy_opts [
    tools: [Jido.Memory.Examples.Actions.RetrieveNotes],
    model: :fast,
    max_iterations: 4,
    request_policy: :reject,
    tool_timeout_ms: 5_000,
    tool_max_retries: 0,
    tool_retry_backoff_ms: 100,
    runtime_adapter: true,
    observability: %{},
    tool_context: %{},
    system_prompt:
      "You are a memory-enabled demo agent. Use the example_retrieve_notes tool when memory lookups are needed."
  ]

  use Jido.Agent,
    name: "jido_memory_examples_ai_agent",
    description: "Example AI-capable Jido agent wired to Jido.Memory",
    default_plugins: %{__memory__: false},
    plugins:
      Jido.AI.PluginStack.default_plugins() ++
        [
          {Jido.Memory.BasicPlugin,
           %{
             store: {Jido.Memory.Store.ETS, [table: :jido_memory_examples_ai]},
             namespace_mode: :per_agent,
             auto_capture: true
           }}
        ],
    strategy: {Jido.AI.Reasoning.ReAct.Strategy, @strategy_opts},
    schema:
      Zoi.object(%{
        __strategy__: Zoi.map() |> Zoi.default(%{}),
        model: Zoi.any() |> Zoi.default(:fast),
        requests: Zoi.map() |> Zoi.default(%{}),
        last_request_id: Zoi.string() |> Zoi.optional(),
        last_query: Zoi.string() |> Zoi.default(""),
        last_answer: Zoi.string() |> Zoi.default(""),
        completed: Zoi.boolean() |> Zoi.default(false)
      })
end

defmodule Jido.Memory.Examples.Runner do
  @moduledoc false

  alias Jido.AI.Actions.ToolCalling.ExecuteTool
  alias Jido.AgentServer
  alias Jido.Memory.Examples.{AIEnabledAgent, JidoAgent}
  alias Jido.Memory.Examples.Actions.RetrieveNotes
  alias Jido.Memory.Runtime
  alias Jido.Memory.Store.ETS
  alias Jido.Signal

  @plain_table :jido_memory_examples_agent
  @ai_table :jido_memory_examples_ai
  @jido_instance Jido.Memory.Examples.JidoRuntime
  @runtime_owner Jido.Memory.Examples.JidoRuntimeOwner
  @runtime_start_timeout 5_000

  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) when is_list(opts) do
    with :ok <- ensure_runtime_started(),
         :ok <- ensure_tables_ready(),
         {:ok, plain_result} <- run_plain_agent_demo(opts),
         {:ok, ai_result} <- run_ai_agent_demo(opts) do
      {:ok,
       %{
         plain_agent: plain_result,
         ai_agent: ai_result
       }}
    end
  end

  @spec ensure_tables_ready() :: :ok | {:error, term()}
  def ensure_tables_ready do
    with :ok <- ETS.ensure_ready(table: @plain_table),
         :ok <- ETS.ensure_ready(table: @ai_table) do
      :ok
    end
  end

  @spec ensure_runtime_started() :: :ok | {:error, term()}
  def ensure_runtime_started do
    cond do
      runtime_ready?() ->
        :ok

      is_pid(Process.whereis(@runtime_owner)) ->
        restart_runtime_owner()

      true ->
        start_runtime_owner()
    end
  end

  @spec run_plain_agent_demo(keyword()) :: {:ok, map()} | {:error, term()}
  def run_plain_agent_demo(opts \\ []) when is_list(opts) do
    agent_id = Keyword.get(opts, :plain_agent_id, unique_agent_id("plain"))

    with :ok <- ensure_runtime_started(),
         {:ok, pid} <- AgentServer.start_link(agent: JidoAgent, id: agent_id, jido: @jido_instance) do
      try do
        with {:ok, agent_state} <- AgentServer.state(pid),
             agent = agent_state.agent,
             {:ok, _record} <- remember_note(agent, "The BEAM runs Elixir processes efficiently."),
             {:ok, _record} <- remember_note(agent, "Phoenix uses PubSub for message fan-out."),
             signal <- Signal.new!("demo.retrieve", %{query: "beam", limit: 5}, source: "/examples/plain"),
             {:ok, retrieved_agent} <- AgentServer.call(pid, signal) do
          {:ok,
           %{
             agent_id: agent_id,
             retrieved_count: retrieved_agent.state.retrieved_count,
             retrieved_texts: retrieved_agent.state.retrieved_texts,
             namespace: memory_namespace(retrieved_agent),
             plugin: Jido.Memory.BasicPlugin
           }}
        end
      after
        stop_server(pid)
      end
    end
  end

  @spec run_ai_agent_demo(keyword()) :: {:ok, map()} | {:error, term()}
  def run_ai_agent_demo(opts \\ []) when is_list(opts) do
    agent_id = Keyword.get(opts, :ai_agent_id, unique_agent_id("ai"))

    with :ok <- ensure_runtime_started(),
         {:ok, pid} <- AgentServer.start_link(agent: AIEnabledAgent, id: agent_id, jido: @jido_instance) do
      try do
        with {:ok, agent_state} <- AgentServer.state(pid),
             agent = agent_state.agent,
             {:ok, _record} <- remember_note(agent, "Memories are stored in ETS and recalled through Jido.Memory."),
             {:ok, _record} <- remember_note(agent, "The example AI agent exposes memory as a tool."),
             {:ok, tool_result} <-
               Jido.Exec.run(
                 ExecuteTool,
                 %{
                   tool_name: RetrieveNotes.name(),
                   params: %{query: "memory", limit: 5}
                 },
                 %{
                   state: agent.state,
                   tools: [RetrieveNotes]
                 }
               ) do
          memory_result = tool_result.result

          {:ok,
           %{
             agent_id: agent_id,
             tool_name: tool_result.tool_name,
             retrieved_count: Map.get(memory_result, :retrieved_count, 0),
             retrieved_texts: Map.get(memory_result, :retrieved_texts, []),
             memory_result: memory_result,
             namespace: memory_namespace(agent),
             plugins: AIEnabledAgent.plugins()
           }}
        end
      after
        stop_server(pid)
      end
    end
  end

  defp remember_note(agent, text) do
    Runtime.remember(agent, %{
      class: :semantic,
      kind: :fact,
      text: text,
      tags: ["example", "memory"]
    })
  end

  defp unique_agent_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive])}"
  end

  defp start_runtime_owner do
    caller = self()
    ref = make_ref()

    _pid =
      spawn(fn ->
        Process.register(self(), @runtime_owner)

        result =
          case Jido.start(name: @jido_instance, otp_app: :jido_memory) do
            {:ok, _pid} -> :ok
            {:error, reason} -> {:error, reason}
          end

        send(caller, {ref, result})

        receive do
          :stop -> :ok
        end
      end)

    await_runtime_start(ref)
  end

  defp restart_runtime_owner do
    case Process.whereis(@runtime_owner) do
      pid when is_pid(pid) ->
        Process.exit(pid, :kill)
        start_runtime_owner()

      nil ->
        start_runtime_owner()
    end
  end

  defp await_runtime_start(ref) do
    receive do
      {^ref, :ok} ->
        if runtime_ready?(), do: :ok, else: {:error, :runtime_not_ready}

      {^ref, {:error, reason}} ->
        {:error, reason}
    after
      @runtime_start_timeout ->
        {:error, :runtime_start_timeout}
    end
  end

  defp runtime_ready? do
    Enum.all?(
      [
        Process.whereis(@jido_instance),
        Process.whereis(Jido.registry_name(@jido_instance)),
        Process.whereis(Jido.agent_supervisor_name(@jido_instance))
      ],
      &is_pid/1
    )
  end

  defp memory_namespace(%{state: %{__memory__: %{namespace: namespace}}}) when is_binary(namespace),
    do: namespace

  defp memory_namespace(_), do: nil

  defp stop_server(nil), do: :ok

  defp stop_server(pid) when is_pid(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal, 5_000), else: :ok
  end
end
