# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe "Extra Object Verbs" do
  let(:engine) { Odin::Transform::TransformEngine.new }
  let(:ctx) { Odin::Transform::VerbContext.new }
  let(:dv) { Odin::Types::DynValue }

  def invoke(name, *args)
    engine.invoke_verb(name, args, ctx)
  end

  def rec
    dv.of_object({
      "name" => dv.of_string("Ada"),
      "role" => dv.of_string("admin"),
      "active" => dv.of_bool(true)
    })
  end

  # ── pick ──

  describe "pick" do
    it "keeps only the named keys, preserving source order" do
      result = invoke("pick", rec, dv.of_string("name"), dv.of_string("role"))
      expect(result.object?).to be true
      expect(result.value.keys).to eq(%w[name role])
      expect(result.get("name").value).to eq("Ada")
    end

    it "skips keys absent from the source" do
      result = invoke("pick", rec, dv.of_string("name"), dv.of_string("zzz"))
      expect(result.value.keys).to eq(%w[name])
    end

    it "returns null for a non-object" do
      expect(invoke("pick", dv.of_string("x"), dv.of_string("name")).null?).to be true
    end

    it "returns null for null input" do
      expect(invoke("pick", dv.of_null, dv.of_string("name")).null?).to be true
    end
  end

  # ── omit ──

  describe "omit" do
    it "drops the named keys, preserving remaining order" do
      result = invoke("omit", rec, dv.of_string("active"))
      expect(result.value.keys).to eq(%w[name role])
    end

    it "ignores keys not present" do
      result = invoke("omit", rec, dv.of_string("zzz"))
      expect(result.value.keys).to eq(%w[name role active])
    end

    it "returns null for a non-object" do
      expect(invoke("omit", dv.of_string("x"), dv.of_string("name")).null?).to be true
    end
  end

  # ── fromEntries ──

  describe "fromEntries" do
    it "builds an object from [key, value] pair arrays" do
      pairs = dv.of_array([
        dv.of_array([dv.of_string("name"), dv.of_string("Ada")]),
        dv.of_array([dv.of_string("role"), dv.of_string("admin")])
      ])
      result = invoke("fromEntries", pairs)
      expect(result.get("name").value).to eq("Ada")
      expect(result.get("role").value).to eq("admin")
    end

    it "returns null for a non-array" do
      expect(invoke("fromEntries", dv.of_string("x")).null?).to be true
    end

    it "returns null for null input" do
      expect(invoke("fromEntries", dv.of_null).null?).to be true
    end
  end

  # ── invert ──

  describe "invert" do
    it "swaps keys and values" do
      m = dv.of_object({ "a" => dv.of_string("x"), "b" => dv.of_string("y") })
      result = invoke("invert", m)
      expect(result.get("x").value).to eq("a")
      expect(result.get("y").value).to eq("b")
    end

    it "last key wins on a value collision" do
      dup = dv.of_object({ "a" => dv.of_string("same"), "b" => dv.of_string("same") })
      result = invoke("invert", dup)
      expect(result.get("same").value).to eq("b")
    end

    it "returns null for a non-object" do
      expect(invoke("invert", dv.of_string("x")).null?).to be true
    end
  end

  # ── defaults ──

  describe "defaults" do
    it "fills only missing keys from the fallback" do
      base = dv.of_object({ "name" => dv.of_string("Ada") })
      fallback = dv.of_object({ "name" => dv.of_string("Anon"), "role" => dv.of_string("guest") })
      result = invoke("defaults", base, fallback)
      expect(result.get("name").value).to eq("Ada")
      expect(result.get("role").value).to eq("guest")
    end

    it "returns the fallback when the first argument is a non-object" do
      fallback = dv.of_object({ "name" => dv.of_string("Anon"), "role" => dv.of_string("guest") })
      result = invoke("defaults", dv.of_string("x"), fallback)
      expect(result.get("name").value).to eq("Anon")
      expect(result.get("role").value).to eq("guest")
    end
  end

  # ── renameKeys ──

  describe "renameKeys" do
    it "renames mapped keys and keeps the rest" do
      src = dv.of_object({ "fn" => dv.of_string("Ada"), "keep" => dv.of_string("as-is") })
      mapping = dv.of_object({ "fn" => dv.of_string("firstName") })
      result = invoke("renameKeys", src, mapping)
      expect(result.get("firstName").value).to eq("Ada")
      expect(result.get("keep").value).to eq("as-is")
    end

    it "returns null for a non-object source" do
      mapping = dv.of_object({ "fn" => dv.of_string("firstName") })
      expect(invoke("renameKeys", dv.of_string("x"), mapping).null?).to be true
    end
  end

  # ── compactObject ──

  describe "compactObject" do
    it "drops null and empty-string values, keeps zero and false" do
      src = dv.of_object({
        "name" => dv.of_string("Ada"),
        "middle" => dv.of_null,
        "nickname" => dv.of_string(""),
        "zero" => dv.of_integer(0),
        "flag" => dv.of_bool(false)
      })
      result = invoke("compactObject", src)
      expect(result.value.keys).to eq(%w[name zero flag])
      expect(result.get("zero").value).to eq(0)
      expect(result.get("flag").value).to be false
    end

    it "returns null for a non-object" do
      expect(invoke("compactObject", dv.of_string("x")).null?).to be true
    end
  end
end
