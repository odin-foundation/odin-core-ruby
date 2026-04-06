# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "golden_helper"

RSpec.describe "Golden Parse Tests" do
  GOLDEN_DIR = find_golden_dir

  def self.load_parse_tests
    tests = []
    parse_dir = File.join(GOLDEN_DIR, "parse")
    Dir[File.join(parse_dir, "**", "*.json")].sort.each do |json_file|
      next if File.basename(json_file) == "manifest.json"
      suite = JSON.parse(File.read(json_file))
      (suite["tests"] || []).each do |test|
        tests << [test["id"] || File.basename(json_file, ".json"), test, File.basename(json_file)]
      end
    end
    tests
  end

  # No known gaps — all golden tests must pass

  load_parse_tests.each do |id, test_case, file|
    it "golden parse: #{id}" do
      # Skip planned/not-implemented tests
      pending "Planned test" if test_case["status"] == "planned"

      input_text = test_case["input"]

      if test_case["expectError"]
        expect { Odin.parse(input_text) }.to raise_error(Odin::Errors::ParseError) do |err|
          if test_case["expectError"]["code"]
            expect(err.code).to eq(test_case["expectError"]["code"])
          end
        end
        next
      end

      doc = Odin.parse(input_text)
      expected = test_case["expected"]

      # Handle documents array (chaining tests)
      if expected["documents"]
        if doc.respond_to?(:documents)
          docs = doc.documents
          expected["documents"].each_with_index do |exp_doc, i|
            actual_doc = docs[i]
            next unless actual_doc

            assert_assignments(actual_doc, exp_doc["assignments"]) if exp_doc["assignments"]
            assert_metadata(actual_doc, exp_doc["metadata"]) if exp_doc["metadata"]
          end
        else
          # Single document - check first expected doc
          exp_doc = expected["documents"][0]
          assert_assignments(doc, exp_doc["assignments"]) if exp_doc["assignments"]
          assert_metadata(doc, exp_doc["metadata"]) if exp_doc["metadata"]
        end
        next
      end

      assert_assignments(doc, expected["assignments"]) if expected["assignments"]
      assert_metadata(doc, expected["metadata"]) if expected["metadata"]
      assert_modifiers(doc, expected["modifiers"]) if expected["modifiers"]
      assert_directives(doc, expected["directives"]) if expected["directives"]

      if expected["pathCount"]
        expect(doc.size).to eq(expected["pathCount"])
      end
    end
  end

  private

  def assert_assignments(doc, expected_assignments)
    return unless expected_assignments
    expected_assignments.each do |path, expected_value|
      actual = doc.get(path)
      # Check metadata for $.key paths
      if actual.nil? && path.start_with?("$.")
        meta_key = path[2..]
        actual = doc.metadata[meta_key] if doc.respond_to?(:metadata)
      end
      expect(actual).not_to be_nil, "Missing path: #{path}"
      assert_value_matches(actual, expected_value, path)
    end
  end

  def assert_metadata(doc, expected_metadata)
    return unless expected_metadata
    expected_metadata.each do |key, expected_value|
      actual = doc.metadata[key]
      if expected_value.is_a?(String)
        expect(actual).not_to be_nil, "Missing metadata key: #{key}"
        actual_val = actual.value
        actual_val = actual_val.to_s if actual_val.is_a?(Date) || actual_val.is_a?(Time)
        expect(actual_val).to eq(expected_value)
      elsif expected_value.is_a?(Hash)
        expect(actual).not_to be_nil, "Missing metadata key: #{key}"
        assert_value_matches(actual, expected_value, "$.#{key}")
      end
    end
  end

  def assert_modifiers(doc, expected_modifiers)
    return unless expected_modifiers
    expected_modifiers.each do |path, exp_mods|
      actual = doc.get(path)
      expect(actual).not_to be_nil, "Missing path for modifier check: #{path}"
      expect(actual.required?).to eq(exp_mods["required"] || false) if exp_mods.key?("required")
      expect(actual.confidential?).to eq(exp_mods["confidential"] || false) if exp_mods.key?("confidential")
      expect(actual.deprecated?).to eq(exp_mods["deprecated"] || false) if exp_mods.key?("deprecated")
    end
  end

  def assert_directives(doc, expected_directives)
    return unless expected_directives
    # Directives are stored on ParseResult
    return unless doc.respond_to?(:raw_documents)
    actual_dirs = doc.raw_documents&.first&.[](:directives) || []
    expected_directives.each_with_index do |exp, i|
      act = actual_dirs[i]
      expect(act).not_to be_nil, "Missing directive at index #{i}"
      expect(act[:type]).to eq(exp["type"])
      expect(act[:path]).to eq(exp["path"]) if exp.key?("path")
      expect(act[:alias]).to eq(exp["alias"]) if exp.key?("alias")
      expect(act[:url]).to eq(exp["url"]) if exp.key?("url")
      expect(act[:condition]).to eq(exp["condition"]) if exp.key?("condition")
    end
  end

  def assert_value_matches(actual, expected, path_context = "")
    return unless expected.is_a?(Hash)
    exp_type = expected["type"]

    case exp_type
    when "string"
      expect(actual.type).to eq(:string), "Expected string at #{path_context}, got #{actual.type}"
      expect(actual.value).to eq(expected["value"])
    when "integer"
      expect(actual.type).to eq(:integer), "Expected integer at #{path_context}, got #{actual.type}"
      if expected.key?("raw")
        expect(actual.raw).to eq(expected["raw"])
      else
        expect(actual.value).to eq(expected["value"])
      end
    when "number"
      expect(actual.type).to eq(:number), "Expected number at #{path_context}, got #{actual.type}"
      if expected.key?("raw")
        expect(actual.raw).to eq(expected["raw"])
      end
      if expected.key?("value")
        expect(actual.value).to be_within(1e-10).of(expected["value"])
      end
    when "boolean"
      expect(actual.type).to eq(:boolean), "Expected boolean at #{path_context}, got #{actual.type}"
      expect(actual.value).to eq(expected["value"])
    when "null"
      expect(actual.type).to eq(:null), "Expected null at #{path_context}, got #{actual.type}"
    when "currency"
      expect(actual.type).to eq(:currency), "Expected currency at #{path_context}, got #{actual.type}"
      if expected.key?("value")
        expect(actual.value.to_f).to be_within(1e-10).of(expected["value"])
      end
      if expected.key?("raw")
        expect(actual.raw).to eq(expected["raw"])
      end
      expect(actual.currency_code).to eq(expected["currencyCode"]) if expected.key?("currencyCode")
      expect(actual.decimal_places).to eq(expected["decimalPlaces"]) if expected.key?("decimalPlaces")
    when "date"
      expect(actual.type).to eq(:date), "Expected date at #{path_context}, got #{actual.type}"
      if expected.key?("value")
        expect(actual.raw).to eq(expected["value"].to_s)
      end
      if expected.key?("raw")
        expect(actual.raw).to eq(expected["raw"])
      end
    when "timestamp"
      expect(actual.type).to eq(:timestamp), "Expected timestamp at #{path_context}, got #{actual.type}"
      if expected.key?("value")
        expect(actual.raw).to eq(expected["value"].to_s)
      end
      if expected.key?("raw")
        expect(actual.raw).to eq(expected["raw"])
      end
    when "time"
      expect(actual.type).to eq(:time), "Expected time at #{path_context}, got #{actual.type}"
      expect(actual.value).to eq(expected["value"]) if expected.key?("value")
    when "duration"
      expect(actual.type).to eq(:duration), "Expected duration at #{path_context}, got #{actual.type}"
      expect(actual.value).to eq(expected["value"]) if expected.key?("value")
    when "reference"
      expect(actual.type).to eq(:reference), "Expected reference at #{path_context}, got #{actual.type}"
      if expected.key?("value")
        expect(actual.path).to eq(expected["value"])
      end
      if expected.key?("path")
        expect(actual.path).to eq(expected["path"])
      end
    when "binary"
      expect(actual.type).to eq(:binary), "Expected binary at #{path_context}, got #{actual.type}"
      expect(actual.algorithm).to eq(expected["algorithm"]) if expected.key?("algorithm")
      if expected.key?("value")
        expect(actual.data).to eq(expected["value"])
      end
    when "percent"
      expect(actual.type).to eq(:percent), "Expected percent at #{path_context}, got #{actual.type}"
      if expected.key?("value")
        expect(actual.value).to be_within(1e-10).of(expected["value"])
      end
    when "verb"
      expect(actual.type).to eq(:verb), "Expected verb at #{path_context}, got #{actual.type}"
    end

    # Check modifiers on value
    if expected["modifiers"]
      mods = expected["modifiers"]
      if mods.is_a?(Array)
        # Array format: ["confidential", "required", ...]
        expect(actual.required?).to eq(mods.include?("required"))
        expect(actual.confidential?).to eq(mods.include?("confidential"))
        expect(actual.deprecated?).to eq(mods.include?("deprecated"))
      elsif mods.is_a?(Hash)
        expect(actual.required?).to eq(mods["required"] || false) if mods.key?("required")
        expect(actual.confidential?).to eq(mods["confidential"] || false) if mods.key?("confidential")
        expect(actual.deprecated?).to eq(mods["deprecated"] || false) if mods.key?("deprecated")
      end
    end
  end
end
