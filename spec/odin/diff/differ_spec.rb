# frozen_string_literal: true

require "spec_helper"

RSpec.describe Odin::Diff::Differ do
  let(:differ) { described_class.new }

  def build_doc(&block)
    b = Odin.builder
    block.call(b)
    b.build
  end

  def make_mods(required: false, confidential: false, deprecated: false)
    Odin::Types::OdinModifiers.new(required: required, confidential: confidential, deprecated: deprecated)
  end

  # ── Empty diff ──────────────────────────────────────────────

  describe "empty diff" do
    it "identical single-field documents produce empty diff" do
      doc = build_doc { |b| b.set_string("name", "John") }
      d = differ.compute_diff(doc, doc)
      expect(d).to be_empty
    end

    it "two empty documents produce empty diff" do
      a = Odin::Types::OdinDocument.empty
      b = Odin::Types::OdinDocument.empty
      d = differ.compute_diff(a, b)
      expect(d).to be_empty
    end

    it "same single assignment produces empty diff" do
      a = build_doc { |b| b.set_integer("count", 42) }
      b = build_doc { |b| b.set_integer("count", 42) }
      d = differ.compute_diff(a, b)
      expect(d).to be_empty
    end

    it "same multiple assignments produce empty diff" do
      a = build_doc do |b|
        b.set_string("name", "John")
        b.set_integer("age", 30)
        b.set_boolean("active", true)
      end
      b = build_doc do |b|
        b.set_string("name", "John")
        b.set_integer("age", 30)
        b.set_boolean("active", true)
      end
      d = differ.compute_diff(a, b)
      expect(d).to be_empty
    end

    it "same value with same modifiers produces empty diff" do
      a = build_doc { |b| b.set_string("name", "John", modifiers: make_mods(required: true)) }
      b = build_doc { |b| b.set_string("name", "John", modifiers: make_mods(required: true)) }
      d = differ.compute_diff(a, b)
      expect(d).to be_empty
    end
  end

  # ── Additions ───────────────────────────────────────────────

  describe "additions" do
    it "detects one field added" do
      a = build_doc { |b| b.set_string("name", "John") }
      b = build_doc do |bd|
        bd.set_string("name", "John")
        bd.set_integer("age", 30)
      end
      d = differ.compute_diff(a, b)
      expect(d.added.length).to eq(1)
      expect(d.added[0].path).to eq("age")
      expect(d.added[0].value).to eq(Odin::Types::OdinInteger.new(30))
    end

    it "detects multiple fields added" do
      a = build_doc { |b| b.set_string("name", "John") }
      b = build_doc do |bd|
        bd.set_string("name", "John")
        bd.set_integer("age", 30)
        bd.set_string("city", "Austin")
      end
      d = differ.compute_diff(a, b)
      expect(d.added.length).to eq(2)
      expect(d.added.map(&:path)).to contain_exactly("age", "city")
    end

    it "detects array element added" do
      a = build_doc { |b| b.set_string("items[0]", "first") }
      b = build_doc do |bd|
        bd.set_string("items[0]", "first")
        bd.set_string("items[1]", "second")
      end
      d = differ.compute_diff(a, b)
      expect(d.added.length).to eq(1)
      expect(d.added[0].path).to eq("items[1]")
    end

    it "detects nested path added" do
      a = build_doc { |b| b.set_string("person.name", "John") }
      b = build_doc do |bd|
        bd.set_string("person.name", "John")
        bd.set_string("person.address.city", "Austin")
      end
      d = differ.compute_diff(a, b)
      expect(d.added.length).to eq(1)
      expect(d.added[0].path).to eq("person.address.city")
    end

    it "field added to empty document" do
      a = Odin::Types::OdinDocument.empty
      b = build_doc { |bd| bd.set_string("name", "John") }
      d = differ.compute_diff(a, b)
      expect(d.added.length).to eq(1)
      expect(d.added[0].path).to eq("name")
    end

    it "preserves modifiers on added entries" do
      a = Odin::Types::OdinDocument.empty
      mods = make_mods(required: true)
      b = build_doc { |bd| bd.set_string("name", "John", modifiers: mods) }
      d = differ.compute_diff(a, b)
      expect(d.added[0].modifiers).to eq(mods)
    end

    it "detects addition with null value" do
      a = Odin::Types::OdinDocument.empty
      b = build_doc { |bd| bd.set_null("field") }
      d = differ.compute_diff(a, b)
      expect(d.added.length).to eq(1)
      expect(d.added[0].value).to be_a(Odin::Types::OdinNull)
    end

    it "additions are sorted by path" do
      a = Odin::Types::OdinDocument.empty
      b = build_doc do |bd|
        bd.set_string("zebra", "z")
        bd.set_string("alpha", "a")
        bd.set_string("middle", "m")
      end
      d = differ.compute_diff(a, b)
      expect(d.added.map(&:path)).to eq(%w[alpha middle zebra])
    end
  end

  # ── Removals ────────────────────────────────────────────────

  describe "removals" do
    it "detects one field removed" do
      a = build_doc do |b|
        b.set_string("name", "John")
        b.set_integer("age", 30)
      end
      b = build_doc { |bd| bd.set_string("name", "John") }
      d = differ.compute_diff(a, b)
      expect(d.removed.length).to eq(1)
      expect(d.removed[0].path).to eq("age")
    end

    it "detects multiple fields removed" do
      a = build_doc do |b|
        b.set_string("name", "John")
        b.set_integer("age", 30)
        b.set_string("city", "Austin")
      end
      b = build_doc { |bd| bd.set_string("name", "John") }
      d = differ.compute_diff(a, b)
      expect(d.removed.length).to eq(2)
      expect(d.removed.map(&:path)).to contain_exactly("age", "city")
    end

    it "detects array element removed" do
      a = build_doc do |b|
        b.set_string("items[0]", "first")
        b.set_string("items[1]", "second")
      end
      b = build_doc { |bd| bd.set_string("items[0]", "first") }
      d = differ.compute_diff(a, b)
      expect(d.removed.length).to eq(1)
      expect(d.removed[0].path).to eq("items[1]")
    end

    it "detects nested path removed" do
      a = build_doc do |b|
        b.set_string("person.name", "John")
        b.set_string("person.address.city", "Austin")
      end
      b = build_doc { |bd| bd.set_string("person.name", "John") }
      d = differ.compute_diff(a, b)
      expect(d.removed.length).to eq(1)
      expect(d.removed[0].path).to eq("person.address.city")
    end

    it "all fields removed from document" do
      a = build_doc do |b|
        b.set_string("name", "John")
        b.set_integer("age", 30)
      end
      b = Odin::Types::OdinDocument.empty
      d = differ.compute_diff(a, b)
      expect(d.removed.length).to eq(2)
    end

    it "preserves modifiers on removed entries" do
      mods = make_mods(confidential: true)
      a = build_doc { |b| b.set_string("ssn", "123", modifiers: mods) }
      b = Odin::Types::OdinDocument.empty
      d = differ.compute_diff(a, b)
      expect(d.removed[0].modifiers).to eq(mods)
    end

    it "removals are sorted by path" do
      a = build_doc do |b|
        b.set_string("zebra", "z")
        b.set_string("alpha", "a")
        b.set_string("middle", "m")
      end
      b = Odin::Types::OdinDocument.empty
      d = differ.compute_diff(a, b)
      expect(d.removed.map(&:path)).to eq(%w[alpha middle zebra])
    end
  end

  # ── Changes ─────────────────────────────────────────────────

  describe "changes" do
    it "detects string value changed" do
      a = build_doc { |b| b.set_string("name", "John") }
      b = build_doc { |bd| bd.set_string("name", "Jane") }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
      expect(d.changed[0].path).to eq("name")
      expect(d.changed[0].old_value).to eq(Odin::Types::OdinString.new("John"))
      expect(d.changed[0].new_value).to eq(Odin::Types::OdinString.new("Jane"))
    end

    it "detects integer value changed" do
      a = build_doc { |b| b.set_integer("count", 42) }
      b = build_doc { |bd| bd.set_integer("count", 100) }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
      expect(d.changed[0].path).to eq("count")
    end

    it "detects number value changed" do
      a = build_doc { |b| b.set_number("rate", 3.14) }
      b = build_doc { |bd| bd.set_number("rate", 2.71) }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
    end

    it "detects currency value changed" do
      a = build_doc { |b| b.set_currency("price", 99.99) }
      b = build_doc { |bd| bd.set_currency("price", 149.99) }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
    end

    it "detects boolean value changed" do
      a = build_doc { |b| b.set_boolean("active", true) }
      b = build_doc { |bd| bd.set_boolean("active", false) }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
    end

    it "detects type change (string to integer)" do
      a = build_doc { |b| b.set_string("value", "42") }
      b = build_doc { |bd| bd.set_integer("value", 42) }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
    end

    it "detects type change (integer to number)" do
      a = build_doc { |b| b.set_integer("value", 42) }
      b = build_doc { |bd| bd.set_number("value", 42.0) }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
    end

    it "detects modifier-only change (value same, modifier different)" do
      a = build_doc { |b| b.set_string("name", "John") }
      b = build_doc { |bd| bd.set_string("name", "John", modifiers: make_mods(required: true)) }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
      expect(d.changed[0].path).to eq("name")
    end

    it "detects adding modifier to existing field" do
      a = build_doc { |b| b.set_string("ssn", "123") }
      b = build_doc { |bd| bd.set_string("ssn", "123", modifiers: make_mods(confidential: true)) }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
    end

    it "detects removing modifier from existing field" do
      a = build_doc { |b| b.set_string("ssn", "123", modifiers: make_mods(confidential: true)) }
      b = build_doc { |bd| bd.set_string("ssn", "123") }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
    end

    it "detects modifier changed (required to confidential)" do
      a = build_doc { |b| b.set_string("field", "v", modifiers: make_mods(required: true)) }
      b = build_doc { |bd| bd.set_string("field", "v", modifiers: make_mods(confidential: true)) }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
    end

    it "no change when value and modifier both same" do
      mods = make_mods(required: true, confidential: true)
      a = build_doc { |b| b.set_string("field", "val", modifiers: mods) }
      b = build_doc { |bd| bd.set_string("field", "val", modifiers: mods) }
      d = differ.compute_diff(a, b)
      expect(d).to be_empty
    end

    it "changes are sorted by path" do
      a = build_doc do |b|
        b.set_string("zebra", "old")
        b.set_string("alpha", "old")
      end
      b = build_doc do |bd|
        bd.set_string("zebra", "new")
        bd.set_string("alpha", "new")
      end
      d = differ.compute_diff(a, b)
      expect(d.changed.map(&:path)).to eq(%w[alpha zebra])
    end

    it "detects null to value change" do
      a = build_doc { |b| b.set_null("name") }
      b = build_doc { |bd| bd.set_string("name", "John") }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
    end

    it "detects value to null change" do
      a = build_doc { |b| b.set_string("name", "John") }
      b = build_doc { |bd| bd.set_null("name") }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
    end
  end

  # ── Move detection ──────────────────────────────────────────

  describe "move detection" do
    it "detects simple move" do
      a = build_doc { |b| b.set_string("oldField", "value") }
      b = build_doc { |bd| bd.set_string("newField", "value") }
      d = differ.compute_diff(a, b)
      expect(d.moved.length).to eq(1)
      expect(d.moved[0].from_path).to eq("oldField")
      expect(d.moved[0].to_path).to eq("newField")
      expect(d.removed).to be_empty
      expect(d.added).to be_empty
    end

    it "no move when values differ" do
      a = build_doc { |b| b.set_string("pathA", "value1") }
      b = build_doc { |bd| bd.set_string("pathB", "value2") }
      d = differ.compute_diff(a, b)
      expect(d.moved).to be_empty
      expect(d.removed.length).to eq(1)
      expect(d.added.length).to eq(1)
    end

    it "detects multiple moves" do
      a = build_doc do |b|
        b.set_string("oldA", "alpha")
        b.set_string("oldB", "beta")
      end
      b = build_doc do |bd|
        bd.set_string("newA", "alpha")
        bd.set_string("newB", "beta")
      end
      d = differ.compute_diff(a, b)
      expect(d.moved.length).to eq(2)
      expect(d.removed).to be_empty
      expect(d.added).to be_empty
    end

    it "move with integer value" do
      a = build_doc { |b| b.set_integer("old", 42) }
      b = build_doc { |bd| bd.set_integer("new", 42) }
      d = differ.compute_diff(a, b)
      expect(d.moved.length).to eq(1)
      expect(d.moved[0].from_path).to eq("old")
      expect(d.moved[0].to_path).to eq("new")
    end

    it "move preserves value reference" do
      val = Odin::Types::OdinString.new("shared")
      a = build_doc { |b| b.set("source", val) }
      b = build_doc { |bd| bd.set("target", val) }
      d = differ.compute_diff(a, b)
      expect(d.moved.length).to eq(1)
      expect(d.moved[0].value).to eq(val)
    end

    it "first match wins for duplicate values" do
      a = build_doc do |b|
        b.set_string("a1", "dup")
        b.set_string("a2", "dup")
      end
      b = build_doc do |bd|
        bd.set_string("b1", "dup")
        bd.set_string("b2", "dup")
      end
      d = differ.compute_diff(a, b)
      expect(d.moved.length).to eq(2)
      expect(d.removed).to be_empty
      expect(d.added).to be_empty
    end

    it "partial move with remaining add/remove" do
      a = build_doc do |b|
        b.set_string("old", "shared")
        b.set_string("removed", "gone")
      end
      b = build_doc do |bd|
        bd.set_string("new", "shared")
        bd.set_string("added", "fresh")
      end
      d = differ.compute_diff(a, b)
      expect(d.moved.length).to eq(1)
      expect(d.removed.length).to eq(1)
      expect(d.removed[0].path).to eq("removed")
      expect(d.added.length).to eq(1)
      expect(d.added[0].path).to eq("added")
    end

    it "does not move when type differs" do
      a = build_doc { |b| b.set_string("old", "42") }
      b = build_doc { |bd| bd.set_integer("new", 42) }
      d = differ.compute_diff(a, b)
      expect(d.moved).to be_empty
    end
  end

  # ── All value types ─────────────────────────────────────────

  describe "all value types" do
    it "diff with null values" do
      a = build_doc { |b| b.set_null("field") }
      b = build_doc { |bd| bd.set_null("field") }
      d = differ.compute_diff(a, b)
      expect(d).to be_empty
    end

    it "diff with binary values" do
      a = build_doc { |b| b.set("data", Odin::Types::OdinBinary.new("SGVsbG8=")) }
      b = build_doc { |bd| bd.set("data", Odin::Types::OdinBinary.new("V29ybGQ=")) }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
    end

    it "diff with same binary values" do
      val = Odin::Types::OdinBinary.new("SGVsbG8=")
      a = build_doc { |b| b.set("data", val) }
      b = build_doc { |bd| bd.set("data", Odin::Types::OdinBinary.new("SGVsbG8=")) }
      d = differ.compute_diff(a, b)
      expect(d).to be_empty
    end

    it "diff with binary algorithm difference" do
      a = build_doc { |b| b.set("hash", Odin::Types::OdinBinary.new("abc123", algorithm: "sha256")) }
      b = build_doc { |bd| bd.set("hash", Odin::Types::OdinBinary.new("abc123", algorithm: "md5")) }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
    end

    it "diff with date values" do
      a = build_doc { |b| b.set("date", Odin::Types::OdinDate.new(Date.new(2024, 6, 15))) }
      b = build_doc { |bd| bd.set("date", Odin::Types::OdinDate.new(Date.new(2024, 6, 16))) }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
    end

    it "diff with same date values" do
      a = build_doc { |b| b.set("date", Odin::Types::OdinDate.new(Date.new(2024, 6, 15))) }
      b = build_doc { |bd| bd.set("date", Odin::Types::OdinDate.new(Date.new(2024, 6, 15))) }
      d = differ.compute_diff(a, b)
      expect(d).to be_empty
    end

    it "diff with reference values" do
      a = build_doc { |b| b.set("ref", Odin::Types::OdinReference.new("drivers[0]")) }
      b = build_doc { |bd| bd.set("ref", Odin::Types::OdinReference.new("drivers[1]")) }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
    end

    it "diff with same reference values" do
      a = build_doc { |b| b.set("ref", Odin::Types::OdinReference.new("drivers[0]")) }
      b = build_doc { |bd| bd.set("ref", Odin::Types::OdinReference.new("drivers[0]")) }
      d = differ.compute_diff(a, b)
      expect(d).to be_empty
    end

    it "diff with percent values" do
      a = build_doc { |b| b.set("rate", Odin::Types::OdinPercent.new(0.15)) }
      b = build_doc { |bd| bd.set("rate", Odin::Types::OdinPercent.new(0.25)) }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
    end

    it "diff with time values" do
      a = build_doc { |b| b.set("start", Odin::Types::OdinTime.new("09:30:00")) }
      b = build_doc { |bd| bd.set("start", Odin::Types::OdinTime.new("10:30:00")) }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
    end

    it "diff with duration values" do
      a = build_doc { |b| b.set("term", Odin::Types::OdinDuration.new("P6M")) }
      b = build_doc { |bd| bd.set("term", Odin::Types::OdinDuration.new("P1Y")) }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
    end

    it "diff with timestamp values" do
      a = build_doc { |b| b.set("ts", Odin::Types::OdinTimestamp.new(Time.utc(2024, 6, 15, 10, 30))) }
      b = build_doc { |bd| bd.set("ts", Odin::Types::OdinTimestamp.new(Time.utc(2024, 6, 15, 11, 30))) }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
    end

    it "diff with currency code mismatch" do
      a = build_doc { |b| b.set_currency("amount", 100.00, currency_code: "USD") }
      b = build_doc { |bd| bd.set_currency("amount", 100.00, currency_code: "EUR") }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
    end

    it "percent vs number is a type change" do
      a = build_doc { |b| b.set("value", Odin::Types::OdinPercent.new(0.15)) }
      b = build_doc { |bd| bd.set("value", Odin::Types::OdinNumber.new(0.15)) }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
    end
  end

  # ── Edge cases ──────────────────────────────────────────────

  describe "edge cases" do
    it "very deep nested paths" do
      a = build_doc { |b| b.set_string("a.b.c.d.e.f", "deep") }
      b = build_doc { |bd| bd.set_string("a.b.c.d.e.f", "deeper") }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
      expect(d.changed[0].path).to eq("a.b.c.d.e.f")
    end

    it "mixed additions, removals, and changes" do
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
      expect(d.changed.length).to eq(1)
      expect(d.changed[0].path).to eq("name")
      expect(d.added.length).to eq(1)
      expect(d.added[0].path).to eq("state")
      expect(d.removed.length).to eq(2)
    end

    it "diff is not empty when only move detected" do
      a = build_doc { |b| b.set_string("old", "val") }
      b = build_doc { |bd| bd.set_string("new", "val") }
      d = differ.compute_diff(a, b)
      expect(d).not_to be_empty
    end

    it "handles combined modifier change" do
      a = build_doc { |b| b.set_string("f", "v", modifiers: make_mods(required: true)) }
      b = build_doc { |bd| bd.set_string("f", "v", modifiers: make_mods(required: true, confidential: true)) }
      d = differ.compute_diff(a, b)
      expect(d.changed.length).to eq(1)
    end

    it "nil modifiers equals no modifiers" do
      a = build_doc { |b| b.set_string("f", "v") }
      b = build_doc { |bd| bd.set_string("f", "v", modifiers: Odin::Types::OdinModifiers::NONE) }
      d = differ.compute_diff(a, b)
      expect(d).to be_empty
    end
  end
end
