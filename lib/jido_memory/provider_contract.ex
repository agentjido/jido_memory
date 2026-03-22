defmodule Jido.Memory.ProviderContract do
  @moduledoc """
  Helper functions for verifying canonical memory providers.

  This module is intended for provider contract tests across repositories.
  """

  alias Jido.Memory.Capabilities
  alias Jido.Memory.ProviderRef
  alias Jido.Memory.Runtime

  @type provider_input :: ProviderRef.t() | module() | {module(), keyword()} | nil

  @spec provider_ref(provider_input()) :: {:ok, ProviderRef.t()} | {:error, term()}
  def provider_ref(provider), do: ProviderRef.normalize(provider)

  @spec provider_meta(provider_input()) :: {:ok, map()} | {:error, term()}
  def provider_meta(provider) do
    with {:ok, provider_ref} <- provider_ref(provider) do
      provider_ref.module.init(provider_ref.opts)
    end
  end

  @spec capabilities(provider_input()) :: {:ok, map()} | {:error, term()}
  def capabilities(provider) do
    with {:ok, provider_ref} <- provider_ref(provider),
         {:ok, provider_meta} <- provider_ref.module.init(provider_ref.opts) do
      {:ok, provider_ref.module.capabilities(provider_meta) |> Capabilities.normalize()}
    end
  end

  @spec supports?(provider_input(), atom() | [atom()]) :: boolean()
  def supports?(provider, capability_path) do
    case capabilities(provider) do
      {:ok, capabilities} -> Capabilities.supported?(capabilities, capability_path)
      {:error, _reason} -> false
    end
  end

  @spec canonical_explanation?(map()) :: boolean()
  def canonical_explanation?(%{} = explanation) do
    Map.has_key?(explanation, :provider) and
      Map.has_key?(explanation, :namespace) and
      Map.has_key?(explanation, :query) and
      Map.has_key?(explanation, :result_count) and
      Map.has_key?(explanation, :results) and
      Map.has_key?(explanation, :extensions)
  end

  def canonical_explanation?(_explanation), do: false

  @type core_flow_result :: %{
          record: Jido.Memory.Record.t(),
          fetched: Jido.Memory.Record.t(),
          records: [Jido.Memory.Record.t()],
          deleted?: boolean()
        }

  @spec exercise_core_flow(provider_input(), map() | struct(), map(), map() | keyword(), keyword()) ::
          {:ok, core_flow_result()} | {:error, term()}
  def exercise_core_flow(provider, target, attrs, query, runtime_opts \\ [])
      when is_map(attrs) and is_list(runtime_opts) do
    runtime_opts = Keyword.put(runtime_opts, :provider, provider)

    with {:ok, record} <- Runtime.remember(target, attrs, runtime_opts),
         {:ok, fetched} <- Runtime.get(target, record.id, runtime_opts),
         {:ok, records} <- Runtime.retrieve(target, query, runtime_opts),
         {:ok, deleted?} <- Runtime.forget(target, record.id, runtime_opts) do
      {:ok, %{record: record, fetched: fetched, records: records, deleted?: deleted?}}
    end
  end
end
