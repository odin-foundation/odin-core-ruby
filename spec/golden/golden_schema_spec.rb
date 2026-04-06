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

  load_schema_tests.each do |id, test_case, suite_id|
    it "schema/#{suite_id}/#{id}" do
      schema_text = test_case["schema"]
      expected = test_case["expected"]

      schema = Odin.parse_schema(schema_text)
      expect(schema).not_to be_nil, "Failed to parse schema for #{id}"

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
