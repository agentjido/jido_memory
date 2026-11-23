defmodule SupportDesk.PalaceSnapshot do
  @moduledoc false
  use Jido.Action, name: "palace_snapshot", schema: Jido.Joi.object(%{})

  @impl true
  def run(_input, %{handoff: %{palace: options}}) do
    with {:ok, snapshot} <- Jido.Memory.MemPalace.wake_up(%{}, options), do: {:ok, %{snapshot: snapshot}}
  end
end

defmodule SupportDesk.OpenPalaceDrawer do
  @moduledoc false
  use Jido.Action, name: "open_palace_drawer", schema: Jido.Joi.object(%{id: Jido.Joi.string()})

  @impl true
  def run(%{id: id}, %{handoff: %{palace: options}}) do
    with {:ok, record} <- Jido.Memory.Provider.MemPalace.get(%{}, id, options), do: {:ok, %{record: record}}
  end
end

defmodule SupportDesk.PalaceFacts do
  @moduledoc false
  alias Jido.Joi

  use Jido.Action,
    name: "palace_facts",
    schema: Joi.object(%{subject: Joi.string(), effective_on: Joi.string()})

  @impl true
  def run(%{subject: subject, effective_on: date}, %{palace: options}) do
    with {:ok, facts} <- Jido.Memory.MemPalace.graph_query(%{}, [subject: subject, as_of: date] ++ options) do
      {:ok, %{facts: facts}}
    end
  end
end

defmodule SupportDesk.PalaceTaxonomy do
  @moduledoc false
  use Jido.Action, name: "palace_taxonomy", schema: Jido.Joi.object(%{})

  @impl true
  def run(_input, %{palace: options}) do
    with {:ok, taxonomy} <- Jido.Memory.MemPalace.taxonomy(%{}, options), do: {:ok, %{wings: taxonomy.wings}}
  end
end

defmodule SupportDesk.SearchPalaceRooms do
  @moduledoc false
  alias Jido.Joi

  use Jido.Action,
    name: "search_palace_rooms",
    schema: Joi.object(%{term: Joi.string(), placement: Joi.map() |> Joi.default(%{})})

  @impl true
  def run(%{term: term, placement: placement}, %{palace: options}) do
    query = %{text_contains: term, extensions: %{"mempalace" => placement}}

    with {:ok, result} <- Jido.Memory.Provider.MemPalace.retrieve(%{}, query, options) do
      {:ok, %{hits: result.hits}}
    end
  end
end
