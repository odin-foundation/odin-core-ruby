# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "golden_helper"

RSpec.describe "Golden Schema Tests" do
  SCHEMA_GOLDEN_DIR = find_golden_dir

  # No known gaps — all golden tests must pass

  def self.load_schema_tests
    tests = []
    schema_dir = File.join(SCHEMA_GOLDEN_DIR, "schema")
    manifest_file = File.join(schema_dir, "manifest.json")
    return tests unless File.exist?(manifest_file)

    manifest = JSON.parse(File.read(manifest_file))
    (manifest["testSuites"] || []).each do |suite|
      suite_path = File.join(schema_dir, suite["path"])
      next unless File.exist?(suite_path)

      suite_data = JSON.parse(File.read(suite_path))
      (suite_data["tests"] || []).each do |test|
        tests << [test["id"], test, suite["id"]]
      end
    end
    tests
  end

  # Map an ODIN value/type to the TS-shaped "kind" string used in fixtures.
  def field_type_kind(field)
    return "typeRef" if field.type_ref && field.field_type == Odin::Types::SchemaFieldType::REFERENCE &&
                        field.name == "_composition"

    case field.field_type
    when Odin::Types::SchemaFieldType::INTEGER then "integer"
    when Odin::Types::SchemaFieldType::NUMBER then "number"
    when Odin::Types::SchemaFieldType::CURRENCY then "currency"
    when Odin::Types::SchemaFieldType::PERCENT then "percent"
    when Odin::Types::SchemaFieldType::BOOLEAN then "boolean"
    when Odin::Types::SchemaFieldType::DATE then "date"
    when Odin::Types::SchemaFieldType::TIMESTAMP then "timestamp"
    when Odin::Types::SchemaFieldType::TIME then "time"
    when Odin::Types::SchemaFieldType::DURATION then "duration"
    when Odin::Types::SchemaFieldType::BINARY then "binary"
    when Odin::Types::SchemaFieldType::REFERENCE then "reference"
    when Odin::Types::SchemaFieldType::NULL then "null"
    else "string"
    end
  end

  def default_value_hash(value)
    case value
    when Odin::Types::OdinInteger then { "type" => "integer", "value" => value.value }
    when Odin::Types::OdinNumber then { "type" => "number", "value" => value.value }
    when Odin::Types::OdinCurrency then { "type" => "currency", "value" => value.value.to_f }
    when Odin::Types::OdinPercent then { "type" => "percent", "value" => value.value }
    when Odin::Types::OdinBoolean then { "type" => "boolean", "value" => value.value }
    when Odin::Types::OdinString then { "type" => "string", "value" => value.value }
    else {}
    end
  end

  def constraint_to_hash(c)
    case c
    when Odin::Types::BoundsConstraint then { "kind" => "bounds", "min" => c.min, "max" => c.max }
    when Odin::Types::PatternConstraint then { "kind" => "pattern", "pattern" => c.pattern }
    when Odin::Types::FormatConstraint then { "kind" => "format", "format" => c.format_name }
    when Odin::Types::EnumConstraint then { "kind" => "enum", "values" => c.values }
    when Odin::Types::UniqueConstraint then { "kind" => "unique" }
    else { "kind" => c.kind.to_s }
    end
  end

  def conditional_to_hash(cond)
    val = cond.value
    typed = if val == "true" || val == "false"
              val == "true"
            elsif val.to_s.match?(/\A-?\d+(\.\d+)?\z/)
              val.include?(".") ? val.to_f : val.to_i
            else
              val
            end
    { "field" => cond.field, "operator" => cond.operator, "value" => typed, "unless" => cond.unless }
  end

  def assert_field(field, a, label)
    expect(field).not_to(be_nil, "#{label} should be defined")

    if a["typeKind"]
      expect(field_type_kind(field)).to eq(a["typeKind"]), "#{label} type kind"
    end
    if a["typeRefName"]
      expect(field.type_ref.to_s.sub(/\A@+/, "")).to eq(a["typeRefName"]), "#{label} typeRef name"
    end
    expect(field.required).to eq(a["required"]), "#{label} required" if a.key?("required")
    expect(field.nullable).to eq(a["nullable"]), "#{label} nullable" if a.key?("nullable")
    expect(field.immutable).to eq(a["immutable"]), "#{label} immutable" if a.key?("immutable")
    expect(field.computed).to eq(a["computed"]), "#{label} computed" if a.key?("computed")
    expect(field.deprecated).to eq(a["deprecated"]), "#{label} deprecated" if a.key?("deprecated")

    if a["union"]
      expect(field.union?).to eq(true), "#{label} should be a union"
      kinds = field.union_members.map(&:to_s).sort
      expect(kinds).to eq(a["union"].sort), "#{label} union members"
    end

    if a["default"]
      expect(field.default_value).not_to(be_nil, "#{label} default value")
      actual = default_value_hash(field.default_value)
      a["default"].each do |k, v|
        expect(actual[k]).to eq(v), "#{label} default.#{k}"
      end
    end

    if a["constraints"]
      actual = field.constraints.map { |c| constraint_to_hash(c) }
      a["constraints"].each do |expected_c|
        found = actual.any? { |c| expected_c.all? { |k, v| c[k] == v } }
        expect(found).to eq(true),
          "#{label} should have constraint #{expected_c} (got #{actual})"
      end
    end

    if a["conditionals"]
      actual = field.conditionals.map { |c| conditional_to_hash(c) }
      a["conditionals"].each do |expected_cond|
        found = actual.any? { |c| expected_cond.all? { |k, v| c[k] == v } }
        expect(found).to eq(true),
          "#{label} should have conditional #{expected_cond} (got #{actual})"
      end
    end
  end

  def run_field_assertions(schema, assert_block, id)
    (assert_block["fields"] || {}).each do |field_path, a|
      assert_field(schema.fields[field_path], a, "[#{id}] field '#{field_path}'")
    end

    (assert_block["types"] || {}).each do |type_name, ta|
      type = schema.types[type_name]
      expect(type).not_to(be_nil, "[#{id}] type '#{type_name}' should be defined")
      (ta["fields"] || {}).each do |field_key, a|
        assert_field(type.fields[field_key], a, "[#{id}] type '#{type_name}' field '#{field_key}'")
      end
    end
  end

  load_schema_tests.each do |id, test_case, suite_id|
    it "schema/#{suite_id}/#{id}" do
      schema_text = test_case["schema"]
      expected = test_case["expected"]

      schema = Odin.parse_schema(schema_text)
      expect(schema).not_to be_nil, "Failed to parse schema for #{id}"

      # Value-level assertions (constraint values, union members, defaults, flags).
      run_field_assertions(schema, test_case["assert"], id) if test_case["assert"]

      next unless expected

      # Structural cases: assert nesting (field keys present), not full equality
      if test_case["structural"]
        (expected["types"] || {}).each do |type_name, type_def|
          actual_type = schema.types[type_name]
          expect(actual_type).not_to be_nil, "Missing type definition: #{type_name}"
          (type_def["fields"] || {}).each_key do |field_key|
            expect(actual_type.fields).to have_key(field_key),
              "Type #{type_name} missing field #{field_key}"
          end
        end
        (expected["fields"] || {}).each_key do |field_path|
          expect(schema.fields).to have_key(field_path),
            "Missing root field #{field_path}"
        end
        next
      end

      # Validate type definitions
      if expected["types"]
        expected["types"].each do |type_name, type_def|
          actual_type = schema.types[type_name]
          expect(actual_type).not_to be_nil, "Missing type definition: #{type_name}"

          if type_def["base"]
            expect(actual_type.base_type.to_s).to eq(type_def["base"]),
              "Type #{type_name} base mismatch: expected #{type_def['base']}, got #{actual_type.base_type}"
          end

          if type_def["constraints"]
            type_def["constraints"].each do |constraint_name, constraint_value|
              actual_constraint = actual_type.constraints[constraint_name] || actual_type.constraints[constraint_name.to_sym]
              expect(actual_constraint).not_to be_nil,
                "Missing constraint #{constraint_name} on type #{type_name}"
              expect(actual_constraint.to_s).to eq(constraint_value.to_s),
                "Constraint #{constraint_name} on type #{type_name}: expected #{constraint_value}, got #{actual_constraint}"
            end
          end

          if type_def["intersection"]
            expect(actual_type).to respond_to(:intersection_types),
              "Type #{type_name} should have intersection types"
          end
        end
      end

      # Validate field definitions
      if expected["fields"]
        expected["fields"].each do |field_path, field_def|
          actual_field = schema.fields[field_path]
          expect(actual_field).not_to be_nil, "Missing field definition: #{field_path}"

          if field_def["type"]
            expect(actual_field.type_ref.to_s).to eq(field_def["type"]),
              "Field #{field_path} type mismatch"
          end
        end
      end
    end
  end
end
