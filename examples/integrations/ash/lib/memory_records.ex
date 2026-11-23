defmodule JidoMemory.Examples.Ash.SameTenant do
  @moduledoc false
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_options), do: "the actor belongs to the current tenant"

  @impl true
  def match?(%{tenant: tenant}, %{subject: %{tenant: tenant}}, _options) when is_binary(tenant), do: true
  def match?(_actor, _context, _options), do: false
end

defmodule JidoMemory.Examples.Ash.MemoryRecord do
  @moduledoc false

  require Ash.Query

  use Ash.Resource,
    domain: JidoMemory.Examples.Ash.MemoryRecords,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  multitenancy do
    strategy(:attribute)
    attribute(:tenant_id)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:tenant_id, :string, allow_nil?: false)
    attribute(:collection, :string, public?: true, allow_nil?: false)
    attribute(:key, :string, public?: true, allow_nil?: false)
    attribute(:value, :map, public?: true, allow_nil?: false)
    attribute(:source_signal_id, :string, public?: true, allow_nil?: false)
    update_timestamp(:updated_at, public?: true)
  end

  identities do
    identity(:scoped_key, [:collection, :key], pre_check_with: JidoMemory.Examples.Ash.MemoryRecords)
  end

  actions do
    defaults([:read, :destroy])

    create :put do
      accept([:collection, :key, :value, :source_signal_id])
      upsert?(true)
      upsert_identity(:scoped_key)
      upsert_fields([:value, :source_signal_id, :updated_at])
    end

    read :query do
      argument(:collection, :string, allow_nil?: false)
      argument(:where, :map, allow_nil?: false)
      filter(expr(collection == ^arg(:collection)))
      prepare(&filter_values/2)
      prepare(build(sort: [updated_at: :desc, key: :asc]))
      pagination(offset?: true, required?: false)
    end
  end

  policies do
    policy always() do
      forbid_unless(JidoMemory.Examples.Ash.SameTenant)
      authorize_if(always())
    end

    policy action_type(:read) do
      authorize_if(actor_attribute_equals(:may_read, true))
    end

    policy action_type([:create, :destroy]) do
      authorize_if(actor_attribute_equals(:may_write, true))
    end
  end

  defp filter_values(query, _context) do
    case Ash.Query.get_argument(query, :where) do
      %{summary: summary} -> Ash.Query.filter(query, value[:summary] == ^summary)
      %{} -> query
    end
  end
end

defmodule JidoMemory.Examples.Ash.MemoryRecords do
  @moduledoc false

  use Ash.Domain, extensions: [AshJido]

  resources do
    resource JidoMemory.Examples.Ash.MemoryRecord do
      define(:put_memory, action: :put)
      define(:get_memory, action: :read, get_by: [:collection, :key])
      define(:query_memory, action: :query)
      define(:delete_memory, action: :destroy, get_by: [:collection, :key])
    end
  end

  jido do
    expose(:put_memory, select: [:key, :value, :source_signal_id])
    expose(:get_memory, select: [:key, :value, :source_signal_id])

    expose(:query_memory,
      select: [:key, :value, :source_signal_id],
      pagination: [type: :offset, max_page_size: 100]
    )

    expose(:delete_memory)
  end
end
