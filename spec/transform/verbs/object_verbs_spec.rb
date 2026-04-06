# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe "Object Verbs" do
  let(:engine) { Odin::Transform::TransformEngine.new }
  let(:ctx) { Odin::Transform::VerbContext.new }
  let(:dv) { Odin::Types::DynValue }

  def invoke(name, *args)
    engine.invoke_verb(name, args, ctx)
  end

  def make_obj(hash)
    dv.of_object(hash.transform_values { |v| dv.of_string(v.to_s) })
  end

  # ── keys ──

  describe "keys" do
    it "returns keys of an object" do
      obj = dv.of_object({ "a" => dv.of_integer(1), "b" => dv.of_integer(2), "c" => dv.of_integer(3) })
      result = invoke("keys", obj)
      expect(result.array?).to be true
      expect(result.value.map(&:value)).to contain_exactly("a", "b", "c")
    end

    it "returns null for null input" do
      result = invoke("keys", dv.of_null)
      expect(result.null?).to be true
    end

    it "returns empty array for empty object" do
      obj = dv.of_object({})
      result = invoke("keys", obj)
      expect(result.array?).to be true
      expect(result.value).to be_empty
    end

    it "returns string keys" do
      obj = dv.of_object({ "name" => dv.of_string("Alice") })
      result = invoke("keys", obj)
      expect(result.value.first.string?).to be true
    end
  end

  # ── values ──

  describe "values" do
    it "returns values of an object" do
      obj = dv.of_object({ "a" => dv.of_integer(1), "b" => dv.of_integer(2) })
      result = invoke("values", obj)
      expect(result.array?).to be true
      expect(result.value.length).to eq(2)
    end

    it "returns null for null input" do
      result = invoke("values", dv.of_null)
      expect(result.null?).to be true
    end

    it "returns empty array for empty object" do
      obj = dv.of_object({})
      result = invoke("values", obj)
      expect(result.array?).to be true
      expect(result.value).to be_empty
    end

    it "preserves value types" do
      obj = dv.of_object({ "n" => dv.of_integer(42), "s" => dv.of_string("hello") })
      result = invoke("values", obj)
      types = result.value.map(&:type)
      expect(types).to contain_exactly(:integer, :string)
    end
  end

  # ── entries ──

  describe "entries" do
    it "returns array of [key, value] pairs" do
      obj = dv.of_object({ "x" => dv.of_integer(1), "y" => dv.of_integer(2) })
      result = invoke("entries", obj)
      expect(result.array?).to be true
      expect(result.value.length).to eq(2)
      first_entry = result.value.first
      expect(first_entry.array?).to be true
      expect(first_entry.value.length).to eq(2)
      expect(first_entry.value[0].string?).to be true
    end

    it "returns null for null input" do
      result = invoke("entries", dv.of_null)
      expect(result.null?).to be true
    end

    it "returns empty array for empty object" do
      obj = dv.of_object({})
      result = invoke("entries", obj)
      expect(result.array?).to be true
      expect(result.value).to be_empty
    end

    it "pairs contain correct key and value" do
      obj = dv.of_object({ "name" => dv.of_string("Alice") })
      result = invoke("entries", obj)
      pair = result.value.first
      expect(pair.value[0].value).to eq("name")
      expect(pair.value[1].value).to eq("Alice")
    end
  end

  # ── has ──

  describe "has" do
    it "returns true for existing key" do
      obj = dv.of_object({ "name" => dv.of_string("Alice") })
      result = invoke("has", obj, dv.of_string("name"))
      expect(result.value).to be true
    end

    it "returns false for missing key" do
      obj = dv.of_object({ "name" => dv.of_string("Alice") })
      result = invoke("has", obj, dv.of_string("age"))
      expect(result.value).to be false
    end

    it "returns false for null object" do
      result = invoke("has", dv.of_null, dv.of_string("key"))
      expect(result.value).to be false
    end

    it "returns false for empty object" do
      obj = dv.of_object({})
      result = invoke("has", obj, dv.of_string("anything"))
      expect(result.value).to be false
    end

    it "returns boolean type" do
      obj = dv.of_object({ "a" => dv.of_integer(1) })
      result = invoke("has", obj, dv.of_string("a"))
      expect(result.bool?).to be true
    end
  end

  # ── get ──

  describe "get" do
    it "returns value for existing key" do
      obj = dv.of_object({ "name" => dv.of_string("Alice") })
      result = invoke("get", obj, dv.of_string("name"))
      expect(result.value).to eq("Alice")
    end

    it "returns default for missing key" do
      obj = dv.of_object({ "name" => dv.of_string("Alice") })
      result = invoke("get", obj, dv.of_string("age"), dv.of_integer(0))
      expect(result.value).to eq(0)
    end

    it "returns null for missing key without default" do
      obj = dv.of_object({ "name" => dv.of_string("Alice") })
      result = invoke("get", obj, dv.of_string("age"))
      expect(result.null?).to be true
    end

    it "returns default for null object" do
      result = invoke("get", dv.of_null, dv.of_string("key"), dv.of_string("fallback"))
      expect(result.value).to eq("fallback")
    end

    it "returns null for null object without default" do
      result = invoke("get", dv.of_null, dv.of_string("key"))
      expect(result.null?).to be true
    end

    it "returns correct type for integer value" do
      obj = dv.of_object({ "count" => dv.of_integer(42) })
      result = invoke("get", obj, dv.of_string("count"))
      expect(result.integer?).to be true
      expect(result.value).to eq(42)
    end
  end

  # ── merge ──

  describe "merge" do
    it "merges two objects with overlapping keys (second wins)" do
      a = dv.of_object({ "x" => dv.of_integer(1), "y" => dv.of_integer(2) })
      b = dv.of_object({ "y" => dv.of_integer(99), "z" => dv.of_integer(3) })
      result = invoke("merge", a, b)
      expect(result.object?).to be true
      expect(result.get("x")).to eq(dv.of_integer(1))
      expect(result.get("y")).to eq(dv.of_integer(99))
      expect(result.get("z")).to eq(dv.of_integer(3))
    end

    it "merges disjoint objects" do
      a = dv.of_object({ "a" => dv.of_integer(1) })
      b = dv.of_object({ "b" => dv.of_integer(2) })
      result = invoke("merge", a, b)
      expect(result.get("a")).to eq(dv.of_integer(1))
      expect(result.get("b")).to eq(dv.of_integer(2))
    end

    it "merges multiple objects" do
      a = dv.of_object({ "a" => dv.of_integer(1) })
      b = dv.of_object({ "b" => dv.of_integer(2) })
      c = dv.of_object({ "c" => dv.of_integer(3) })
      result = invoke("merge", a, b, c)
      expect(result.get("a")).to eq(dv.of_integer(1))
      expect(result.get("b")).to eq(dv.of_integer(2))
      expect(result.get("c")).to eq(dv.of_integer(3))
    end

    it "skips null arguments" do
      a = dv.of_object({ "a" => dv.of_integer(1) })
      result = invoke("merge", a, dv.of_null)
      expect(result.object?).to be true
      expect(result.get("a")).to eq(dv.of_integer(1))
    end

    it "returns null when all arguments are null" do
      result = invoke("merge", dv.of_null, dv.of_null)
      expect(result.null?).to be true
    end

    it "preserves value types in merged result" do
      a = dv.of_object({ "num" => dv.of_integer(1) })
      b = dv.of_object({ "str" => dv.of_string("hello") })
      result = invoke("merge", a, b)
      expect(result.get("num").integer?).to be true
      expect(result.get("str").string?).to be true
    end

    it "last object wins for all overlapping keys" do
      a = dv.of_object({ "x" => dv.of_integer(1), "y" => dv.of_integer(2) })
      b = dv.of_object({ "x" => dv.of_integer(10), "y" => dv.of_integer(20) })
      result = invoke("merge", a, b)
      expect(result.get("x")).to eq(dv.of_integer(10))
      expect(result.get("y")).to eq(dv.of_integer(20))
    end
  end
end
