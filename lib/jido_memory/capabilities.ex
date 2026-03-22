defmodule Jido.Memory.Capabilities do
  @moduledoc """
  Helpers for normalizing and querying provider capability maps.
  """

  @default %{
    core: false,
    retrieval: %{explainable: false, active: false, memory_types: false, provider_extensions: false},
    lifecycle: %{consolidate: false, inspect: false},
    ingestion: %{batch: false, multimodal: false, routed: false, access: :none},
    operations: %{},
    governance: %{protected_memory: false, exact_preservation: false, access: :none},
    hooks: %{}
  }

  @spec default() :: map()
  def default, do: @default

  @spec core_only() :: map()
  def core_only, do: put_in(@default, [:core], true)

  @spec normalize(map() | nil) :: map()
  def normalize(nil), do: @default

  def normalize(%{} = capabilities) do
    deep_merge(@default, capabilities)
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
end
