# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe "Extra Array Verbs" do
  let(:engine) { Odin::Transform::TransformEngine.new }
  let(:ctx) { Odin::Transform::VerbContext.new }
  let(:dv) { Odin::Types::DynValue }

  def invoke(name, *args)
    engine.invoke_verb(name, args, ctx)
  end

  def ints(*nums)
    dv.of_array(nums.map { |n| dv.of_integer(n) })
  end

  def values(result)
    result.value.map(&:value)
  end

  # ── intersection ──

  describe "intersection" do
    it "returns deduped common elements in first-array order" do
      result = invoke("intersection", ints(1, 2, 2, 3), ints(2, 3, 4))
      expect(values(result)).to eq([2, 3])
    end

    it "returns a single shared element" do
      result = invoke("intersection", ints(1, 2, 2, 3), ints(3, 5))
      expect(values(result)).to eq([3])
    end

    it "returns empty for fewer than two arrays" do
      expect(invoke("intersection", ints(1, 2)).value).to be_empty
    end
  end

  # ── union ──

  describe "union" do
    it "merges and dedupes preserving first-seen order" do
      result = invoke("union", ints(1, 2, 2), ints(2, 3))
      expect(values(result)).to eq([1, 2, 3])
    end

    it "concatenates disjoint arrays" do
      result = invoke("union", ints(1, 2), ints(3, 4))
      expect(values(result)).to eq([1, 2, 3, 4])
    end

    it "yields the second array when the first is empty" do
      result = invoke("union", dv.of_array([]), ints(2, 3))
      expect(values(result)).to eq([2, 3])
    end
  end

  # ── difference ──

  describe "difference" do
    it "returns deduped elements of a not in b" do
      result = invoke("difference", ints(1, 1, 2, 3), ints(2, 3, 4))
      expect(values(result)).to eq([1])
    end

    it "returns all of a when there is no overlap" do
      result = invoke("difference", ints(1, 2, 3), ints(9, 8))
      expect(values(result)).to eq([1, 2, 3])
    end
  end

  # ── symmetricDifference ──

  describe "symmetricDifference" do
    it "returns elements in exactly one array" do
      result = invoke("symmetricDifference", ints(1, 2, 3), ints(2, 3, 4))
      expect(values(result)).to eq([1, 4])
    end

    it "concatenates disjoint arrays" do
      result = invoke("symmetricDifference", ints(1, 2), ints(3, 4))
      expect(values(result)).to eq([1, 2, 3, 4])
    end

    it "dedupes within each side" do
      result = invoke("symmetricDifference", ints(1, 1, 2), ints(2, 3))
      expect(values(result)).to eq([1, 3])
    end
  end

  # ── countBy ──

  describe "countBy" do
    it "counts by a field, sorting keys" do
      items = dv.of_array([
        dv.of_object({ "region" => dv.of_string("east") }),
        dv.of_object({ "region" => dv.of_string("west") }),
        dv.of_object({ "region" => dv.of_string("east") })
      ])
      result = invoke("countBy", items, dv.of_string("region"))
      expect(result.value.keys).to eq(%w[east west])
      expect(result.get("east").value).to eq(2)
      expect(result.get("west").value).to eq(1)
    end

    it "counts scalar values when no field is given" do
      tags = dv.of_array(%w[a b a a].map { |s| dv.of_string(s) })
      result = invoke("countBy", tags)
      expect(result.get("a").value).to eq(3)
      expect(result.get("b").value).to eq(1)
    end

    it "returns null for a non-array" do
      expect(invoke("countBy", dv.of_string("x")).null?).to be true
    end
  end

  # ── keyBy ──

  describe "keyBy" do
    it "indexes by a field with last-wins on collision" do
      users = dv.of_array([
        dv.of_object({ "id" => dv.of_string("u1"), "name" => dv.of_string("Ada") }),
        dv.of_object({ "id" => dv.of_string("u2"), "name" => dv.of_string("Bo") }),
        dv.of_object({ "id" => dv.of_string("u1"), "name" => dv.of_string("Ada2") })
      ])
      result = invoke("keyBy", users, dv.of_string("id"))
      expect(result.get("u1").get("name").value).to eq("Ada2")
      expect(result.get("u2").get("name").value).to eq("Bo")
    end

    it "returns null for a non-array" do
      expect(invoke("keyBy", dv.of_string("x"), dv.of_string("id")).null?).to be true
    end
  end

  # ── explode ──

  describe "explode" do
    it "expands a row per element of the named array field" do
      orders = dv.of_array([
        dv.of_object({ "id" => dv.of_string("o1"), "tags" => dv.of_array([dv.of_string("red"), dv.of_string("blue")]) })
      ])
      result = invoke("explode", orders, dv.of_string("tags"))
      expect(result.value.length).to eq(2)
      expect(result.value[0].get("tags").value).to eq("red")
      expect(result.value[1].get("tags").value).to eq("blue")
    end

    it "keeps a single row when the field array is empty" do
      orders = dv.of_array([
        dv.of_object({ "id" => dv.of_string("o2"), "tags" => dv.of_array([]) })
      ])
      result = invoke("explode", orders, dv.of_string("tags"))
      expect(result.value.length).to eq(1)
      expect(result.value[0].get("id").value).to eq("o2")
    end

    it "passes rows through when the field is missing" do
      plain = dv.of_array([
        dv.of_object({ "id" => dv.of_string("p1") }),
        dv.of_object({ "id" => dv.of_string("p2") })
      ])
      result = invoke("explode", plain, dv.of_string("tags"))
      expect(result.value.map { |r| r.get("id").value }).to eq(%w[p1 p2])
    end
  end

  # ── window ──

  describe "window" do
    it "produces sliding windows of size n" do
      result = invoke("window", ints(1, 2, 3), dv.of_integer(2))
      expect(result.value.length).to eq(2)
      expect(values(result.value[0])).to eq([1, 2])
      expect(values(result.value[1])).to eq([2, 3])
    end

    it "produces single-element windows for size 1" do
      result = invoke("window", ints(1, 2, 3), dv.of_integer(1))
      expect(result.value.length).to eq(3)
      expect(values(result.value[0])).to eq([1])
    end

    it "returns empty when n exceeds the array length" do
      expect(invoke("window", ints(1, 2), dv.of_integer(5)).value).to be_empty
    end

    it "returns empty for a non-positive size" do
      expect(invoke("window", ints(1, 2, 3), dv.of_integer(0)).value).to be_empty
    end
  end

  # ── countIf / sumIf / avgIf ──

  def orders
    dv.of_array([
      dv.of_object({ "status" => dv.of_string("paid"), "amount" => dv.of_integer(100) }),
      dv.of_object({ "status" => dv.of_string("open"), "amount" => dv.of_integer(200) }),
      dv.of_object({ "status" => dv.of_string("paid"), "amount" => dv.of_integer(300) })
    ])
  end

  describe "countIf" do
    it "counts rows matching the predicate" do
      result = invoke("countIf", orders, dv.of_string("status"), dv.of_string("="), dv.of_string("paid"))
      expect(result.value).to eq(2)
    end

    it "returns 0 when nothing matches" do
      result = invoke("countIf", orders, dv.of_string("status"), dv.of_string("="), dv.of_string("void"))
      expect(result.value).to eq(0)
    end
  end

  describe "sumIf" do
    it "sums a field over matching rows" do
      result = invoke("sumIf", orders, dv.of_string("status"), dv.of_string("="), dv.of_string("paid"), dv.of_string("amount"))
      expect(result.value).to eq(400)
    end

    it "returns 0 when nothing matches" do
      result = invoke("sumIf", orders, dv.of_string("status"), dv.of_string("="), dv.of_string("void"), dv.of_string("amount"))
      expect(result.value).to eq(0)
    end
  end

  describe "avgIf" do
    it "averages a field over matching rows" do
      result = invoke("avgIf", orders, dv.of_string("status"), dv.of_string("="), dv.of_string("paid"), dv.of_string("amount"))
      expect(result.value).to eq(200)
    end

    it "returns null when nothing matches" do
      result = invoke("avgIf", orders, dv.of_string("status"), dv.of_string("="), dv.of_string("void"), dv.of_string("amount"))
      expect(result.null?).to be true
    end
  end
end
