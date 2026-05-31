# frozen_string_literal: true

require_relative "../../spec_helper"
require "date"

RSpec.describe "Registry-aware schema validation" do
  CANONICAL_POLICY_SCHEMA =
    File.expand_path("../../../../../../schemas/insurance/personal/auto/policy.schema.odin", __FILE__)

  def unresolved_ref_count(result)
    result.errors.count { |e| e.code == Odin::Errors::ValidationErrorCode::UNRESOLVED_REFERENCE }
  end

  describe "import alias and quote handling" do
    it "strips quotes and honors the 'as' alias" do
      schema = Odin.parse_schema(<<~ODIN)
        @import "../../common/types.schema.odin" as types

        {$}
        odin = "1.0.0"
      ODIN
      imp = schema.imports.first
      expect(imp.path).to eq("../../common/types.schema.odin")
      expect(imp.alias_name).to eq("types")
    end
  end

  describe "V013 resolution via registry" do
    let(:schema) do
      Odin.parse_schema(<<~ODIN)
        @import "./types.schema.odin" as types

        {$}
        odin = "1.0.0"

        status = !@types.policy_status
      ODIN
    end
    let(:doc) { Odin.parse("status = \"active\"") }

    it "reports V013 without a registry" do
      expect(unresolved_ref_count(Odin.validate(doc, schema))).to eq(1)
    end

    it "resolves the imported type with a registry (V013 -> 0)" do
      registry = Odin::Resolver::TypeRegistry.new
      registry.register_all(
        { "policy_status" => Odin::Types::SchemaType.new(name: "policy_status") },
        "types"
      )
      expect(unresolved_ref_count(Odin.validate(doc, schema, {}, registry))).to eq(0)
    end
  end

  describe "canonical policy schema with resolved imports" do
    let(:schema) { Odin.parse_schema(File.read(CANONICAL_POLICY_SCHEMA, encoding: "UTF-8")) }

    it "builds a registry namespacing imported types by alias" do
      _flat, registry = Odin::Resolver::ImportResolver.new
                                                      .resolve_with_registry(schema, base_path: CANONICAL_POLICY_SCHEMA)
      expect(registry.has?("types.policy_status")).to be true
    end

    it "nests term.* into the @policy type, not the schema root" do
      expect(schema.types["policy"].fields).to include("term.effective", "term.expiration")
    end

    it "yields no root required-field errors for an empty document" do
      result = Odin.validate_with_imports(Odin.parse(""), schema, CANONICAL_POLICY_SCHEMA)
      required_missing = result.errors.count do |e|
        e.code == Odin::Errors::ValidationErrorCode::REQUIRED_FIELD_MISSING
      end
      expect(required_missing).to eq(0)
    end

    it "validates a minimal satisfying document clean" do
      b = Odin.builder
      b.set(".term.effective", Odin::Types::OdinDate.new(Date.new(2025, 1, 1)))
      b.set(".term.expiration", Odin::Types::OdinDate.new(Date.new(2025, 12, 31)))
      result = Odin.validate_with_imports(b.build, schema, CANONICAL_POLICY_SCHEMA)
      expect(result.valid?).to be true
    end
  end
end
