defmodule Jido.Memory.ProviderRegistry do
  @moduledoc """
  Alias registry for canonical memory provider names.

  Core `jido_memory` ships with a hard built-in alias core. External provider
  packages extend that atom-based registry through application config:

      config :jido_memory, :provider_aliases,
        custom_provider: MyApp.Memory.CustomProvider
  """

  @built_in_aliases %{
    basic: Jido.Memory.Provider.Basic
  }

  @type provider_alias :: atom()
  @type aliases_input :: keyword(module()) | map() | nil

  @doc "Returns the built-in provider alias map."
  @spec built_in_aliases() :: %{optional(provider_alias()) => module()}
  def built_in_aliases, do: @built_in_aliases

  @doc "Normalizes alias input into an atom-to-module map."
  @spec normalize_aliases(aliases_input()) :: {:ok, %{optional(provider_alias()) => module()}} | {:error, :invalid_provider_aliases}
  def normalize_aliases(nil), do: {:ok, %{}}

  def normalize_aliases(aliases) when is_list(aliases) do
    aliases
    |> Enum.into(%{})
    |> normalize_aliases()
  rescue
    ArgumentError -> {:error, :invalid_provider_aliases}
  end

  def normalize_aliases(aliases) when is_map(aliases) do
    aliases
    |> Enum.reduce_while({:ok, %{}}, fn
      {alias_name, module}, {:ok, acc} when is_atom(alias_name) and is_atom(module) ->
        {:cont, {:ok, Map.put(acc, alias_name, module)}}

      _entry, _acc ->
        {:halt, {:error, :invalid_provider_aliases}}
    end)
  end

  def normalize_aliases(_aliases), do: {:error, :invalid_provider_aliases}

  @doc "Returns the merged provider alias map."
  @spec aliases() :: %{optional(provider_alias()) => module()}
  def aliases do
    configured =
      :jido_memory
      |> Application.get_env(:provider_aliases, [])
      |> normalize_aliases()
      |> case do
        {:ok, aliases} -> aliases
        {:error, _reason} -> %{}
      end

    Map.merge(configured, @built_in_aliases)
  end

  @doc "Resolves an alias or provider module to a concrete provider module."
  @spec resolve(atom() | module()) :: {:ok, module()} | {:error, term()}
  def resolve(value) when is_atom(value) do
    case Map.fetch(aliases(), value) do
      {:ok, module} -> {:ok, module}
      :error -> {:ok, value}
    end
  end

  @doc "Resolves an alias or provider module, raising on unknown values."
  @spec resolve!(atom() | module()) :: module()
  def resolve!(value) do
    {:ok, module} = resolve(value)
    module
  end

  @doc "Returns true when the value is a registered provider alias."
  @spec alias?(term()) :: boolean()
  def alias?(value) when is_atom(value), do: Map.has_key?(aliases(), value)
  def alias?(_value), do: false

  @doc "Returns the canonical atom key for a provider alias or registered module."
  @spec key_for(atom() | module() | nil) :: provider_alias() | nil
  def key_for(nil), do: nil

  def key_for(value) when is_atom(value) do
    cond do
      alias?(value) ->
        value

      true ->
        aliases()
        |> Enum.sort_by(fn {alias_name, _module} -> Atom.to_string(alias_name) end)
        |> Enum.find_value(fn {alias_name, module} ->
          if module == value, do: alias_name, else: nil
        end)
    end
  end
end
