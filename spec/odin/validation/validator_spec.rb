# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Odin::Validation::Validator do
  let(:validator) { described_class.new }

  # Helper to build a document
  def build_doc(&block)
    b = Odin::Types::OdinDocumentBuilder.new
    block.call(b)
    b.build
  end

  # Helper to build a schema directly
  def build_schema(fields: {}, types: {}, arrays: {}, object_constraints: {}, metadata: {})
    Odin::Types::OdinSchema.new(
      metadata: metadata,
      types: types,
      fields: fields,
      arrays: arrays,
      object_constraints: object_constraints
    )
  end

  def string_field(name, **opts)
    Odin::Types::SchemaField.new(name: name, field_type: :string, **opts)
  end

  def integer_field(name, **opts)
    Odin::Types::SchemaField.new(name: name, field_type: :integer, **opts)
  end

  def number_field(name, **opts)
    Odin::Types::SchemaField.new(name: name, field_type: :number, **opts)
  end

  def boolean_field(name, **opts)
    Odin::Types::SchemaField.new(name: name, field_type: :boolean, **opts)
  end

  def currency_field(name, **opts)
    Odin::Types::SchemaField.new(name: name, field_type: :currency, **opts)
  end

  def date_field(name, **opts)
    Odin::Types::SchemaField.new(name: name, field_type: :date, **opts)
  end

  # ── V001: Required field missing ──

  describe "V001 - Required field missing" do
    it "reports missing required field" do
      schema = build_schema(fields: { "name" => string_field("name", required: true) })
      doc = build_doc { |b| b.set_string("age", "30") }
      result = validator.validate(doc, schema)
      expect(result.valid?).to be false
      expect(result.errors.first.code).to eq("V001")
    end

    it "passes when required field is present" do
      schema = build_schema(fields: { "name" => string_field("name", required: true) })
      doc = build_doc { |b| b.set_string("name", "Alice") }
      result = validator.validate(doc, schema)
      v001_errors = result.errors.select { |e| e.code == "V001" }
      expect(v001_errors).to be_empty
    end

    it "reports multiple missing required fields" do
      schema = build_schema(fields: {
        "name" => string_field("name", required: true),
        "email" => string_field("email", required: true),
      })
      doc = build_doc { |b| b.set_string("other", "x") }
      result = validator.validate(doc, schema)
      v001 = result.errors.select { |e| e.code == "V001" }
      expect(v001.length).to eq(2)
    end

    it "does not report optional fields as missing" do
      schema = build_schema(fields: {
        "name" => string_field("name", required: true),
        "notes" => string_field("notes", required: false),
      })
      doc = build_doc { |b| b.set_string("name", "Alice") }
      result = validator.validate(doc, schema)
      v001 = result.errors.select { |e| e.code == "V001" }
      expect(v001).to be_empty
    end

    it "reports required field in nested type" do
      type_fields = { "email" => string_field("email", required: true) }
      types = { "user" => Odin::Types::SchemaType.new(name: "user", fields: type_fields) }
      schema = build_schema(types: types)
      doc = build_doc { |b| b.set_string("user.name", "Alice") }
      result = validator.validate(doc, schema)
      v001 = result.errors.select { |e| e.code == "V001" }
      expect(v001.any? { |e| e.path == "user.email" }).to be true
    end

    it "does not check required on computed fields" do
      schema = build_schema(fields: {
        "total" => number_field("total", required: true, computed: true),
      })
      doc = build_doc { |b| b.set_string("other", "x") }
      result = validator.validate(doc, schema)
      v001 = result.errors.select { |e| e.code == "V001" }
      expect(v001).to be_empty
    end

    it "required field present but null still fails" do
      schema = build_schema(fields: { "name" => string_field("name", required: true) })
      doc = build_doc { |b| b.set_null("name") }
      result = validator.validate(doc, schema)
      v001 = result.errors.select { |e| e.code == "V001" }
      expect(v001).not_to be_empty
    end

    it "skips required check for fields with conditionals" do
      cond = Odin::Types::SchemaConditional.new(field: "method", operator: "=", value: "card")
      schema = build_schema(fields: {
        "card_number" => string_field("card_number", required: true, conditionals: [cond]),
      })
      doc = build_doc { |b| b.set_string("method", "bank") }
      result = validator.validate(doc, schema)
      v001 = result.errors.select { |e| e.code == "V001" }
      expect(v001).to be_empty
    end
  end

  # ── V002: Type mismatch ──

  describe "V002 - Type mismatch" do
    it "reports string where integer expected" do
      schema = build_schema(fields: { "age" => integer_field("age") })
      doc = build_doc { |b| b.set_string("age", "thirty") }
      result = validator.validate(doc, schema)
      v002 = result.errors.select { |e| e.code == "V002" }
      expect(v002).not_to be_empty
    end

    it "reports integer where string expected" do
      schema = build_schema(fields: { "name" => string_field("name") })
      doc = build_doc { |b| b.set_integer("name", 42) }
      result = validator.validate(doc, schema)
      v002 = result.errors.select { |e| e.code == "V002" }
      expect(v002).not_to be_empty
    end

    it "reports number where boolean expected" do
      schema = build_schema(fields: { "flag" => boolean_field("flag") })
      doc = build_doc { |b| b.set_number("flag", 3.14) }
      result = validator.validate(doc, schema)
      v002 = result.errors.select { |e| e.code == "V002" }
      expect(v002).not_to be_empty
    end

    it "passes when types match: string" do
      schema = build_schema(fields: { "name" => string_field("name") })
      doc = build_doc { |b| b.set_string("name", "Alice") }
      result = validator.validate(doc, schema)
      v002 = result.errors.select { |e| e.code == "V002" }
      expect(v002).to be_empty
    end

    it "passes when types match: integer" do
      schema = build_schema(fields: { "age" => integer_field("age") })
      doc = build_doc { |b| b.set_integer("age", 30) }
      result = validator.validate(doc, schema)
      v002 = result.errors.select { |e| e.code == "V002" }
      expect(v002).to be_empty
    end

    it "passes when types match: boolean" do
      schema = build_schema(fields: { "flag" => boolean_field("flag") })
      doc = build_doc { |b| b.set_boolean("flag", true) }
      result = validator.validate(doc, schema)
      v002 = result.errors.select { |e| e.code == "V002" }
      expect(v002).to be_empty
    end

    it "number field accepts integer (compatible)" do
      schema = build_schema(fields: { "val" => number_field("val") })
      doc = build_doc { |b| b.set_integer("val", 42) }
      result = validator.validate(doc, schema)
      v002 = result.errors.select { |e| e.code == "V002" }
      expect(v002).to be_empty
    end

    it "number field accepts currency (compatible)" do
      schema = build_schema(fields: { "val" => number_field("val") })
      doc = build_doc { |b| b.set_currency("val", 99.99) }
      result = validator.validate(doc, schema)
      v002 = result.errors.select { |e| e.code == "V002" }
      expect(v002).to be_empty
    end

    it "integer field rejects number" do
      schema = build_schema(fields: { "count" => integer_field("count") })
      doc = build_doc { |b| b.set_number("count", 3.14) }
      result = validator.validate(doc, schema)
      v002 = result.errors.select { |e| e.code == "V002" }
      expect(v002).not_to be_empty
    end

    it "null value does not trigger type mismatch (nullable)" do
      schema = build_schema(fields: { "val" => string_field("val") })
      doc = build_doc { |b| b.set_null("val") }
      result = validator.validate(doc, schema)
      v002 = result.errors.select { |e| e.code == "V002" }
      expect(v002).to be_empty
    end

    it "skips type check for missing fields" do
      schema = build_schema(fields: { "age" => integer_field("age") })
      doc = build_doc { |b| b.set_string("name", "Alice") }
      result = validator.validate(doc, schema)
      v002 = result.errors.select { |e| e.code == "V002" }
      expect(v002).to be_empty
    end

    it "reports boolean where string expected" do
      schema = build_schema(fields: { "name" => string_field("name") })
      doc = build_doc { |b| b.set_boolean("name", true) }
      result = validator.validate(doc, schema)
      v002 = result.errors.select { |e| e.code == "V002" }
      expect(v002).not_to be_empty
    end
  end

  # ── V003: Value out of bounds ──

  describe "V003 - Value out of bounds" do
    it "reports value below min" do
      bounds = Odin::Types::BoundsConstraint.new(min: 0, max: 150)
      schema = build_schema(fields: {
        "age" => integer_field("age", constraints: [bounds]),
      })
      doc = build_doc { |b| b.set_integer("age", -5) }
      result = validator.validate(doc, schema)
      v003 = result.errors.select { |e| e.code == "V003" }
      expect(v003).not_to be_empty
    end

    it "reports value above max" do
      bounds = Odin::Types::BoundsConstraint.new(min: 0, max: 150)
      schema = build_schema(fields: {
        "age" => integer_field("age", constraints: [bounds]),
      })
      doc = build_doc { |b| b.set_integer("age", 200) }
      result = validator.validate(doc, schema)
      v003 = result.errors.select { |e| e.code == "V003" }
      expect(v003).not_to be_empty
    end

    it "passes value at min boundary (inclusive)" do
      bounds = Odin::Types::BoundsConstraint.new(min: 0, max: 150)
      schema = build_schema(fields: {
        "age" => integer_field("age", constraints: [bounds]),
      })
      doc = build_doc { |b| b.set_integer("age", 0) }
      result = validator.validate(doc, schema)
      v003 = result.errors.select { |e| e.code == "V003" }
      expect(v003).to be_empty
    end

    it "passes value at max boundary (inclusive)" do
      bounds = Odin::Types::BoundsConstraint.new(min: 0, max: 150)
      schema = build_schema(fields: {
        "age" => integer_field("age", constraints: [bounds]),
      })
      doc = build_doc { |b| b.set_integer("age", 150) }
      result = validator.validate(doc, schema)
      v003 = result.errors.select { |e| e.code == "V003" }
      expect(v003).to be_empty
    end

    it "passes value within range" do
      bounds = Odin::Types::BoundsConstraint.new(min: 1, max: 100)
      schema = build_schema(fields: {
        "qty" => integer_field("qty", constraints: [bounds]),
      })
      doc = build_doc { |b| b.set_integer("qty", 50) }
      result = validator.validate(doc, schema)
      v003 = result.errors.select { |e| e.code == "V003" }
      expect(v003).to be_empty
    end

    it "checks string length bounds" do
      bounds = Odin::Types::BoundsConstraint.new(min: 3, max: 10)
      schema = build_schema(fields: {
        "code" => string_field("code", constraints: [bounds]),
      })
      doc = build_doc { |b| b.set_string("code", "AB") }
      result = validator.validate(doc, schema)
      v003 = result.errors.select { |e| e.code == "V003" }
      expect(v003).not_to be_empty
    end

    it "string length at boundary passes" do
      bounds = Odin::Types::BoundsConstraint.new(min: 3, max: 10)
      schema = build_schema(fields: {
        "code" => string_field("code", constraints: [bounds]),
      })
      doc = build_doc { |b| b.set_string("code", "ABC") }
      result = validator.validate(doc, schema)
      v003 = result.errors.select { |e| e.code == "V003" }
      expect(v003).to be_empty
    end

    it "no bounds constraint means no check" do
      schema = build_schema(fields: { "val" => integer_field("val") })
      doc = build_doc { |b| b.set_integer("val", 999999) }
      result = validator.validate(doc, schema)
      v003 = result.errors.select { |e| e.code == "V003" }
      expect(v003).to be_empty
    end

    it "min-only bound check" do
      bounds = Odin::Types::BoundsConstraint.new(min: 1)
      schema = build_schema(fields: {
        "qty" => integer_field("qty", constraints: [bounds]),
      })
      doc = build_doc { |b| b.set_integer("qty", 0) }
      result = validator.validate(doc, schema)
      v003 = result.errors.select { |e| e.code == "V003" }
      expect(v003).not_to be_empty
    end

    it "max-only bound check" do
      bounds = Odin::Types::BoundsConstraint.new(max: 100)
      schema = build_schema(fields: {
        "qty" => integer_field("qty", constraints: [bounds]),
      })
      doc = build_doc { |b| b.set_integer("qty", 101) }
      result = validator.validate(doc, schema)
      v003 = result.errors.select { |e| e.code == "V003" }
      expect(v003).not_to be_empty
    end
  end

  # ── V004: Pattern mismatch ──

  describe "V004 - Pattern mismatch" do
    it "reports value not matching pattern" do
      pattern = Odin::Types::PatternConstraint.new(pattern: "^[A-Z]{3}$")
      schema = build_schema(fields: {
        "code" => string_field("code", constraints: [pattern]),
      })
      doc = build_doc { |b| b.set_string("code", "ab") }
      result = validator.validate(doc, schema)
      v004 = result.errors.select { |e| e.code == "V004" }
      expect(v004).not_to be_empty
    end

    it "passes value matching pattern" do
      pattern = Odin::Types::PatternConstraint.new(pattern: "^[A-Z]{3}$")
      schema = build_schema(fields: {
        "code" => string_field("code", constraints: [pattern]),
      })
      doc = build_doc { |b| b.set_string("code", "ABC") }
      result = validator.validate(doc, schema)
      v004 = result.errors.select { |e| e.code == "V004" }
      expect(v004).to be_empty
    end

    it "rejects dangerous regex pattern" do
      pattern = Odin::Types::PatternConstraint.new(pattern: "(a+)+$")
      schema = build_schema(fields: {
        "val" => string_field("val", constraints: [pattern]),
      })
      doc = build_doc { |b| b.set_string("val", "aaa") }
      result = validator.validate(doc, schema)
      v004 = result.errors.select { |e| e.code == "V004" }
      expect(v004).not_to be_empty
    end

    it "handles invalid regex gracefully" do
      pattern = Odin::Types::PatternConstraint.new(pattern: "[invalid")
      schema = build_schema(fields: {
        "val" => string_field("val", constraints: [pattern]),
      })
      doc = build_doc { |b| b.set_string("val", "test") }
      result = validator.validate(doc, schema)
      v004 = result.errors.select { |e| e.code == "V004" }
      expect(v004).not_to be_empty
    end

    it "skips pattern check for non-string values" do
      pattern = Odin::Types::PatternConstraint.new(pattern: "^\\d+$")
      schema = build_schema(fields: {
        "val" => integer_field("val", constraints: [pattern]),
      })
      doc = build_doc { |b| b.set_integer("val", 42) }
      result = validator.validate(doc, schema)
      v004 = result.errors.select { |e| e.code == "V004" }
      expect(v004).to be_empty
    end

    it "pattern with anchors" do
      pattern = Odin::Types::PatternConstraint.new(pattern: "^\\d{5}$")
      schema = build_schema(fields: {
        "zip" => string_field("zip", constraints: [pattern]),
      })
      doc = build_doc { |b| b.set_string("zip", "12345") }
      result = validator.validate(doc, schema)
      v004 = result.errors.select { |e| e.code == "V004" }
      expect(v004).to be_empty
    end

    it "pattern fails without anchors matching" do
      pattern = Odin::Types::PatternConstraint.new(pattern: "^\\d{5}$")
      schema = build_schema(fields: {
        "zip" => string_field("zip", constraints: [pattern]),
      })
      doc = build_doc { |b| b.set_string("zip", "1234") }
      result = validator.validate(doc, schema)
      v004 = result.errors.select { |e| e.code == "V004" }
      expect(v004).not_to be_empty
    end

    it "skips null values" do
      pattern = Odin::Types::PatternConstraint.new(pattern: "^[A-Z]+$")
      schema = build_schema(fields: {
        "val" => string_field("val", constraints: [pattern]),
      })
      doc = build_doc { |b| b.set_null("val") }
      result = validator.validate(doc, schema)
      v004 = result.errors.select { |e| e.code == "V004" }
      expect(v004).to be_empty
    end
  end

  # ── V005: Invalid enum value ──

  describe "V005 - Invalid enum value" do
    it "reports value not in enum list" do
      enum = Odin::Types::EnumConstraint.new(values: ["draft", "published", "archived"])
      schema = build_schema(fields: {
        "status" => string_field("status", constraints: [enum]),
      })
      doc = build_doc { |b| b.set_string("status", "deleted") }
      result = validator.validate(doc, schema)
      v005 = result.errors.select { |e| e.code == "V005" }
      expect(v005).not_to be_empty
    end

    it "passes value in enum list" do
      enum = Odin::Types::EnumConstraint.new(values: ["draft", "published", "archived"])
      schema = build_schema(fields: {
        "status" => string_field("status", constraints: [enum]),
      })
      doc = build_doc { |b| b.set_string("status", "draft") }
      result = validator.validate(doc, schema)
      v005 = result.errors.select { |e| e.code == "V005" }
      expect(v005).to be_empty
    end

    it "enum check is case sensitive" do
      enum = Odin::Types::EnumConstraint.new(values: ["Draft", "Published"])
      schema = build_schema(fields: {
        "status" => string_field("status", constraints: [enum]),
      })
      doc = build_doc { |b| b.set_string("status", "draft") }
      result = validator.validate(doc, schema)
      v005 = result.errors.select { |e| e.code == "V005" }
      expect(v005).not_to be_empty
    end

    it "skips null values" do
      enum = Odin::Types::EnumConstraint.new(values: ["a", "b"])
      schema = build_schema(fields: {
        "val" => string_field("val", constraints: [enum]),
      })
      doc = build_doc { |b| b.set_null("val") }
      result = validator.validate(doc, schema)
      v005 = result.errors.select { |e| e.code == "V005" }
      expect(v005).to be_empty
    end

    it "single enum value" do
      enum = Odin::Types::EnumConstraint.new(values: ["only"])
      schema = build_schema(fields: {
        "choice" => string_field("choice", constraints: [enum]),
      })
      doc = build_doc { |b| b.set_string("choice", "only") }
      result = validator.validate(doc, schema)
      v005 = result.errors.select { |e| e.code == "V005" }
      expect(v005).to be_empty
    end

    it "error message includes allowed values" do
      enum = Odin::Types::EnumConstraint.new(values: ["a", "b", "c"])
      schema = build_schema(fields: {
        "val" => string_field("val", constraints: [enum]),
      })
      doc = build_doc { |b| b.set_string("val", "x") }
      result = validator.validate(doc, schema)
      err = result.errors.find { |e| e.code == "V005" }
      expect(err.message).to include("a, b, c")
    end
  end

  # ── V006: Array length violation ──

  describe "V006 - Array length violation" do
    it "reports array too short" do
      arrays = {
        "items" => Odin::Types::SchemaArray.new(path: "items", min_items: 2),
      }
      schema = build_schema(arrays: arrays)
      doc = build_doc { |b| b.set_string("items[0].name", "one") }
      result = validator.validate(doc, schema)
      v006 = result.errors.select { |e| e.code == "V006" }
      expect(v006).not_to be_empty
    end

    it "reports array too long" do
      arrays = {
        "items" => Odin::Types::SchemaArray.new(path: "items", max_items: 2),
      }
      schema = build_schema(arrays: arrays)
      doc = build_doc do |b|
        b.set_string("items[0].name", "a")
        b.set_string("items[1].name", "b")
        b.set_string("items[2].name", "c")
      end
      result = validator.validate(doc, schema)
      v006 = result.errors.select { |e| e.code == "V006" }
      expect(v006).not_to be_empty
    end

    it "passes array at exact min boundary" do
      arrays = {
        "items" => Odin::Types::SchemaArray.new(path: "items", min_items: 2),
      }
      schema = build_schema(arrays: arrays)
      doc = build_doc do |b|
        b.set_string("items[0].name", "a")
        b.set_string("items[1].name", "b")
      end
      result = validator.validate(doc, schema)
      v006 = result.errors.select { |e| e.code == "V006" }
      expect(v006).to be_empty
    end

    it "passes array at exact max boundary" do
      arrays = {
        "items" => Odin::Types::SchemaArray.new(path: "items", max_items: 2),
      }
      schema = build_schema(arrays: arrays)
      doc = build_doc do |b|
        b.set_string("items[0].name", "a")
        b.set_string("items[1].name", "b")
      end
      result = validator.validate(doc, schema)
      v006 = result.errors.select { |e| e.code == "V006" }
      expect(v006).to be_empty
    end

    it "empty array when min_items > 0" do
      arrays = {
        "items" => Odin::Types::SchemaArray.new(path: "items", min_items: 1),
      }
      schema = build_schema(arrays: arrays)
      doc = build_doc { |b| b.set_string("other", "x") }
      result = validator.validate(doc, schema)
      # Array has 0 items but min_items is 1 — V006 violation
      v006 = result.errors.select { |e| e.code == "V006" }
      expect(v006.length).to eq(1)
      expect(v006.first.path).to eq("items")
    end

    it "no constraints means no check" do
      arrays = {
        "items" => Odin::Types::SchemaArray.new(path: "items"),
      }
      schema = build_schema(arrays: arrays)
      doc = build_doc do |b|
        10.times { |i| b.set_string("items[#{i}].name", "item#{i}") }
      end
      result = validator.validate(doc, schema)
      v006 = result.errors.select { |e| e.code == "V006" }
      expect(v006).to be_empty
    end

    it "both min and max violated" do
      arrays = {
        "items" => Odin::Types::SchemaArray.new(path: "items", min_items: 2, max_items: 5),
      }
      schema = build_schema(arrays: arrays)
      doc = build_doc { |b| b.set_string("items[0].name", "only_one") }
      result = validator.validate(doc, schema)
      v006 = result.errors.select { |e| e.code == "V006" }
      expect(v006).not_to be_empty
    end

    it "error includes count details" do
      arrays = {
        "items" => Odin::Types::SchemaArray.new(path: "items", min_items: 3),
      }
      schema = build_schema(arrays: arrays)
      doc = build_doc { |b| b.set_string("items[0].x", "a") }
      result = validator.validate(doc, schema)
      err = result.errors.find { |e| e.code == "V006" }
      expect(err.message).to include("1")
      expect(err.message).to include("3")
    end
  end

  # ── V007: Unique constraint violation ──

  describe "V007 - Unique constraint violation" do
    it "reports duplicate items in unique array" do
      arrays = {
        "tags" => Odin::Types::SchemaArray.new(path: "tags", unique: true,
          item_fields: { "value" => string_field("value") }),
      }
      schema = build_schema(arrays: arrays)
      doc = build_doc do |b|
        b.set_string("tags[0].value", "ruby")
        b.set_string("tags[1].value", "ruby")
      end
      result = validator.validate(doc, schema)
      v007 = result.errors.select { |e| e.code == "V007" }
      expect(v007).not_to be_empty
    end

    it "passes when all items unique" do
      arrays = {
        "tags" => Odin::Types::SchemaArray.new(path: "tags", unique: true,
          item_fields: { "value" => string_field("value") }),
      }
      schema = build_schema(arrays: arrays)
      doc = build_doc do |b|
        b.set_string("tags[0].value", "ruby")
        b.set_string("tags[1].value", "python")
      end
      result = validator.validate(doc, schema)
      v007 = result.errors.select { |e| e.code == "V007" }
      expect(v007).to be_empty
    end

    it "single item is always unique" do
      arrays = {
        "tags" => Odin::Types::SchemaArray.new(path: "tags", unique: true),
      }
      schema = build_schema(arrays: arrays)
      doc = build_doc { |b| b.set_string("tags[0].value", "ruby") }
      result = validator.validate(doc, schema)
      v007 = result.errors.select { |e| e.code == "V007" }
      expect(v007).to be_empty
    end

    it "non-unique array allows duplicates" do
      arrays = {
        "tags" => Odin::Types::SchemaArray.new(path: "tags", unique: false),
      }
      schema = build_schema(arrays: arrays)
      doc = build_doc do |b|
        b.set_string("tags[0].value", "ruby")
        b.set_string("tags[1].value", "ruby")
      end
      result = validator.validate(doc, schema)
      v007 = result.errors.select { |e| e.code == "V007" }
      expect(v007).to be_empty
    end
  end

  # ── V008: Invariant violation ──

  describe "V008 - Invariant violation" do
    it "reports violated invariant" do
      invariant = Odin::Types::SchemaInvariant.new(expression: "end >= start")
      schema = build_schema(
        fields: {
          "order.start" => integer_field("start"),
          "order.end" => integer_field("end"),
        },
        object_constraints: { "order" => [invariant] }
      )
      doc = build_doc do |b|
        b.set_integer("order.start", 10)
        b.set_integer("order.end", 5)
      end
      result = validator.validate(doc, schema)
      v008 = result.errors.select { |e| e.code == "V008" }
      expect(v008).not_to be_empty
    end

    it "passes satisfied invariant" do
      invariant = Odin::Types::SchemaInvariant.new(expression: "end >= start")
      schema = build_schema(
        fields: {
          "order.start" => integer_field("start"),
          "order.end" => integer_field("end"),
        },
        object_constraints: { "order" => [invariant] }
      )
      doc = build_doc do |b|
        b.set_integer("order.start", 5)
        b.set_integer("order.end", 10)
      end
      result = validator.validate(doc, schema)
      v008 = result.errors.select { |e| e.code == "V008" }
      expect(v008).to be_empty
    end

    it "equality invariant passes" do
      invariant = Odin::Types::SchemaInvariant.new(expression: "total = expected")
      schema = build_schema(
        fields: {
          "order.total" => number_field("total"),
          "order.expected" => number_field("expected"),
        },
        object_constraints: { "order" => [invariant] }
      )
      doc = build_doc do |b|
        b.set_number("order.total", 100.0)
        b.set_number("order.expected", 100.0)
      end
      result = validator.validate(doc, schema)
      v008 = result.errors.select { |e| e.code == "V008" }
      expect(v008).to be_empty
    end

    it "equality invariant fails" do
      invariant = Odin::Types::SchemaInvariant.new(expression: "total = expected")
      schema = build_schema(
        fields: {
          "order.total" => number_field("total"),
          "order.expected" => number_field("expected"),
        },
        object_constraints: { "order" => [invariant] }
      )
      doc = build_doc do |b|
        b.set_number("order.total", 100.0)
        b.set_number("order.expected", 200.0)
      end
      result = validator.validate(doc, schema)
      v008 = result.errors.select { |e| e.code == "V008" }
      expect(v008).not_to be_empty
    end

    it "compares to literal values" do
      invariant = Odin::Types::SchemaInvariant.new(expression: "qty >= 1")
      schema = build_schema(
        fields: { "qty" => integer_field("qty") },
        object_constraints: { "" => [invariant] }
      )
      doc = build_doc { |b| b.set_integer("qty", 0) }
      result = validator.validate(doc, schema)
      v008 = result.errors.select { |e| e.code == "V008" }
      expect(v008).not_to be_empty
    end

    it "skips when field missing" do
      invariant = Odin::Types::SchemaInvariant.new(expression: "qty >= 1")
      schema = build_schema(
        fields: { "qty" => integer_field("qty") },
        object_constraints: { "" => [invariant] }
      )
      doc = build_doc { |b| b.set_string("other", "x") }
      result = validator.validate(doc, schema)
      v008 = result.errors.select { |e| e.code == "V008" }
      expect(v008).to be_empty
    end
  end

  # ── V009: Cardinality constraint violation ──

  describe "V009 - Cardinality constraint violation" do
    it "one_of fails when none present" do
      card = Odin::Types::SchemaCardinality.new(
        cardinality_type: "one_of",
        fields: ["email", "phone", "address"],
        min: 1
      )
      schema = build_schema(
        fields: {
          "contact.email" => string_field("email"),
          "contact.phone" => string_field("phone"),
          "contact.address" => string_field("address"),
        },
        object_constraints: { "contact" => [card] }
      )
      doc = build_doc { |b| b.set_string("contact.other", "x") }
      result = validator.validate(doc, schema)
      v009 = result.errors.select { |e| e.code == "V009" }
      expect(v009).not_to be_empty
    end

    it "one_of passes when one present" do
      card = Odin::Types::SchemaCardinality.new(
        cardinality_type: "one_of",
        fields: ["email", "phone"],
        min: 1
      )
      schema = build_schema(
        object_constraints: { "contact" => [card] }
      )
      doc = build_doc { |b| b.set_string("contact.email", "a@b.com") }
      result = validator.validate(doc, schema)
      v009 = result.errors.select { |e| e.code == "V009" }
      expect(v009).to be_empty
    end

    it "exactly_one fails when two present" do
      card = Odin::Types::SchemaCardinality.new(
        cardinality_type: "exactly_one",
        fields: ["ssn", "passport"],
        min: 1, max: 1
      )
      schema = build_schema(
        object_constraints: { "id" => [card] }
      )
      doc = build_doc do |b|
        b.set_string("id.ssn", "123-45-6789")
        b.set_string("id.passport", "AB123456")
      end
      result = validator.validate(doc, schema)
      v009 = result.errors.select { |e| e.code == "V009" }
      expect(v009).not_to be_empty
    end

    it "exactly_one passes with exactly one" do
      card = Odin::Types::SchemaCardinality.new(
        cardinality_type: "exactly_one",
        fields: ["ssn", "passport"],
        min: 1, max: 1
      )
      schema = build_schema(
        object_constraints: { "id" => [card] }
      )
      doc = build_doc { |b| b.set_string("id.ssn", "123-45-6789") }
      result = validator.validate(doc, schema)
      v009 = result.errors.select { |e| e.code == "V009" }
      expect(v009).to be_empty
    end

    it "at_most_one fails with two" do
      card = Odin::Types::SchemaCardinality.new(
        cardinality_type: "at_most_one",
        fields: ["phone", "fax"],
        max: 1
      )
      schema = build_schema(
        object_constraints: { "" => [card] }
      )
      doc = build_doc do |b|
        b.set_string("phone", "555-0100")
        b.set_string("fax", "555-0200")
      end
      result = validator.validate(doc, schema)
      v009 = result.errors.select { |e| e.code == "V009" }
      expect(v009).not_to be_empty
    end

    it "at_most_one passes with zero" do
      card = Odin::Types::SchemaCardinality.new(
        cardinality_type: "at_most_one",
        fields: ["phone", "fax"],
        max: 1
      )
      schema = build_schema(
        object_constraints: { "" => [card] }
      )
      doc = build_doc { |b| b.set_string("name", "Alice") }
      result = validator.validate(doc, schema)
      v009 = result.errors.select { |e| e.code == "V009" }
      expect(v009).to be_empty
    end

    it "of constraint with range (2..3)" do
      card = Odin::Types::SchemaCardinality.new(
        cardinality_type: "of",
        fields: ["a", "b", "c", "d"],
        min: 2, max: 3
      )
      schema = build_schema(object_constraints: { "" => [card] })
      doc = build_doc { |b| b.set_string("a", "x") }
      result = validator.validate(doc, schema)
      v009 = result.errors.select { |e| e.code == "V009" }
      expect(v009).not_to be_empty # only 1, need 2
    end
  end

  # ── V010: Conditional requirement ──

  describe "V010 - Conditional requirement not met" do
    it "required field missing when condition true" do
      cond = Odin::Types::SchemaConditional.new(field: "method", operator: "=", value: "card")
      schema = build_schema(fields: {
        "method" => string_field("method"),
        "card_number" => string_field("card_number", required: true, conditionals: [cond]),
      })
      doc = build_doc { |b| b.set_string("method", "card") }
      result = validator.validate(doc, schema)
      v010 = result.errors.select { |e| e.code == "V010" }
      expect(v010).not_to be_empty
    end

    it "required field present when condition true" do
      cond = Odin::Types::SchemaConditional.new(field: "method", operator: "=", value: "card")
      schema = build_schema(fields: {
        "method" => string_field("method"),
        "card_number" => string_field("card_number", required: true, conditionals: [cond]),
      })
      doc = build_doc do |b|
        b.set_string("method", "card")
        b.set_string("card_number", "4111-1111-1111-1111")
      end
      result = validator.validate(doc, schema)
      v010 = result.errors.select { |e| e.code == "V010" }
      expect(v010).to be_empty
    end

    it "condition false - field not required" do
      cond = Odin::Types::SchemaConditional.new(field: "method", operator: "=", value: "card")
      schema = build_schema(fields: {
        "method" => string_field("method"),
        "card_number" => string_field("card_number", required: true, conditionals: [cond]),
      })
      doc = build_doc { |b| b.set_string("method", "bank") }
      result = validator.validate(doc, schema)
      v010 = result.errors.select { |e| e.code == "V010" }
      expect(v010).to be_empty
    end

    it "unless conditional - field required when condition false" do
      cond = Odin::Types::SchemaConditional.new(
        field: "sso_enabled", operator: "=", value: "true", unless_cond: true
      )
      schema = build_schema(fields: {
        "sso_enabled" => boolean_field("sso_enabled"),
        "password" => string_field("password", required: true, conditionals: [cond]),
      })
      doc = build_doc { |b| b.set_boolean("sso_enabled", false) }
      result = validator.validate(doc, schema)
      v010 = result.errors.select { |e| e.code == "V010" }
      expect(v010).not_to be_empty
    end

    it "unless conditional - field not required when condition true" do
      cond = Odin::Types::SchemaConditional.new(
        field: "sso_enabled", operator: "=", value: "true", unless_cond: true
      )
      schema = build_schema(fields: {
        "sso_enabled" => boolean_field("sso_enabled"),
        "password" => string_field("password", required: true, conditionals: [cond]),
      })
      doc = build_doc { |b| b.set_boolean("sso_enabled", true) }
      result = validator.validate(doc, schema)
      v010 = result.errors.select { |e| e.code == "V010" }
      expect(v010).to be_empty
    end

    it "condition field missing - no error" do
      cond = Odin::Types::SchemaConditional.new(field: "method", operator: "=", value: "card")
      schema = build_schema(fields: {
        "card_number" => string_field("card_number", required: true, conditionals: [cond]),
      })
      doc = build_doc { |b| b.set_string("other", "x") }
      result = validator.validate(doc, schema)
      v010 = result.errors.select { |e| e.code == "V010" }
      expect(v010).to be_empty
    end

    it "numeric conditional with > operator" do
      cond = Odin::Types::SchemaConditional.new(field: "amount", operator: ">", value: "100")
      schema = build_schema(fields: {
        "amount" => number_field("amount"),
        "approval" => string_field("approval", required: true, conditionals: [cond]),
      })
      doc = build_doc { |b| b.set_number("amount", 200.0) }
      result = validator.validate(doc, schema)
      v010 = result.errors.select { |e| e.code == "V010" }
      expect(v010).not_to be_empty
    end

    it "numeric conditional with > operator - below threshold" do
      cond = Odin::Types::SchemaConditional.new(field: "amount", operator: ">", value: "100")
      schema = build_schema(fields: {
        "amount" => number_field("amount"),
        "approval" => string_field("approval", required: true, conditionals: [cond]),
      })
      doc = build_doc { |b| b.set_number("amount", 50.0) }
      result = validator.validate(doc, schema)
      v010 = result.errors.select { |e| e.code == "V010" }
      expect(v010).to be_empty
    end
  end

  # ── V011: Unknown field ──

  describe "V011 - Unknown field (strict mode)" do
    it "reports unknown field in strict mode" do
      schema = build_schema(fields: { "name" => string_field("name") })
      doc = build_doc do |b|
        b.set_string("name", "Alice")
        b.set_string("unknown_field", "x")
      end
      result = validator.validate(doc, schema, strict: true)
      v011 = result.errors.select { |e| e.code == "V011" }
      expect(v011).not_to be_empty
    end

    it "no error for unknown field in non-strict mode" do
      schema = build_schema(fields: { "name" => string_field("name") })
      doc = build_doc do |b|
        b.set_string("name", "Alice")
        b.set_string("unknown_field", "x")
      end
      result = validator.validate(doc, schema)
      v011 = result.errors.select { |e| e.code == "V011" }
      expect(v011).to be_empty
    end

    it "all known fields pass strict mode" do
      schema = build_schema(fields: {
        "name" => string_field("name"),
        "age" => integer_field("age"),
      })
      doc = build_doc do |b|
        b.set_string("name", "Alice")
        b.set_integer("age", 30)
      end
      result = validator.validate(doc, schema, strict: true)
      v011 = result.errors.select { |e| e.code == "V011" }
      expect(v011).to be_empty
    end

    it "multiple unknown fields all reported" do
      schema = build_schema(fields: { "name" => string_field("name") })
      doc = build_doc do |b|
        b.set_string("name", "Alice")
        b.set_string("extra1", "x")
        b.set_string("extra2", "y")
      end
      result = validator.validate(doc, schema, strict: true)
      v011 = result.errors.select { |e| e.code == "V011" }
      expect(v011.length).to eq(2)
    end

    it "array item fields are considered known" do
      arrays = {
        "items" => Odin::Types::SchemaArray.new(
          path: "items",
          item_fields: { "name" => string_field("name") }
        ),
      }
      schema = build_schema(arrays: arrays)
      doc = build_doc { |b| b.set_string("items[0].name", "x") }
      result = validator.validate(doc, schema, strict: true)
      v011 = result.errors.select { |e| e.code == "V011" }
      expect(v011).to be_empty
    end

    it "unknown array item field in strict mode" do
      arrays = {
        "items" => Odin::Types::SchemaArray.new(
          path: "items",
          item_fields: { "name" => string_field("name") }
        ),
      }
      schema = build_schema(arrays: arrays)
      doc = build_doc do |b|
        b.set_string("items[0].name", "x")
        b.set_string("items[0].extra", "y")
      end
      result = validator.validate(doc, schema, strict: true)
      v011 = result.errors.select { |e| e.code == "V011" }
      expect(v011).not_to be_empty
    end
  end

  # ── V012: Circular reference ──

  describe "V012 - Circular reference" do
    it "detects self-referencing value" do
      schema = build_schema(fields: { "a" => string_field("a") })
      doc = build_doc do |b|
        b.set("a", Odin::Types::OdinReference.new("b"))
        b.set("b", Odin::Types::OdinReference.new("a"))
      end
      result = validator.validate(doc, schema)
      v012 = result.errors.select { |e| e.code == "V012" }
      expect(v012).not_to be_empty
    end

    it "no circular reference for normal refs" do
      schema = build_schema(fields: { "a" => string_field("a") })
      doc = build_doc do |b|
        b.set("a", Odin::Types::OdinReference.new("b"))
        b.set_string("b", "value")
      end
      result = validator.validate(doc, schema)
      v012 = result.errors.select { |e| e.code == "V012" }
      expect(v012).to be_empty
    end

    it "detects longer circular chain" do
      schema = build_schema
      doc = build_doc do |b|
        b.set("a", Odin::Types::OdinReference.new("b"))
        b.set("b", Odin::Types::OdinReference.new("c"))
        b.set("c", Odin::Types::OdinReference.new("a"))
      end
      result = validator.validate(doc, schema)
      v012 = result.errors.select { |e| e.code == "V012" }
      expect(v012).not_to be_empty
    end
  end

  # ── V013: Unresolved reference ──

  describe "V013 - Unresolved reference" do
    it "reports reference to non-existent path" do
      schema = build_schema
      doc = build_doc do |b|
        b.set("ref", Odin::Types::OdinReference.new("nonexistent"))
      end
      result = validator.validate(doc, schema)
      v013 = result.errors.select { |e| e.code == "V013" }
      expect(v013).not_to be_empty
    end

    it "passes when reference target exists" do
      schema = build_schema
      doc = build_doc do |b|
        b.set("ref", Odin::Types::OdinReference.new("target"))
        b.set_string("target", "value")
      end
      result = validator.validate(doc, schema)
      v013 = result.errors.select { |e| e.code == "V013" }
      expect(v013).to be_empty
    end

    it "reports type reference to undefined type" do
      schema = build_schema(fields: {
        "billing" => string_field("billing", type_ref: "nonexistent_type"),
      })
      doc = build_doc { |b| b.set_string("billing", "x") }
      result = validator.validate(doc, schema)
      v013 = result.errors.select { |e| e.code == "V013" }
      expect(v013).not_to be_empty
    end

    it "passes valid type reference" do
      types = { "address" => Odin::Types::SchemaType.new(name: "address") }
      schema = build_schema(
        types: types,
        fields: { "billing" => string_field("billing", type_ref: "address") }
      )
      doc = build_doc { |b| b.set_string("billing", "x") }
      result = validator.validate(doc, schema)
      v013 = result.errors.select { |e| e.code == "V013" }
      expect(v013).to be_empty
    end
  end

  # ── Multiple errors ──

  describe "multiple validation errors" do
    it "collects all errors (not just first)" do
      bounds = Odin::Types::BoundsConstraint.new(min: 0, max: 150)
      schema = build_schema(fields: {
        "name" => string_field("name", required: true),
        "age" => integer_field("age", required: true, constraints: [bounds]),
      })
      doc = build_doc { |b| b.set_string("other", "x") }
      result = validator.validate(doc, schema)
      expect(result.errors.length).to be >= 2
    end

    it "ValidationResult.valid? returns true for no errors" do
      schema = build_schema(fields: { "name" => string_field("name") })
      doc = build_doc { |b| b.set_string("name", "Alice") }
      result = validator.validate(doc, schema)
      expect(result.valid?).to be true
    end

    it "ValidationResult.valid? returns false for errors" do
      schema = build_schema(fields: { "name" => string_field("name", required: true) })
      doc = build_doc { |b| b.set_string("other", "x") }
      result = validator.validate(doc, schema)
      expect(result.valid?).to be false
    end

    it "errors have proper structure" do
      schema = build_schema(fields: { "name" => string_field("name", required: true) })
      doc = build_doc { |b| b.set_string("other", "x") }
      result = validator.validate(doc, schema)
      err = result.errors.first
      expect(err).to respond_to(:code)
      expect(err).to respond_to(:path)
      expect(err).to respond_to(:message)
      expect(err).to respond_to(:expected)
      expect(err).to respond_to(:actual)
    end

    it "ValidationResult.errors is frozen" do
      schema = build_schema
      doc = build_doc { |b| b.set_string("x", "y") }
      result = validator.validate(doc, schema)
      expect(result.errors).to be_frozen
    end

    it "mixed error types in single validation" do
      bounds = Odin::Types::BoundsConstraint.new(min: 0, max: 100)
      enum = Odin::Types::EnumConstraint.new(values: ["a", "b"])
      schema = build_schema(fields: {
        "required_field" => string_field("required_field", required: true),
        "num" => integer_field("num", constraints: [bounds]),
        "choice" => string_field("choice", constraints: [enum]),
      })
      doc = build_doc do |b|
        b.set_integer("num", 200)
        b.set_string("choice", "c")
      end
      result = validator.validate(doc, schema)
      codes = result.errors.map(&:code).uniq
      expect(codes).to include("V001") # missing required
      expect(codes).to include("V003") # out of bounds
      expect(codes).to include("V005") # invalid enum
    end

    it "empty document against empty schema is valid" do
      schema = build_schema
      doc = build_doc { |_b| }
      result = validator.validate(doc, schema)
      expect(result.valid?).to be true
    end
  end
end
