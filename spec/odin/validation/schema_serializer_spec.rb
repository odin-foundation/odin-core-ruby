# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Odin::Validation::SchemaSerializer do
  let(:serializer) { described_class.new }

  def build_schema(**opts)
    Odin::Types::OdinSchema.new(**opts)
  end

  def string_field(name, **opts)
    Odin::Types::SchemaField.new(name: name, field_type: :string, **opts)
  end

  def integer_field(name, **opts)
    Odin::Types::SchemaField.new(name: name, field_type: :integer, **opts)
  end

  # ── Roundtrip ──

  describe "roundtrip" do
    it "serializes and re-parses producing equivalent schema" do
      schema = build_schema(
        metadata: { "odin" => "1.0.0", "schema" => "1.0.0" },
        fields: { "name" => string_field("name", required: true) }
      )
      text = serializer.serialize(schema)
      reparsed = Odin::Validation::SchemaParser.new.parse_schema(text)
      expect(reparsed.metadata["odin"]).to eq("1.0.0")
    end

    it "preserves type definitions through roundtrip" do
      type_fields = { "line1" => string_field("line1", required: true) }
      types = { "address" => Odin::Types::SchemaType.new(name: "address", fields: type_fields) }
      schema = build_schema(metadata: { "odin" => "1.0.0" }, types: types)
      text = serializer.serialize(schema)
      expect(text).to include("address")
      expect(text).to include("line1")
    end

    it "preserves constraints through serialization" do
      bounds = Odin::Types::BoundsConstraint.new(min: 0, max: 150)
      schema = build_schema(
        metadata: { "odin" => "1.0.0" },
        fields: { "age" => integer_field("age", constraints: [bounds]) }
      )
      text = serializer.serialize(schema)
      expect(text).to include(":(0..150)")
    end

    it "preserves pattern constraints" do
      pattern = Odin::Types::PatternConstraint.new(pattern: "^[A-Z]+$")
      schema = build_schema(
        metadata: { "odin" => "1.0.0" },
        fields: { "code" => string_field("code", constraints: [pattern]) }
      )
      text = serializer.serialize(schema)
      expect(text).to include(":/^[A-Z]+$/")
    end

    it "preserves enum constraints" do
      enum = Odin::Types::EnumConstraint.new(values: ["a", "b", "c"])
      schema = build_schema(
        metadata: { "odin" => "1.0.0" },
        fields: { "status" => string_field("status", constraints: [enum]) }
      )
      text = serializer.serialize(schema)
      expect(text).to include("(a, b, c)")
    end
  end

  # ── Output format ──

  describe "output format" do
    it "includes metadata header" do
      schema = build_schema(metadata: { "odin" => "1.0.0" })
      text = serializer.serialize(schema)
      expect(text).to include("{$}")
    end

    it "includes type definition headers" do
      types = { "user" => Odin::Types::SchemaType.new(name: "user") }
      schema = build_schema(metadata: { "odin" => "1.0.0" }, types: types)
      text = serializer.serialize(schema)
      expect(text).to include("{@user}")
    end

    it "serializes required modifier as !" do
      schema = build_schema(
        metadata: { "odin" => "1.0.0" },
        fields: { "name" => string_field("name", required: true) }
      )
      text = serializer.serialize(schema)
      expect(text).to include("!")
    end

    it "serializes integer type as ##" do
      schema = build_schema(
        metadata: { "odin" => "1.0.0" },
        fields: { "count" => integer_field("count") }
      )
      text = serializer.serialize(schema)
      expect(text).to include("##")
    end

    it "serializes array definitions" do
      arrays = {
        "items" => Odin::Types::SchemaArray.new(
          path: "items",
          item_fields: { "name" => string_field("name") },
          min_items: 1,
          max_items: 10
        ),
      }
      schema = build_schema(metadata: { "odin" => "1.0.0" }, arrays: arrays)
      text = serializer.serialize(schema)
      expect(text).to include("{items[]}")
      expect(text).to include(":(1..10)")
    end

    it "serializes unique constraint" do
      arrays = {
        "tags" => Odin::Types::SchemaArray.new(path: "tags", unique: true),
      }
      schema = build_schema(metadata: { "odin" => "1.0.0" }, arrays: arrays)
      text = serializer.serialize(schema)
      expect(text).to include(":unique")
    end

    it "serializes format constraint" do
      fmt = Odin::Types::FormatConstraint.new(format_name: "email")
      schema = build_schema(
        metadata: { "odin" => "1.0.0" },
        fields: { "email" => string_field("email", constraints: [fmt]) }
      )
      text = serializer.serialize(schema)
      expect(text).to include(":format email")
    end

    it "serializes conditionals" do
      cond = Odin::Types::SchemaConditional.new(field: "method", operator: "=", value: "card")
      schema = build_schema(
        metadata: { "odin" => "1.0.0" },
        fields: {
          "card_number" => string_field("card_number", required: true, conditionals: [cond]),
        }
      )
      text = serializer.serialize(schema)
      expect(text).to include(":if method = card")
    end

    it "serializes invariant constraints" do
      invariant = Odin::Types::SchemaInvariant.new(expression: "end >= start")
      schema = build_schema(
        metadata: { "odin" => "1.0.0" },
        object_constraints: { "range" => [invariant] }
      )
      text = serializer.serialize(schema)
      expect(text).to include(":invariant end >= start")
    end
  end
end
