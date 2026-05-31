# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe "Registry-aware schema validation" do
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

  describe "imported typeref resolves via the import resolver" do
    # Two tiny inline schemas served from memory: a main schema importing a
    # `types` schema, with a top-level field referencing @types.policy_status.
    main_schema = <<~ODIN
      @import "./types.schema.odin" as types

      {$}
      odin = "1.0.0"

      status = !@types.policy_status
    ODIN
    types_schema = <<~ODIN
      {$}
      odin = "1.0.0"

      {@policy_status}
      value = !
    ODIN

    # In-memory file reader: keys imports by basename, no disk access.
    let(:loader) do
      files = { "types.schema.odin" => types_schema }
      ->(abs) { files.fetch(File.basename(abs)) }
    end
    let(:schema) { Odin.parse_schema(main_schema) }
    let(:doc) { Odin.parse("status = \"active\"") }
    let(:registry) do
      _flat, reg = Odin::Resolver::ImportResolver.new(loader: loader)
                                                 .resolve_with_registry(schema, base_path: "main.schema.odin")
      reg
    end

    it "namespaces the imported type by alias" do
      expect(registry.has?("types.policy_status")).to be true
    end

    it "reports V013 without a registry" do
      expect(unresolved_ref_count(Odin.validate(doc, schema))).to eq(1)
    end

    it "resolves the imported type with the resolver-built registry (V013 -> 0)" do
      expect(unresolved_ref_count(Odin.validate(doc, schema, {}, registry))).to eq(0)
    end
  end

  describe "relative-subsection nesting" do
    it "nests term.* into the @policy type, not the schema root" do
      schema = Odin.parse_schema(<<~ODIN)
        {@policy}
        number = !

        {.term}
        effective = !date
        expiration = !date
      ODIN
      expect(schema.types["policy"].fields).to include("term.effective", "term.expiration")
      expect(schema.fields).not_to have_key("term.effective")
      expect(schema.fields).not_to have_key("term.expiration")
    end
  end
end
