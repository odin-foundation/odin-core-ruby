# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "golden_helper"

RSpec.describe "Golden Validate Tests" do
  VALIDATE_GOLDEN_DIR = find_golden_dir

  # No known gaps — all golden tests must pass

  def self.load_validate_tests
    tests = []
    validate_dir = File.join(VALIDATE_GOLDEN_DIR, "validate")
    manifest_file = File.join(validate_dir, "manifest.json")
    return tests unless File.exist?(manifest_file)

    manifest = JSON.parse(File.read(manifest_file))
    (manifest["testSuites"] || []).each do |suite|
      suite_path = File.join(validate_dir, suite["path"])
      next unless File.exist?(suite_path)

      suite_data = JSON.parse(File.read(suite_path))
      (suite_data["tests"] || []).each do |test|
        tests << [test["id"], test, suite["id"]]
      end
    end
    tests
  end

  load_validate_tests.each do |id, test_case, suite_id|
    it "validate/#{suite_id}/#{id}" do
      schema_text = test_case["schema"]
      input_text = test_case["input"]
      expected = test_case["expected"]
      test_options = test_case["options"] || {}

      schema = Odin.parse_schema(schema_text)
      doc = Odin.parse(input_text)
      validate_opts = {}
      validate_opts[:strict] = test_options["strict"] if test_options.key?("strict")
      result = Odin.validate(doc, schema, validate_opts)

      if expected["valid"] == true
        expect(result.valid?).to eq(true),
          "Expected valid for #{id}, got errors: #{result.errors.map(&:message).join(', ')}"
      else
        expect(result.valid?).to eq(false),
          "Expected invalid for #{id}, but validation passed"

        if expected["errors"]
          expected["errors"].each do |exp_error|
            if exp_error["code"]
              matching = result.errors.find { |e| e.code == exp_error["code"] }
              expect(matching).not_to be_nil,
                "Expected error code #{exp_error['code']} for #{id}, got: #{result.errors.map(&:code).join(', ')}"

              if exp_error["path"]
                expect(matching.path).to eq(exp_error["path"]),
                  "Error path mismatch for #{id}: expected #{exp_error['path']}, got #{matching.path}"
              end
            end
          end
        end

        if expected["error"]
          # Single error message match
          expect(result.errors).not_to be_empty,
            "Expected error '#{expected['error']}' for #{id}"
        end
      end
    end
  end
end
