defmodule JidoMemory.Examples.Ash.Refund do
  @moduledoc false

  use Ash.Resource,
    domain: JidoMemory.Examples.Ash.Refunds,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  multitenancy do
    strategy(:attribute)
    attribute(:tenant_id)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:tenant_id, :string, allow_nil?: false)
    attribute(:ticket_key, :string, public?: true, allow_nil?: false)
    attribute(:amount_cents, :integer, public?: true, allow_nil?: false)
    attribute(:currency, :string, public?: true, allow_nil?: false)
    attribute(:revision, :integer, public?: true, allow_nil?: false)
    attribute(:processor_note, :string, sensitive?: true)
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:ticket_key, :amount_cents, :currency, :revision, :processor_note])
    end

    update :correct do
      primary?(true)
      accept([:amount_cents, :revision])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if(actor_attribute_equals(:role, :support))
    end

    policy action_type([:create, :update]) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end
  end
end

defmodule JidoMemory.Examples.Ash.Refunds do
  @moduledoc false

  use Ash.Domain, extensions: [AshJido]

  resources do
    resource JidoMemory.Examples.Ash.Refund do
      define(:read_refund, action: :read, get_by: [:ticket_key])
    end
  end

  jido do
    expose(:read_refund, select: [:ticket_key, :amount_cents, :currency, :revision])
  end
end
