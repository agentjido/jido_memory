defmodule Jido.Memory.IntegrationBindingsTest do
  use ExUnit.Case, async: true

  alias Jido.{Joi, Memory}
  alias Jido.Memory.Plugin

  defmodule ReadAccount do
    use Jido.Action, name: "read_integration_account", schema: Joi.object(%{key: Joi.string()})

    @impl true
    def run(%{key: key}, %{tenant: tenant}), do: {:ok, %{key: key, tenant: tenant}}
  end

  defmodule IndexLookup do
    use Jido.Flow,
      name: "lookup_integration_index",
      schema: Joi.object(%{key: Joi.string()})

    flow do
      step("read", action: ReadAccount, params: input())
      output(result("read"))
    end
  end

  defmodule SelectOperation do
    use Jido.Action, name: "select_test_memory_operation", schema: Joi.object(%{key: Joi.string()})

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule InvokeIndex do
    use Jido.Action, name: "invoke_test_memory_index", schema: Joi.object(%{key: Joi.string()})

    @impl true
    def run(params, context) do
      with {:ok, target} <- Memory.operation(context, :index, :accounts, :search) do
        {:continue, params, target}
      end
    end
  end

  defmodule Review do
    use Jido.Flow, name: "review_bound_evidence", schema: Joi.object(%{key: Joi.string()})

    flow do
      await("approved", event: "test.memory.approved", match: %{key: input(:key)})
      output(result("approved"))
    end
  end

  defmodule SelectReview do
    use Jido.Action, name: "select_test_memory_review", schema: Joi.object(%{key: Joi.string()})

    @impl true
    def run(params, context) do
      with {:ok, target} <- Memory.operation(context, :index, :accounts, :review) do
        {:handoff, params, target}
      end
    end
  end

  defmodule BeginReview do
    use Jido.Flow, name: "begin_bound_review", schema: Joi.object(%{key: Joi.string()})

    flow do
      handoff("review", selector: SelectReview, params: input())
      output(result("review"))
    end
  end

  defmodule RetrieveEvidence do
    alias Jido.Memory.Actions.Access

    use Jido.Flow,
      name: "retrieve_bound_evidence",
      schema: Joi.object(%{key: Joi.string()}),
      output_schema: Joi.object(%{trace: Joi.map()})

    flow do
      step("source", action: Access, params: %{kind: :source, name: :accounts, operation: :read, input: input()})
      invoke("index", decision: SelectOperation, expander: InvokeIndex, params: input())
      step("graph", action: Access, params: %{kind: :graph, name: :relations, operation: :lookup, input: input()})

      output(%{trace: %{source: result("source"), index: result("index"), graph: result("graph")}})
    end
  end

  defmodule Agent do
    use Jido.Agent, name: "memory_integration_test", plugins: [Plugin]

    memory do
      source(:accounts, operations: [read: ReadAccount])
      index(:accounts, operations: [search: IndexLookup, review: Review])
      graph(:relations, operations: [lookup: ReadAccount])
    end

    routes do
      signal_source("/tests/memory/integration")

      route "test.memory.collect", RetrieveEvidence, as: :collect do
        state(:unchanged)
        reply("test.memory.evidence", from: output(:trace))
      end

      route "test.memory.review", BeginReview, as: :review do
        state(:unchanged)
      end
    end
  end

  test "a Turn uses the Agent's bindings and delivers trusted context to the target" do
    agent = Agent.instantiate!(id: "support")
    signal = Agent.collect_signal!(%{key: "AC-17"})
    expected = %{key: "AC-17", tenant: "north"}

    assert {:ok, _agent, [%{signal: %{data: trace}}]} = Agent.cmd(agent, signal, context: %{tenant: "north"})
    assert trace == %{source: expected, index: expected, graph: expected}
  end

  test "an unavailable operation fails before any target runs" do
    assert {:error, {:memory_operation_unavailable, :source, :accounts, :read}} =
             Memory.access(%{}, :source, :accounts, :read, %{key: "AC-17"})
  end

  test "immediate access directs Flow bindings to native invocation" do
    context = %{plugin_inputs: %{Plugin => %{prepared: %{bindings: %{index: %{accounts: %{search: IndexLookup}}}}}}}

    assert {:error, :memory_operation_requires_flow_dispatch} =
             Memory.access(context, :index, :accounts, :search, %{key: "AC-17"})
  end

  test "a bound Flow that waits can start as a durable root through a handoff" do
    instance = __MODULE__.Runtime

    start_supervised!(
      {Jido,
       name: instance,
       namespace: "tests/memory/integration",
       persistence: {Jido.Persistence.ETS, table: __MODULE__.Store}}
    )

    agent = Agent.instantiate!(id: "support-review")
    signal = Agent.review_signal!(%{key: "AC-17"})

    assert {:handoff, _agent, %Jido.Instruction{target: Review} = successor, []} = Agent.cmd(agent, signal)

    assert {:ok, %{state: :waiting, waits: [%{id: wait_id}], ref: ref}} =
             Jido.Durable.start(instance, successor, signal)

    approval = Jido.Signal.new!("test.memory.approved", %{key: "AC-17"}, source: "/tests/memory/integration")
    assert {:ok, %{state: :completed}} = Jido.Durable.signal(instance, ref, wait_id, approval)
  end

  test "invalid binding targets and empty operation maps fail during configuration" do
    assert {:error, _} = Plugin.normalize(%{collections: %{}, bindings: %{source: %{accounts: %{read: String}}}})
    assert {:error, _} = Plugin.normalize(%{collections: %{}, bindings: %{source: %{accounts: %{}}}})
  end
end
