# frozen_string_literal: true

require "spec_helper"

RSpec.describe Odin::Diff::Patcher do
  let(:differ) { Odin::Diff::Differ.new }
  let(:patcher) { described_class.new }

  def build_doc(&block)
    b = Odin.builder
    block.call(b)
    b.build
  end

  def make_mods(required: false, confidential: false, deprecated: false)
    Odin::Types::OdinModifiers.new(required: required, confidential: confidential, deprecated: deprecated)
  end

  def docs_equal?(a, b)
    a.paths.sort == b.paths.sort &&
      a.paths.all? { |p| a.get(p) == b.get(p) }
  end

  # ── Basic patching ──────────────────────────────────────────

  describe "basic patching" do
    it "patch with only additions" do
      doc = build_doc { |b| b.set_string("name", "John") }
      diff = Odin::Types::OdinDiff.new(
        added: [Odin::Types::DiffEntry.new(path: "age", value: Odin::Types::OdinInteger.new(30))]
      )
      result = patcher.apply_patch(doc, diff)
      expect(result.get("name")).to eq(Odin::Types::OdinString.new("John"))
      expect(result.get("age")).to eq(Odin::Types::OdinInteger.new(30))
    end

    it "patch with only removals" do
      doc = build_doc do |b|
        b.set_string("name", "John")
        b.set_integer("age", 30)
      end
      diff = Odin::Types::OdinDiff.new(
        removed: [Odin::Types::DiffEntry.new(path: "age", value: Odin::Types::OdinInteger.new(30))]
      )
      result = patcher.apply_patch(doc, diff)
      expect(result.get("name")).to eq(Odin::Types::OdinString.new("John"))
      expect(result.get("age")).to be_nil
    end

    it "patch with only changes" do
      doc = build_doc { |b| b.set_string("name", "John") }
      diff = Odin::Types::OdinDiff.new(
        changed: [Odin::Types::DiffChange.new(
          path: "name",
          old_value: Odin::Types::OdinString.new("John"),
          new_value: Odin::Types::OdinString.new("Jane")
        )]
      )
      result = patcher.apply_patch(doc, diff)
      expect(result.get("name")).to eq(Odin::Types::OdinString.new("Jane"))
    end

    it "patch with only moves" do
      doc = build_doc { |b| b.set_string("oldField", "value") }
      diff = Odin::Types::OdinDiff.new(
        moved: [Odin::Types::DiffMove.new(
          from_path: "oldField",
          to_path: "newField",
          value: Odin::Types::OdinString.new("value")
        )]
      )
      result = patcher.apply_patch(doc, diff)
      expect(result.get("oldField")).to be_nil
      expect(result.get("newField")).to eq(Odin::Types::OdinString.new("value"))
    end

    it "patch with mixed operations" do
      doc = build_doc do |b|
        b.set_string("name", "John")
        b.set_integer("age", 30)
        b.set_string("city", "Austin")
      end
      diff = Odin::Types::OdinDiff.new(
        changed: [Odin::Types::DiffChange.new(
          path: "name",
          old_value: Odin::Types::OdinString.new("John"),
          new_value: Odin::Types::OdinString.new("Jane")
        )],
        removed: [Odin::Types::DiffEntry.new(path: "age", value: Odin::Types::OdinInteger.new(30))],
        added: [Odin::Types::DiffEntry.new(path: "state", value: Odin::Types::OdinString.new("TX"))]
      )
      result = patcher.apply_patch(doc, diff)
      expect(result.get("name")).to eq(Odin::Types::OdinString.new("Jane"))
      expect(result.get("age")).to be_nil
      expect(result.get("city")).to eq(Odin::Types::OdinString.new("Austin"))
      expect(result.get("state")).to eq(Odin::Types::OdinString.new("TX"))
    end

    it "patch preserves modifiers on unchanged fields" do
      mods = make_mods(required: true)
      doc = build_doc do |b|
        b.set_string("name", "John", modifiers: mods)
        b.set_integer("age", 30)
      end
      diff = Odin::Types::OdinDiff.new(
        removed: [Odin::Types::DiffEntry.new(path: "age", value: Odin::Types::OdinInteger.new(30))]
      )
      result = patcher.apply_patch(doc, diff)
      expect(result.modifiers_for("name")).to eq(mods)
    end

    it "patch applies modifier changes" do
      old_mods = make_mods(required: true)
      new_mods = make_mods(confidential: true)
      doc = build_doc { |b| b.set_string("field", "val", modifiers: old_mods) }
      diff = Odin::Types::OdinDiff.new(
        changed: [Odin::Types::DiffChange.new(
          path: "field",
          old_value: Odin::Types::OdinString.new("val"),
          new_value: Odin::Types::OdinString.new("val"),
          old_modifiers: old_mods,
          new_modifiers: new_mods
        )]
      )
      result = patcher.apply_patch(doc, diff)
      expect(result.modifiers_for("field")).to eq(new_mods)
    end

    it "patch with addition including modifiers" do
      mods = make_mods(required: true)
      doc = Odin::Types::OdinDocument.empty
      diff = Odin::Types::OdinDiff.new(
        added: [Odin::Types::DiffEntry.new(
          path: "name",
          value: Odin::Types::OdinString.new("John"),
          modifiers: mods
        )]
      )
      result = patcher.apply_patch(doc, diff)
      expect(result.get("name")).to eq(Odin::Types::OdinString.new("John"))
      expect(result.modifiers_for("name")).to eq(mods)
    end

    it "patch preserves metadata" do
      b = Odin.builder
      b.set_string("name", "John")
      b.set_metadata("odin", "1.0.0")
      doc = b.build

      diff = Odin::Types::OdinDiff.new(
        changed: [Odin::Types::DiffChange.new(
          path: "name",
          old_value: Odin::Types::OdinString.new("John"),
          new_value: Odin::Types::OdinString.new("Jane")
        )]
      )
      result = patcher.apply_patch(doc, diff)
      expect(result.metadata_value("odin")).to eq("1.0.0")
    end
  end

  # ── Roundtrip ───────────────────────────────────────────────

  describe "roundtrip: patch(a, diff(a, b)) == b" do
    it "roundtrip with string change" do
      a = build_doc { |b| b.set_string("name", "John") }
      b = build_doc { |bd| bd.set_string("name", "Jane") }
      d = differ.compute_diff(a, b)
      result = patcher.apply_patch(a, d)
      expect(docs_equal?(result, b)).to be true
    end

    it "roundtrip with addition" do
      a = build_doc { |b| b.set_string("name", "John") }
      b = build_doc do |bd|
        bd.set_string("name", "John")
        bd.set_integer("age", 30)
      end
      d = differ.compute_diff(a, b)
      result = patcher.apply_patch(a, d)
      expect(docs_equal?(result, b)).to be true
    end

    it "roundtrip with removal" do
      a = build_doc do |b|
        b.set_string("name", "John")
        b.set_integer("age", 30)
      end
      b = build_doc { |bd| bd.set_string("name", "John") }
      d = differ.compute_diff(a, b)
      result = patcher.apply_patch(a, d)
      expect(docs_equal?(result, b)).to be true
    end

    it "roundtrip with move" do
      a = build_doc { |b| b.set_string("oldField", "value") }
      b = build_doc { |bd| bd.set_string("newField", "value") }
      d = differ.compute_diff(a, b)
      result = patcher.apply_patch(a, d)
      expect(docs_equal?(result, b)).to be true
    end

    it "roundtrip with all value types" do
      a = build_doc do |b|
        b.set_string("str", "hello")
        b.set_integer("int", 42)
        b.set_number("num", 3.14)
        b.set_boolean("bool", true)
        b.set_null("nil")
        b.set_currency("price", 99.99, currency_code: "USD")
      end
      b = build_doc do |bd|
        bd.set_string("str", "world")
        bd.set_integer("int", 100)
        bd.set_number("num", 2.71)
        bd.set_boolean("bool", false)
        bd.set_null("nil")
        bd.set_currency("price", 149.99, currency_code: "EUR")
      end
      d = differ.compute_diff(a, b)
      result = patcher.apply_patch(a, d)
      expect(docs_equal?(result, b)).to be true
    end

    it "roundtrip with modifiers" do
      a = build_doc { |b| b.set_string("name", "John") }
      b = build_doc { |bd| bd.set_string("name", "John", modifiers: make_mods(required: true)) }
      d = differ.compute_diff(a, b)
      result = patcher.apply_patch(a, d)
      expect(result.get("name")).to eq(b.get("name"))
      expect(result.modifiers_for("name")).to eq(b.modifiers_for("name"))
    end

    it "roundtrip with arrays" do
      a = build_doc do |b|
        b.set_string("items[0]", "first")
        b.set_string("items[1]", "second")
      end
      b = build_doc do |bd|
        bd.set_string("items[0]", "first")
        bd.set_string("items[1]", "third")
        bd.set_string("items[2]", "fourth")
      end
      d = differ.compute_diff(a, b)
      result = patcher.apply_patch(a, d)
      expect(docs_equal?(result, b)).to be true
    end

    it "roundtrip with mixed operations" do
      a = build_doc do |b|
        b.set_string("name", "John")
        b.set_integer("age", 30)
        b.set_string("city", "Austin")
      end
      b = build_doc do |bd|
        bd.set_string("name", "Jane")
        bd.set_string("state", "TX")
      end
      d = differ.compute_diff(a, b)
      result = patcher.apply_patch(a, d)
      expect(docs_equal?(result, b)).to be true
    end

    it "roundtrip with nested paths" do
      a = build_doc do |b|
        b.set_string("person.name", "John")
        b.set_string("person.address.city", "Austin")
      end
      b = build_doc do |bd|
        bd.set_string("person.name", "Jane")
        bd.set_string("person.address.city", "Dallas")
        bd.set_string("person.address.state", "TX")
      end
      d = differ.compute_diff(a, b)
      result = patcher.apply_patch(a, d)
      expect(docs_equal?(result, b)).to be true
    end

    it "roundtrip: empty diff produces identical document" do
      doc = build_doc do |b|
        b.set_string("name", "John")
        b.set_integer("age", 30)
      end
      d = differ.compute_diff(doc, doc)
      result = patcher.apply_patch(doc, d)
      expect(docs_equal?(result, doc)).to be true
    end
  end

  # ── Edge cases ──────────────────────────────────────────────

  describe "edge cases" do
    it "empty diff produces identical document" do
      doc = build_doc { |b| b.set_string("name", "John") }
      diff = Odin::Types::OdinDiff.new
      result = patcher.apply_patch(doc, diff)
      expect(docs_equal?(result, doc)).to be true
    end

    it "patching empty document with additions" do
      doc = Odin::Types::OdinDocument.empty
      diff = Odin::Types::OdinDiff.new(
        added: [
          Odin::Types::DiffEntry.new(path: "name", value: Odin::Types::OdinString.new("John")),
          Odin::Types::DiffEntry.new(path: "age", value: Odin::Types::OdinInteger.new(30))
        ]
      )
      result = patcher.apply_patch(doc, diff)
      expect(result.get("name")).to eq(Odin::Types::OdinString.new("John"))
      expect(result.get("age")).to eq(Odin::Types::OdinInteger.new(30))
    end

    it "patch that removes all fields" do
      doc = build_doc do |b|
        b.set_string("name", "John")
        b.set_integer("age", 30)
      end
      diff = Odin::Types::OdinDiff.new(
        removed: [
          Odin::Types::DiffEntry.new(path: "name", value: Odin::Types::OdinString.new("John")),
          Odin::Types::DiffEntry.new(path: "age", value: Odin::Types::OdinInteger.new(30))
        ]
      )
      result = patcher.apply_patch(doc, diff)
      expect(result.paths).to be_empty
    end

    it "patch that changes everything" do
      doc = build_doc do |b|
        b.set_string("name", "John")
        b.set_integer("age", 30)
      end
      diff = Odin::Types::OdinDiff.new(
        changed: [
          Odin::Types::DiffChange.new(
            path: "name",
            old_value: Odin::Types::OdinString.new("John"),
            new_value: Odin::Types::OdinString.new("Jane")
          ),
          Odin::Types::DiffChange.new(
            path: "age",
            old_value: Odin::Types::OdinInteger.new(30),
            new_value: Odin::Types::OdinInteger.new(25)
          )
        ]
      )
      result = patcher.apply_patch(doc, diff)
      expect(result.get("name")).to eq(Odin::Types::OdinString.new("Jane"))
      expect(result.get("age")).to eq(Odin::Types::OdinInteger.new(25))
    end

    it "multiple patches in sequence" do
      doc = build_doc { |b| b.set_string("name", "John") }

      diff1 = differ.compute_diff(
        doc,
        build_doc { |b| b.set_string("name", "Jane") }
      )
      result1 = patcher.apply_patch(doc, diff1)
      expect(result1.get("name")).to eq(Odin::Types::OdinString.new("Jane"))

      target2 = build_doc do |b|
        b.set_string("name", "Jane")
        b.set_integer("age", 25)
      end
      diff2 = differ.compute_diff(result1, target2)
      result2 = patcher.apply_patch(result1, diff2)
      expect(result2.get("name")).to eq(Odin::Types::OdinString.new("Jane"))
      expect(result2.get("age")).to eq(Odin::Types::OdinInteger.new(25))
    end

    it "move preserves modifiers from source" do
      mods = make_mods(required: true)
      doc = build_doc { |b| b.set_string("old", "val", modifiers: mods) }
      b = build_doc { |bd| bd.set_string("new", "val", modifiers: mods) }
      d = differ.compute_diff(doc, b)
      result = patcher.apply_patch(doc, d)
      expect(result.get("new")).to eq(Odin::Types::OdinString.new("val"))
      expect(result.modifiers_for("new")).to eq(mods)
    end

    it "patch result is a new document (not same object)" do
      doc = build_doc { |b| b.set_string("name", "John") }
      diff = Odin::Types::OdinDiff.new
      result = patcher.apply_patch(doc, diff)
      expect(result).not_to equal(doc)
    end

    it "roundtrip with only modifier change preserves value" do
      a = build_doc { |b| b.set_string("f", "v") }
      b = build_doc { |bd| bd.set_string("f", "v", modifiers: make_mods(deprecated: true)) }
      d = differ.compute_diff(a, b)
      result = patcher.apply_patch(a, d)
      expect(result.get("f")).to eq(Odin::Types::OdinString.new("v"))
      expect(result.modifiers_for("f")).to eq(make_mods(deprecated: true))
    end
  end
end
