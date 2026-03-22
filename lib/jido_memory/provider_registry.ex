defmodule Jido.Memory.ProviderRegistry do
  @moduledoc """
  Helper APIs for built-in and optional external provider aliases.

  `jido_memory` always ships the built-in `:basic` and `:tiered` aliases. Any
  additional aliases are opt-in and can be passed explicitly through
  `provider_aliases` in plugin config or runtime opts.

  This registry is intentionally helper-only: direct provider modules and direct
  `{module, opts}` tuples continue to work without registration.
  """

  alias Jido.Memory.Provider.Basic
  alias Jido.Memory.Provider.Tiered

  @type aliases_input :: keyword(module()) | map() | nil
  @type aliases :: %{optional(atom()) => module()}

  @built_in_aliases %{
    basic: Basic,
    tiered: Tiered
  }

  @spec built_in_aliases() :: aliases()
  def built_in_aliases, do: @built_in_aliases

  @spec normalize_aliases(aliases_input()) :: {:ok, aliases()} | {:error, :invalid_provider_aliases}
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
      {alias_name, module}, {:ok, acc} ->
        with {:ok, normalized_alias} <- normalize_alias(alias_name),
             {:ok, normalized_module} <- normalize_module(module) do
          {:cont, {:ok, Map.put(acc, normalized_alias, normalized_module)}}
        else
          :error -> {:halt, {:error, :invalid_provider_aliases}}
        end
    end)
  end

  def normalize_aliases(_aliases), do: {:error, :invalid_provider_aliases}

  @spec registered(aliases_input()) :: {:ok, aliases()} | {:error, :invalid_provider_aliases}
  def registered(extra_aliases \\ nil) do
    with {:ok, extra_aliases} <- normalize_aliases(extra_aliases) do
      {:ok, Map.merge(@built_in_aliases, extra_aliases)}
    end
  end

  @spec resolve_alias(atom(), aliases_input()) ::
          {:ok, module()} | :error | {:error, :invalid_provider_aliases}
  def resolve_alias(alias_name, extra_aliases \\ nil)

  def resolve_alias(alias_name, extra_aliases) when is_atom(alias_name) do
    with {:ok, aliases} <- registered(extra_aliases) do
      case Map.fetch(aliases, alias_name) do
        {:ok, module} -> {:ok, module}
        :error -> :error
      end
    end
  end

  def resolve_alias(_alias_name, _extra_aliases), do: :error

  defp normalize_alias(alias_name) when is_atom(alias_name), do: {:ok, alias_name}
  defp normalize_alias(_alias_name), do: :error

  defp normalize_module(module) when is_atom(module), do: {:ok, module}
  defp normalize_module(_module), do: :error
end
