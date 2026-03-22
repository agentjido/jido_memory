defmodule Jido.Memory.Provider.Mem0 do
  @moduledoc """
  Built-in Mem0-style provider baseline.

  The first cut keeps the canonical `Jido.Memory.Provider` surface and uses the
  existing store-backed core flow while reserving metadata and capabilities for
  later extraction, reconciliation, scoped identity, and graph augmentation
  work.
  """

  @behaviour Jido.Memory.Provider

  alias Jido.Memory.Provider.Basic

  @capabilities %{
    core: true,
    retrieval: %{
      explainable: false,
      active: false,
      memory_types: false,
      provider_extensions: true,
      scoped: true,
      graph_augmentation: false
    },
    lifecycle: %{consolidate: false, inspect: false},
    ingestion: %{batch: false, multimodal: false, routed: false, access: :provider_direct},
    operations: %{feedback: :provider_direct, export: :provider_direct, history: :provider_direct},
    governance: %{protected_memory: false, exact_preservation: false, access: :none},
    hooks: %{}
  }

  @impl true
  def validate_config(opts) when is_list(opts), do: Basic.validate_config(opts)
  def validate_config(_opts), do: {:error, :invalid_provider_opts}

  @impl true
  def child_specs(_opts), do: []

  @impl true
  def init(opts) do
    with :ok <- validate_config(opts),
         {:ok, basic_meta} <- Basic.init(opts) do
      {:ok,
       basic_meta
       |> Map.put(:provider, __MODULE__)
       |> Map.put(:capabilities, @capabilities)
       |> Map.put(:provider_style, :mem0)
       |> Map.put(:topology, %{
         archetype: :extraction_reconciliation,
         retrieval: %{scoped: true, explainable: false, graph_augmentation: false},
         maintenance: %{reconciliation: :provider_direct, feedback: :provider_direct, history: :provider_direct}
       })
       |> Map.put(:scoped_identity, %{
         enabled: false,
         source_precedence: [:runtime_opts, :target, :provider_config],
         supported_dimensions: [:user, :agent, :app, :run]
       })}
    end
  end

  @impl true
  def capabilities(provider_meta), do: Map.get(provider_meta, :capabilities, @capabilities)

  @impl true
  def remember(target, attrs, opts), do: Basic.remember(target, attrs, opts)

  @impl true
  def get(target, id, opts), do: Basic.get(target, id, opts)

  @impl true
  def retrieve(target, query, opts), do: Basic.retrieve(target, query, opts)

  @impl true
  def forget(target, id, opts), do: Basic.forget(target, id, opts)

  @impl true
  def prune(target, opts), do: Basic.prune(target, opts)

  @impl true
  def info(provider_meta, :all), do: {:ok, provider_meta}

  def info(provider_meta, fields) when is_list(fields) do
    {:ok, Map.take(provider_meta, fields)}
  end

  def info(_provider_meta, _fields), do: {:error, :invalid_info_fields}
end
