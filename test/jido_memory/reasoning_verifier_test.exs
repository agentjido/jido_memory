defmodule Jido.Memory.ReasoningVerifierTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Reasoning.ReAct
  alias Jido.Memory.Plugin

  @collection """
  collection :resolutions, max_entries: 3 do
    schema(Jido.Joi.object(%{issue: Jido.Joi.string(), summary: Jido.Joi.string()}))
  end
  """

  @memory """
  memory do
    #{@collection}
  end
  """

  @binding """
  memory do
    index :guides, operations: [search: Jido.AI.Reasoning.Actions.ProjectConversation]
  end
  """

  @use_core """
  use Jido.Agent, name: "reasoning_memory", plugins: [Jido.AI.Agent.Plugin, Jido.Memory.Plugin]
  import Jido.AI.Agent.Plugin, only: [ai: 1, reasoning: 1]
  """

  @remember_route """
  routes do
    signal_source("/tests/memory/reasoning")

    route "memory.resolve", as: :resolve do
      action _params, schema: Jido.Joi.map(), context: context do
        value = %{issue: "duplicate charge", summary: "Refunded"}
        {:ok, context.agent_state, [Jido.Memory.remember(:resolutions, "T-17", value)]}
      end
    end
  end
  """

  test "reports one source warning when the reasoning Flow has no explicit memory step" do
    {module, file, warnings} = compile_agent(use: @use_core, body: @memory <> @remember_route)

    assert [%{severity: :warning, message: message, file: source}] = warnings
    assert Path.expand(source) == file
    assert message =~ inspect(module)
    assert message =~ inspect(ReAct)
    assert message =~ "has no recognized memory step"
    assert message =~ "RecallForModel"
    assert message =~ "warn_unwired_reasoning false"

    assert_quiet_memory_route(module)
  end

  test "an Agent can use memory on an FSM route without AI" do
    state_machine = """
    state_machine do
      initial :open
      terminal :resolved
      transition :resolve, from: :open, route: :resolve, to: :resolved
    end
    """

    {module, _file, warnings} =
      compile_agent(
        use: """
        use Jido.Agent, name: "memory_only",
          plugins: [Jido.Agent.Plugin.FSM, Jido.Memory.Plugin]
        """,
        ai: "",
        body: @memory <> @remember_route <> state_machine
      )

    assert warnings == []
    assert %{state: %{fsm: %{current: :resolved}}} = assert_quiet_memory_route(module)
  end

  test "an AI Agent with no memory is quiet" do
    assert {_, _, []} = compile_agent(use: "use Jido.AI.Agent, name: \"ai_only\"")
  end

  test "an Agent can suppress the warning in the memory section" do
    body = String.replace(@memory, "memory do", "memory do\nwarn_unwired_reasoning false")
    assert {module, _, []} = compile_agent(use: @use_core, body: body <> @remember_route)

    assert %{data: %{collections: _} = data} = Enum.find(module.definition().plugins, &(&1.provider == Plugin))
    refute Map.has_key?(data, :warn_unwired_reasoning)
    assert_quiet_memory_route(module)
  end

  test "finds explicit plugin configuration on a core Agent with the AI plugin" do
    use_core = """
    use Jido.Agent, name: "configured_memory",
      plugins: [
        Jido.AI.Agent.Plugin,
        {Jido.Memory.Plugin, %{collections: %{resolutions: %{
          schema: Jido.Joi.object(%{summary: Jido.Joi.string()}), max_entries: 3
        }}}}
      ]

    import Jido.AI.Agent.Plugin, only: [ai: 1, reasoning: 1]

    routes do
      signal_source("/tests/memory/reasoning")
    end
    """

    assert {_, _, [%{message: message}]} = compile_agent(use: use_core)
    assert message =~ "has no recognized memory step"
  end

  test "finds a memory definition that consists only of a binding" do
    assert {_, _, [%{message: message}]} = compile_agent(body: @binding)
    assert message =~ "has no recognized memory step"
  end

  test "a reasoning Flow with an explicit recall is quiet" do
    flow = compile_flow(recall_step("grant: :prior_resolutions"))
    assert {_, _, []} = compile_agent(flow: flow, body: memory_for(flow))
  end

  test "a reasoning Flow with declared Access is quiet" do
    flow = compile_flow(access_step("kind: :index, name: :guides, operation: :search"))
    assert {_, _, []} = compile_agent(flow: flow, body: @binding)
  end

  test "reports a literal Access operation bound to a Flow" do
    flow = compile_flow(access_step("kind: :index, name: :guides, operation: :search"))

    binding = """
    memory do
      index :guides, operations: [search: Jido.AI.Reasoning.ReAct]
    end
    """

    assert {_, _, [%{message: message}]} = compile_agent(flow: flow, body: binding)
    assert message =~ ~s(step "lookup")
    assert message =~ "requires an Action"
    assert message =~ "invoke"
  end

  test "recognizes a granted recall that supplies records to a custom formatter" do
    flow =
      compile_flow("""
      step("recall", action: Jido.Memory.Actions.RecallGranted, params: %{grant: :prior_resolutions})
      """)

    assert {_, _, []} = compile_agent(flow: flow, body: memory_for(flow))
  end

  test "reports an unknown read grant" do
    flow = compile_flow(recall_step("grant: :misspelled"))

    assert {_, _, [%{message: message}]} = compile_agent(flow: flow, body: memory_for(flow))
    assert message =~ ~s(step "recall")
    assert message =~ "unknown read grant :misspelled"
  end

  test "reports a grant bound to a different root Flow" do
    flow = compile_flow(recall_step("grant: :prior_resolutions"))

    assert {_, _, [%{message: message}]} = compile_agent(flow: flow, body: memory_for(ReAct))
    assert message =~ ":prior_resolutions"
    assert message =~ "are bound to #{inspect(ReAct)}"
  end

  test "reports an undeclared literal filter key even when the value is dynamic" do
    flow = compile_flow(recall_step("grant: :prior_resolutions, where: %{internal_note: input(:note)}"))

    assert {_, _, [%{message: message}]} = compile_agent(flow: flow, body: memory_for(flow))
    assert message =~ "filter keys [:internal_note]"
    assert message =~ ":prior_resolutions"
  end

  test "leaves dynamic grant and filter choices to runtime" do
    for options <- [
          "grant: input(:grant)",
          "grant: :prior_resolutions, where: input(:where)",
          "grant: :prior_resolutions, where: %{issue: input(:issue)}",
          "grant: :misspelled, enabled: false"
        ] do
      flow = compile_flow(recall_step(options))
      assert {_, _, []} = compile_agent(flow: flow, body: memory_for(flow))
    end
  end

  test "reports unknown literal binding and operation names" do
    for {params, expected} <- [
          {"kind: :index, name: :missing, operation: :search", "unknown memory index :missing"},
          {"kind: :index, name: :guides, operation: :missing", "does not declare operation :missing"}
        ] do
      flow = compile_flow(access_step(params))

      assert {_, _, [%{message: message}]} = compile_agent(flow: flow, body: @binding)
      assert message =~ ~s(step "lookup")
      assert message =~ expected
    end
  end

  test "leaves a dynamic named operation choice to runtime" do
    flow = compile_flow(access_step("kind: :index, name: :guides, operation: input(:operation)"))
    assert {_, _, []} = compile_agent(flow: flow, body: @binding)
  end

  test "reports only the first invalid step by name" do
    flow =
      compile_flow(
        recall_step("grant: :missing") <> "\n" <> access_step("kind: :graph, name: :missing, operation: :search")
      )

    assert {_, _, [%{message: message}]} = compile_agent(flow: flow, body: memory_for(flow))
    assert message =~ ~s(step "lookup")
  end

  test "reports when the model reads the original context and recall only feeds the trace" do
    flow = compile_context_flow()

    assert {_, _, [%{message: message}]} = compile_agent(flow: flow, body: memory_for(flow))
    assert message =~ ~s(step "model")
    assert message =~ ~s(bypasses the context from step "recall")
  end

  test "an ordering dependency on recall does not pass its context to the model" do
    flow = compile_context_flow(model_options: ~s(, needs: ["recall"]))

    assert {_, _, [%{message: message}]} = compile_agent(flow: flow, body: memory_for(flow))
    assert message =~ "bypasses the context"
  end

  test "a model can use the recall context or a context built from recalled records" do
    direct = compile_context_flow(context: ~s|result("recall", :context)|)
    assert {_, _, []} = compile_agent(flow: direct, body: memory_for(direct))

    fit = """
    step "fit", recall <- result("recall", :recall) do
      {:ok, %{context: %{evidence: recall.records}}}
    end
    """

    transformed = compile_context_flow(before_model: fit, context: ~s|result("fit", :context)|)
    assert {_, _, []} = compile_agent(flow: transformed, body: memory_for(transformed))
  end

  test "follows result references through intermediate steps before warning" do
    prepare_turn = """
    step "fit", recall <- result("recall", :recall) do
      {:ok, %{records: recall.records}}
    end

    step "prepare_turn", fit <- result("fit") do
      {:ok, %{turn: %{evidence: fit.records}}}
    end
    """

    flow = compile_context_flow(before_model: prepare_turn, turn: ~s|result("prepare_turn", :turn)|)
    assert {_, _, []} = compile_agent(flow: flow, body: memory_for(flow))
  end

  test "keeps conditional recall and multi-call reasoning quiet" do
    conditional = compile_context_flow(recall: "grant: :prior_resolutions, enabled: input(:recall)")
    assert {_, _, []} = compile_agent(flow: conditional, body: memory_for(conditional))

    revise = """
    step("revise", action: CallModel, params: %{turn: result("model", :turn), context: result("recall", :context)})
    """

    multi_call = compile_context_flow(after_model: revise)
    assert {_, _, []} = compile_agent(flow: multi_call, body: memory_for(multi_call))
  end

  test "reports a literal error before the model context bypass" do
    flow = compile_context_flow(recall: "grant: :misspelled")
    body = memory_for(flow)

    assert {_, _, [%{message: message}]} = compile_agent(flow: flow, body: body)
    assert message =~ "unknown read grant :misspelled"

    suppressed = String.replace(body, " do\n", " do\nwarn_unwired_reasoning false\n", global: false)
    assert {_, _, []} = compile_agent(flow: flow, body: suppressed)
  end

  test "invalid memory definitions still raise a compile error" do
    assert_raise Spark.Error.DslError, ~r/Declare at least one memory collection, source, index, or graph/, fn ->
      compile_agent()
    end
  end

  test "the memory DSL rejects duplicate declarations and duplicate operations" do
    flow = compile_flow(access_step("kind: :index, name: :guides, operation: :search"))
    target = "Jido.AI.Reasoning.Actions.ProjectConversation"
    declaration = "index :guides, operations: [search: #{target}]"

    for {declarations, error} <- [
          {@collection <> @collection, ~r/Memory collection names must be unique/},
          {"#{declaration}\n#{declaration}", ~r/Duplicate memory index :guides/},
          {"index :guides, operations: [search: #{target}, search: #{target}]",
           ~r/Duplicate operation for memory index/}
        ] do
      assert_raise Spark.Error.DslError, error, fn ->
        compile_agent(flow: flow, body: "memory do\n#{declarations}\nend")
      end
    end
  end

  defp compile_context_flow(opts \\ []) do
    original_context = ~s|result("project", :context)|
    recall = recall_step(Keyword.get(opts, :recall, "grant: :prior_resolutions"), original_context)
    context = Keyword.get(opts, :context, original_context)
    turn = Keyword.get(opts, :turn, ~s|result("project", :turn)|)

    compile_flow(
      """
      step("project", action: ProjectConversation, params: %{turn: input(:turn)})
      #{recall}
      #{Keyword.get(opts, :before_model, "")}

      step("model", action: CallModel, params: %{turn: #{turn}, context: #{context}}#{Keyword.get(opts, :model_options, "")})
      #{Keyword.get(opts, :after_model, "")}

      step "trace", [model <- result("model"), recall <- result("recall", :recall)] do
        {:ok, %{model: model, recall: recall}}
      end
      """,
      ~s|%{state: %{}, response: %{trace: result("trace")}}|
    )
  end

  defp compile_flow(steps, output \\ "%{state: %{}, response: %{}}") do
    suffix = System.unique_integer([:positive])
    module = Module.concat(__MODULE__, "Flow#{suffix}")
    file = Path.expand("reasoning_verifier_flow_#{suffix}.exs", __DIR__)

    Code.compile_string(
      """
      defmodule #{inspect(module)} do
        alias Jido.Joi
        alias Jido.AI.Reasoning.Actions.{CallModel, ProjectConversation}, warn: false
        alias Jido.Memory.Actions.{Access, RecallForModel}, warn: false

        use Jido.Flow,
          name: "reasoning_warning_test_flow",
          schema: Joi.map(),
          output_schema: Joi.object(%{state: Joi.map(), response: Joi.map()})

        flow do
          #{steps}
          output(#{output})
        end
      end
      """,
      file
    )

    module
  end

  defp recall_step(params, context \\ "input(:context)") do
    ~s|step("recall", action: RecallForModel, params: %{context: #{context}, #{params}})|
  end

  defp access_step(params) do
    ~s|step("lookup", action: Access, params: %{#{params}})|
  end

  defp memory_for(flow) do
    """
    memory #{inspect(flow)} do
      #{@collection}
      read(:prior_resolutions, collection: :resolutions, filters: [:issue], expose: [:summary], limit: 1)
    end
    """
  end

  defp compile_agent(opts \\ []) do
    suffix = System.unique_integer([:positive])
    module = Module.concat(__MODULE__, "Agent#{suffix}")
    file = Path.expand("reasoning_verifier_agent_#{suffix}.exs", __DIR__)
    use_agent = Keyword.get(opts, :use, ~s(use Jido.AI.Agent, name: "reasoning_memory", plugins: [Jido.Memory.Plugin]))
    ai = Keyword.get(opts, :ai, "ai do\nreasoning #{inspect(Keyword.get(opts, :flow, ReAct))}\nend")
    body = Keyword.get(opts, :body, "")

    source = """
    defmodule #{inspect(module)} do
      #{use_agent}
      #{ai}
      #{body}
    end
    """

    {_compiled, diagnostics} = Code.with_diagnostics(fn -> Code.compile_string(source, file) end)
    {module, file, wiring_warnings(diagnostics)}
  end

  defp assert_quiet_memory_route(module) do
    {result, diagnostics} =
      Code.with_diagnostics(fn ->
        module.definition()
        agent = module.instantiate!(id: "warning-test")
        module.cmd(agent, module.resolve_signal!(%{}))
      end)

    assert {:ok, agent, [_]} = result
    assert [%{key: "T-17", value: %{summary: "Refunded"}}] = agent.state.memory.resolutions
    assert wiring_warnings(diagnostics) == []
    agent
  end

  defp wiring_warnings(diagnostics) do
    Enum.filter(diagnostics, &String.starts_with?(&1.message, "[Jido.Memory]"))
  end
end
