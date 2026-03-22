defmodule Jido.Memory.Query do
  @moduledoc """
  Normalized query shape for memory retrieval.

  v1 focuses on structured filters only. Semantic/vector search is intentionally
  deferred while keeping schema room for future RAG features.
  """

  alias Jido.Memory.Record

  @default_limit 20
  @default_order :desc

  @schema Zoi.struct(
            __MODULE__,
            %{
              namespace: Zoi.string(description: "Logical namespace") |> Zoi.optional(),
              classes: Zoi.list(Zoi.atom(), description: "Class filters") |> Zoi.default([]),
              kinds: Zoi.list(Zoi.any(), description: "Open kind filters") |> Zoi.default([]),
              tags_any: Zoi.list(Zoi.string(), description: "Match at least one tag") |> Zoi.default([]),
              tags_all: Zoi.list(Zoi.string(), description: "Match all tags") |> Zoi.default([]),
              text_contains: Zoi.string(description: "Case-insensitive text substring") |> Zoi.optional(),
              since: Zoi.integer(description: "Start timestamp in milliseconds") |> Zoi.optional(),
              until: Zoi.integer(description: "End timestamp in milliseconds") |> Zoi.optional(),
              limit: Zoi.integer(description: "Maximum result count") |> Zoi.default(@default_limit),
              order:
                Zoi.atom(description: "Sort order by observed_at")
                |> Zoi.default(@default_order)
            },
            coerce: true
          )

  @type order :: :asc | :desc
  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the query schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Builds and normalizes a query."
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    with {:ok, namespace} <- normalize_namespace(get_attr(attrs, :namespace)),
         {:ok, classes} <- normalize_classes(get_attr(attrs, :classes, [])),
         {:ok, kinds} <- normalize_kinds(get_attr(attrs, :kinds, [])),
         {:ok, tags_any} <- normalize_tags(get_attr(attrs, :tags_any, [])),
         {:ok, tags_all} <- normalize_tags(get_attr(attrs, :tags_all, [])),
         {:ok, text_contains} <- normalize_text_filter(get_attr(attrs, :text_contains)),
         {:ok, since} <- normalize_optional_time(get_attr(attrs, :since)),
         {:ok, until} <- normalize_optional_time(get_attr(attrs, :until)),
         {:ok, limit} <- normalize_limit(get_attr(attrs, :limit, @default_limit)),
         {:ok, order} <- normalize_order(get_attr(attrs, :order, @default_order)) do
      {:ok,
       struct!(__MODULE__, %{
         namespace: namespace,
         classes: classes,
         kinds: kinds,
         tags_any: tags_any,
         tags_all: tags_all,
         text_contains: text_contains,
         since: since,
         until: until,
         limit: limit,
         order: order
       })}
    end
  end

  def new(_attrs), do: {:error, :invalid_query}

  @doc "Builds and normalizes a query, raising on error."
  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, query} -> query
      {:error, reason} -> raise ArgumentError, "invalid memory query: #{inspect(reason)}"
    end
  end

  @doc "Returns true when query requires a namespace."
  @spec namespace_required?(t()) :: boolean()
  def namespace_required?(%__MODULE__{namespace: namespace}), do: is_nil(namespace)

  @doc "Returns normalized kind keys for comparisons."
  @spec kind_keys(t()) :: [String.t()]
  def kind_keys(%__MODULE__{kinds: kinds}) do
    Enum.map(kinds, &Record.kind_key/1)
  end

  @doc "Returns lowercase text filter, or nil when disabled."
  @spec downcased_text_filter(t()) :: String.t() | nil
  def downcased_text_filter(%__MODULE__{text_contains: nil}), do: nil

  def downcased_text_filter(%__MODULE__{text_contains: text}),
    do: String.downcase(text)

  @spec normalize_namespace(term()) :: {:ok, String.t() | nil} | {:error, term()}
  defp normalize_namespace(nil), do: {:ok, nil}

  defp normalize_namespace(namespace) when is_binary(namespace) do
    trimmed = String.trim(namespace)
    if trimmed == "", do: {:ok, nil}, else: {:ok, trimmed}
  end

  defp normalize_namespace(namespace) when is_atom(namespace),
    do: {:ok, Atom.to_string(namespace)}

  defp normalize_namespace(other), do: {:error, {:invalid_namespace, other}}

  @spec normalize_classes(term()) :: {:ok, [Record.class()]} | {:error, term()}
  defp normalize_classes(classes) when is_list(classes) do
    normalize_unique(classes, &Record.normalize_class/1, & &1)
  end

  defp normalize_classes(nil), do: {:ok, []}
  defp normalize_classes(other), do: {:error, {:invalid_classes, other}}

  @spec normalize_kinds(term()) :: {:ok, [Record.kind()]} | {:error, term()}
  defp normalize_kinds(kinds) when is_list(kinds) do
    normalize_unique(kinds, &Record.normalize_kind/1, &Record.kind_key/1)
  end

  defp normalize_kinds(nil), do: {:ok, []}
  defp normalize_kinds(other), do: {:error, {:invalid_kinds, other}}

  defp normalize_unique(values, normalizer, key_fun) do
    values
    |> Enum.reduce_while({[], MapSet.new()}, fn value, {acc, seen} ->
      case normalizer.(value) do
        {:ok, normalized} ->
          {:cont, maybe_track_unique(normalized, acc, seen, key_fun)}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, _} = error -> error
      {normalized, _seen} -> {:ok, normalized}
    end
  end

  defp maybe_track_unique(normalized, acc, seen, key_fun) do
    key = key_fun.(normalized)

    if MapSet.member?(seen, key) do
      {acc, seen}
    else
      {acc ++ [normalized], MapSet.put(seen, key)}
    end
  end

  @spec normalize_tags(term()) :: {:ok, [String.t()]} | {:error, term()}
  defp normalize_tags(tags), do: Record.normalize_tags(tags)

  @spec normalize_text_filter(term()) :: {:ok, String.t() | nil} | {:error, term()}
  defp normalize_text_filter(nil), do: {:ok, nil}

  defp normalize_text_filter(text) when is_binary(text) do
    trimmed = String.trim(text)
    if trimmed == "", do: {:ok, nil}, else: {:ok, trimmed}
  end

  defp normalize_text_filter(other), do: {:error, {:invalid_text_filter, other}}

  @spec normalize_optional_time(term()) :: {:ok, integer() | nil} | {:error, term()}
  defp normalize_optional_time(nil), do: {:ok, nil}
  defp normalize_optional_time(value) when is_integer(value), do: {:ok, value}
  defp normalize_optional_time(other), do: {:error, {:invalid_timestamp, other}}

  @spec normalize_limit(term()) :: {:ok, pos_integer()} | {:error, term()}
  defp normalize_limit(limit) when is_integer(limit) and limit > 0 do
    {:ok, min(limit, 1000)}
  end

  defp normalize_limit(_), do: {:ok, @default_limit}

  @spec normalize_order(term()) :: {:ok, order()} | {:error, term()}
  defp normalize_order(:asc), do: {:ok, :asc}
  defp normalize_order(:desc), do: {:ok, :desc}
  defp normalize_order("asc"), do: {:ok, :asc}
  defp normalize_order("desc"), do: {:ok, :desc}
  defp normalize_order(nil), do: {:ok, @default_order}
  defp normalize_order(other), do: {:error, {:invalid_order, other}}

  @spec get_attr(map(), atom(), term()) :: term()
  defp get_attr(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
