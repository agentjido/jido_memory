defmodule SupportDesk.GraphStore do
  @moduledoc false

  alias TripleStore.{Adapter, QuadOperations}

  def iri(name), do: RDF.iri("https://example.test/memory/" <> name)

  def put(store, graph, subject, facts) do
    quads =
      Enum.map(facts, fn {predicate, value} ->
        object = if is_binary(value), do: RDF.literal(value), else: value
        {:ok, [s, p, o, g]} = Adapter.terms_to_ids(store.dict_manager, [subject, predicate, object, graph])
        {s, p, o, g}
      end)

    QuadOperations.insert_quads(store.db, quads, [])
  end

  def facts(store, graph, subject) do
    with {:ok, s} <- Adapter.lookup_term_id(store.db, subject),
         {:ok, g} <- Adapter.lookup_term_id(store.db, graph) do
      store.db
      |> QuadOperations.lookup_quads({:bound, :var, :var, :bound}, %{s: s, g: g})
      |> Enum.map(fn {_s, predicate, object, _g} ->
        {:ok, predicate} = Adapter.id_to_term(store.db, predicate)
        {:ok, object} = Adapter.id_to_term(store.db, object)
        {predicate, object}
      end)
    else
      :not_found -> []
    end
  end
end
