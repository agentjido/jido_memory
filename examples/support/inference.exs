defmodule SupportDesk.Inference do
  @moduledoc false

  alias ReqLLM.{Context, Response, Tool, ToolCall}

  def from_args!(argv, fixture) do
    case config(argv) do
      :error ->
        %{model: "fixture:support-desk", options: [], generate_text: fixture}

      {:ok, model, options} ->
        %{model: model, options: options, generate_text: &ReqLLM.generate_text/3}
    end
  end

  def agent_config!(argv, fixture) do
    case config(argv) do
      :error -> {%{model: "fixture:support-desk", options: %{}}, %{jido_ai_inference_client: fixture}}
      {:ok, model, options} -> {%{model: model, options: Map.new(options)}, %{}}
    end
  end

  def prepared_trace(context) do
    %{model_input: Enum.map(context.request.context.messages, &trace_message/1), request_digest: context.digest}
  end

  defp config(argv) do
    {options, []} = OptionParser.parse!(argv, strict: [config: :string])

    case Keyword.fetch(options, :config) do
      :error ->
        :error

      {:ok, path} ->
        {config, _bindings} = Code.eval_file(path)
        {:ok, Keyword.fetch!(config, :model), Keyword.get(config, :options, [])}
    end
  end

  def call!(inference, messages) do
    {response, trace} = generate!(inference, messages, [])
    {Response.text(response), trace}
  end

  def tool_round!(inference, messages, tool) do
    {response, call} = generate!(inference, messages, [tool])

    request =
      case Response.tool_calls(response) do
        [request] -> request
        _ -> raise "Expected one request for #{tool.name}, received: #{inspect(Response.text(response))}"
      end

    result =
      case ToolCall.execute(request, [tool]) do
        {:ok, result} -> result
        {:error, _reason} -> %{status: :invalid_request}
      end

    reply = Context.tool_result(request.id, ToolCall.name(request), Jason.encode!(result))
    trace = %{call: call, request: ToolCall.to_map(request), result: result}
    {messages ++ [response.message, reply], trace}
  end

  defp generate!(inference, messages, tools) do
    prompt = Context.new(messages)
    options = Keyword.put(inference.options, :tools, tools)
    started = System.monotonic_time(:microsecond)
    {:ok, response} = inference.generate_text.(inference.model, prompt, options)

    trace = %{
      model: response.model,
      latency_us: System.monotonic_time(:microsecond) - started,
      usage: Response.usage(response),
      model_input: Enum.map(prompt.messages, &trace_message/1),
      tools: Enum.map(tools, &Tool.to_json_schema/1)
    }

    {response, trace}
  end

  defp trace_message(message) do
    traced = %{role: message.role, content: Enum.map_join(message.content, & &1.text)}

    case message do
      %{tool_call_id: id, name: name} when is_binary(id) ->
        Map.merge(traced, %{tool_call_id: id, name: name})

      %{tool_calls: [_ | _] = calls} ->
        Map.put(traced, :tool_calls, Enum.map(calls, &ToolCall.to_map/1))

      _ ->
        traced
    end
  end

  def fixture_reply(model, prompt, answer) do
    {:ok,
     %Response{id: "fixture", model: model, context: prompt, message: Context.assistant(answer), finish_reason: :stop}}
  end

  def fixture_tool_call(model, prompt, name, arguments) do
    call = ToolCall.new("fixture-#{length(prompt.messages)}", name, Jason.encode!(arguments))
    message = Context.assistant("", tool_calls: [call])
    {:ok, %Response{id: "fixture", model: model, context: prompt, message: message}}
  end
end

defmodule SupportDesk.Inference.Fixture do
  @moduledoc false

  defmacro __using__(_opts) do
    quote unquote: false do
      @behaviour Jido.AI.InferenceClient

      @impl true
      def evaluation_models, do: []

      for {name, arity} <- Jido.AI.InferenceClient.behaviour_info(:callbacks),
          {name, arity} not in [generate_text: 3, evaluation_models: 0] do
        @impl true
        def unquote(name)(unquote_splicing(Macro.generate_arguments(arity, __MODULE__))), do: {:error, :not_supported}
      end
    end
  end
end
