defmodule Jido.Memory.Helpers do
  @moduledoc false

  @spec map_get(map(), atom(), term()) :: term()
  def map_get(map, key, default \\ nil)

  def map_get(%{} = map, key, default) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  def map_get(_value, _key, default), do: default

  @spec pick_value(keyword(), map(), atom(), term()) :: term()
  def pick_value(opts, attrs, key, default \\ nil) when is_list(opts) and is_map(attrs) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> value
      :error -> map_get(attrs, key, default)
    end
  end

  @spec plugin_state(map() | struct(), atom()) :: map()
  def plugin_state(%{state: %{} = state}, key), do: plugin_state(state, key)

  def plugin_state(%{} = map, key) do
    case Map.get(map, key) do
      %{} = plugin_state -> plugin_state
      _ -> %{}
    end
  end

  def plugin_state(_target, _key), do: %{}

  @spec target_id(map() | struct()) :: String.t() | nil
  def target_id(%{id: id}) when is_binary(id), do: id
  def target_id(%{agent: %{id: id}}) when is_binary(id), do: id
  def target_id(_target), do: nil

  @spec normalize_map(term()) :: map()
  def normalize_map(%{} = map), do: map
  def normalize_map(_value), do: %{}

  @spec normalize_optional_string(term()) :: String.t() | nil
  def normalize_optional_string(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  def normalize_optional_string(_value), do: nil

  @spec put_opt_if_missing(keyword(), atom(), term()) :: keyword()
  def put_opt_if_missing(opts, _key, nil), do: opts

  def put_opt_if_missing(opts, key, value) when is_list(opts) do
    case Keyword.get(opts, key) do
      nil -> Keyword.put(opts, key, value)
      _ -> opts
    end
  end
end
