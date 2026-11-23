defmodule JidoMemory.Examples.Ash.Article do
  @moduledoc false

  use Ash.Resource,
    domain: JidoMemory.Examples.Ash.Articles,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  multitenancy do
    strategy(:attribute)
    attribute(:tenant_id)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:tenant_id, :string, allow_nil?: false)
    attribute(:key, :string, public?: true, allow_nil?: false)
    attribute(:revision, :integer, public?: true, allow_nil?: false)
    attribute(:status, :string, public?: true, allow_nil?: false)
    attribute(:body, :string, public?: true, allow_nil?: false)
    attribute(:internal_note, :string, sensitive?: true)
  end

  actions do
    defaults([:read])

    read :browse do
      prepare(build(sort: [key: :asc]))
      pagination(offset?: true, required?: false)
    end

    create :create do
      primary?(true)
      accept([:key, :revision, :status, :body, :internal_note])
    end

    update :update do
      primary?(true)
      accept([:revision, :status])
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

    policy action_type([:create, :update]) do
      authorize_if(actor_attribute_equals(:role, :admin))
    end
  end
end

defmodule JidoMemory.Examples.Ash.Articles do
  @moduledoc false
  use Ash.Domain, extensions: [AshJido]

  resources do
    resource JidoMemory.Examples.Ash.Article do
      define(:list_articles, action: :browse)
      define(:read_article, action: :read, get_by: [:key])
    end
  end

  jido do
    expose(:list_articles,
      select: [:key, :revision, :status, :body],
      filters: [:status],
      pagination: [type: :offset, max_page_size: 10]
    )

    expose(:read_article, select: [:key, :revision, :status, :body])
  end
end
