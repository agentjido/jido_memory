defmodule JidoMemory.Examples.Ash.Account do
  @moduledoc false

  use Ash.Resource,
    domain: JidoMemory.Examples.Ash.Accounts,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  multitenancy do
    strategy(:attribute)
    attribute(:tenant_id)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:tenant_id, :string, allow_nil?: false)
    attribute(:account_key, :string, public?: true, allow_nil?: false)
    attribute(:refund_eligible, :boolean, public?: true, allow_nil?: false)
    attribute(:revision, :integer, public?: true, allow_nil?: false)
    attribute(:internal_note, :string, sensitive?: true)
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:account_key, :refund_eligible, :revision, :internal_note])
    end

    update :update do
      primary?(true)
      accept([:refund_eligible, :revision])
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

defmodule JidoMemory.Examples.Ash.Accounts do
  @moduledoc false

  use Ash.Domain, extensions: [AshJido]

  resources do
    resource JidoMemory.Examples.Ash.Account do
      define(:read_account, action: :read, get_by: [:account_key])
    end
  end

  jido do
    expose(:read_account, select: [:account_key, :refund_eligible, :revision])
  end
end
