defmodule Jido.Memory.QueryTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Query

  test "builds normalized queries and exposes helpers" do
    assert {:ok, %Query{} = query} =
             Query.new(%{
               namespace: " agent:test ",
               classes: [:semantic, "semantic", :working],
               kinds: [:fact, "fact", "event"],
               tags_any: ["beam", "beam", "erlang"],
               tags_all: ["memory", "runtime"],
               text_contains: " Beam ",
               since: 10,
               until: 20,
               limit: 5000,
               order: "asc",
               extensions: %{provider: "hint"}
             })

    assert query.namespace == "agent:test"
    assert query.classes == [:semantic, :working]
    assert query.kinds == [:fact, "event"]
    assert query.tags_any == ["beam", "erlang"]
    assert query.tags_all == ["memory", "runtime"]
    assert query.text_contains == "Beam"
    assert query.limit == 1000
    assert query.order == :asc
    assert Query.kind_keys(query) == ["fact", "event"]
    assert Query.downcased_text_filter(query) == "beam"
    refute Query.namespace_required?(query)
  end

  test "defaults namespace order limit and optional fields" do
    assert {:ok, %Query{} = query} = Query.new(%{})

    assert query.namespace == nil
    assert query.classes == []
    assert query.kinds == []
    assert query.limit == 20
    assert query.order == :desc
    assert Query.namespace_required?(query)
    assert Query.downcased_text_filter(query) == nil
  end

  test "normalizes nils and invalid limit to defaults" do
    assert {:ok, %Query{limit: 20, order: :desc, tags_any: [], tags_all: []}} =
             Query.new(%{
               namespace: "",
               classes: nil,
               kinds: nil,
               tags_any: nil,
               tags_all: nil,
               text_contains: "   ",
               limit: "bad",
               order: nil,
               extensions: nil
             })
  end

  test "validates invalid query inputs" do
    assert {:error, {:invalid_namespace, 123}} = Query.new(%{namespace: 123})
    assert {:error, {:invalid_class, "bad"}} = Query.new(%{classes: ["bad"]})
    assert {:error, {:invalid_classes, :bad}} = Query.new(%{classes: :bad})
    assert {:error, {:invalid_kind, ""}} = Query.new(%{kinds: [""]})
    assert {:error, {:invalid_kinds, :bad}} = Query.new(%{kinds: :bad})
    assert {:error, {:invalid_tag, 123}} = Query.new(%{tags_any: [123]})
    assert {:error, {:invalid_text_filter, 123}} = Query.new(%{text_contains: 123})
    assert {:error, {:invalid_timestamp, :bad}} = Query.new(%{since: :bad})
    assert {:error, {:invalid_order, :sideways}} = Query.new(%{order: :sideways})
    assert {:error, {:invalid_extensions, :bad}} = Query.new(%{extensions: :bad})
    assert {:error, :invalid_query} = Query.new(:bad)
    assert_raise ArgumentError, ~r/invalid memory query/, fn -> Query.new!(%{order: :sideways}) end
  end
end
