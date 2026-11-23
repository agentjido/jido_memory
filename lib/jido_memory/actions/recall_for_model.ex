defmodule Jido.Memory.Actions.RecallForModel do
  @moduledoc """
  Projects an Agent's granted memory into an open Jido AI model context.

  Place the Action after `ProjectConversation` and before `CallModel`. The
  Agent's read grant sets the collection, filters, exposed fields, and result
  limit. The grant applies when its Flow is the sole matching root route.

  Set `max_evidence_bytes` to bound the appended message, including its header
  and JSON punctuation. It defaults to 4,096 bytes. The recall trace retains
  the granted records and lists the records omitted from the message. Use
  `Jido.Memory.Actions.RecallGranted` to format evidence in your Flow.
  """

  alias Jido.AI.Context
  alias Jido.Joi
  alias Jido.Memory.Actions.RecallGranted

  @evidence_header "Memory evidence (retrieved records):\n"
  @default_max_evidence_bytes 4_096

  use Jido.Action,
    name: "jido_memory_recall_for_model",
    schema:
      Joi.extend(RecallGranted.schema(), %{
        context: Context.schema(),
        max_evidence_bytes: Joi.integer() |> Joi.min(0) |> Joi.default(@default_max_evidence_bytes)
      }),
    output_schema: Joi.object(%{context: Context.schema(), recall: Joi.map()})

  @impl true
  def run(params, context) do
    limit = Map.get(params, :max_evidence_bytes, @default_max_evidence_bytes)

    with {:ok, %{recall: recall}} <- RecallGranted.run(params, context),
         {evidence, omitted} = fit_evidence(recall.records, limit),
         {:ok, model_context} <- add_evidence(params.context, recall.grant, evidence) do
      {:ok, %{context: model_context, recall: Map.put(recall, :omitted, omitted)}}
    end
  end

  defp fit_evidence(records, limit) do
    available = limit - byte_size(@evidence_header) - 2

    {parts, omitted, _remaining} =
      Enum.reduce(records, {[], [], available}, fn record, {parts, omitted, remaining} ->
        case encode_record(record, remaining, parts != []) do
          {:ok, json, bytes} ->
            {[json | parts], omitted, remaining - bytes}

          {:error, reason} ->
            {parts, [%{key: record.key, reason: reason} | omitted], remaining}
        end
      end)

    {Enum.reverse(parts), Enum.reverse(omitted)}
  end

  defp encode_record(_record, remaining, _separator?) when remaining <= 0, do: {:error, :evidence_budget}

  defp encode_record(record, remaining, separator?) do
    case Jason.encode(Map.take(record, [:key, :value])) do
      {:ok, json} ->
        bytes = byte_size(json) + if(separator?, do: 1, else: 0)
        if bytes <= remaining, do: {:ok, json, bytes}, else: {:error, :evidence_budget}

      {:error, _} ->
        {:error, :not_json_encodable}
    end
  end

  defp add_evidence(context, _grant, []), do: {:ok, context}

  defp add_evidence(context, grant, parts) do
    json = IO.iodata_to_binary(["[", Enum.intersperse(parts, ","), "]"])
    digest = Base.encode16(:crypto.hash(:sha256, json), case: :lower)

    Context.transform(context, "memory:#{grant}:#{digest}", fn prompt ->
      ReqLLM.Context.append(prompt, ReqLLM.Context.user(@evidence_header <> json))
    end)
  end
end
