defmodule Jido.Memory.ProviderRegistry do
  @moduledoc """
  Alias registry for canonical memory provider names.

  Core `jido_memory` ships with a stable alias map. External provider packages
  can either rely on those aliases or extend them through application config:

      config :jido_memory, :provider_aliases,
        custom_provider: MyApp.Memory.CustomProvider
  """

  @built_in_aliases %{
    basic: Jido.Memory.Provider.Basic,
    mempalace: Jido.Memory.Provider.MemPalace,
    mem0: Jido.Memory.Provider.Mem0
  }

  @type provider_alias :: atom()

  @doc "Returns the built-in provider alias map."
  @spec built_in_aliases() :: %{optional(provider_alias()) => module()}
  def built_in_aliases, do: @built_in_aliases

  @doc "Returns the merged provider alias map."
  @spec aliases() :: %{optional(provider_alias()) => module()}
  def aliases do
    configured =
      :jido_memory
      |> Application.get_env(:provider_aliases, [])
      |> Enum.into(%{})

    Map.merge(@built_in_aliases, configured)
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
end
