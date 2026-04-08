defmodule Jido.Memory.Capabilities do
  @moduledoc """
  Helpers for normalizing and querying structured provider capability maps.
  """

  @default %{
    core: false,
    retrieval: %{
      explainable: false,
      active: false,
      memory_types: false,
      provider_extensions: false
    },
    lifecycle: %{consolidate: false, inspect: false},
    ingestion: %{batch: false, multimodal: false, routed: false, access: :none},
    operations: %{},
    governance: %{protected_memory: false, exact_preservation: false, access: :none},
    hooks: %{}
  }

  @legacy_paths %{
    remember: [:core],
    get: [:core],
    retrieve: [:core],
    forget: [:core],
    prune: [:core],
    ingest: [:ingestion, :batch],
    explain_retrieval: [:retrieval, :explainable],
    consolidate: [:lifecycle, :consolidate]
  }

  @spec default() :: map()
  def default, do: @default

  @spec legacy_paths() :: %{optional(atom()) => [atom()]}
  def legacy_paths, do: @legacy_paths

  @spec normalize(map() | nil) :: map()
  def normalize(nil), do: @default

  def normalize(%{} = capabilities) do
    deep_merge(@default, capabilities)
  end

  @spec from_flat_list([atom()]) :: map()
  def from_flat_list(capabilities) when is_list(capabilities) do
    Enum.reduce(capabilities, @default, fn capability, acc ->
      case Map.get(@legacy_paths, capability) do
        nil -> acc
        path -> put_path(acc, path, true)
      end
    end)
  end

  @spec flatten_supported(map() | nil) :: [atom()]
  def flatten_supported(capabilities) do
    normalized = normalize(capabilities)

    @legacy_paths
    |> Enum.reduce([], fn {capability, path}, acc ->
      if supported?(normalized, path), do: [capability | acc], else: acc
    end)
    |> Enum.reverse()
  end

  @spec supported?(map() | nil, atom() | [atom()]) :: boolean()
  def supported?(capabilities, path) when is_atom(path), do: supported?(capabilities, [path])

  def supported?(capabilities, path) when is_list(path) do
    case get(capabilities, path) do
      value when value in [true, :supported] -> true
      _ -> false
    end
  end

  @spec get(map() | nil, [atom()]) :: term()
  def get(capabilities, path) when is_list(path) do
    Enum.reduce_while(path, normalize(capabilities), fn segment, acc ->
      case acc do
        %{} = map ->
          {:cont, Map.get(map, segment, Map.get(map, Atom.to_string(segment)))}

        _ ->
          {:halt, nil}
      end
    end)
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value) do
        deep_merge(left_value, right_value)
      else
        right_value
      end
    end)
  end

  defp put_path(map, [segment], value) do
    Map.put(map, segment, value)
  end

  defp put_path(map, [segment | rest], value) do
    nested =
      map
      |> Map.get(segment, %{})
      |> case do
        %{} = current -> current
        _ -> %{}
      end

    Map.put(map, segment, put_path(nested, rest, value))
  end
end
