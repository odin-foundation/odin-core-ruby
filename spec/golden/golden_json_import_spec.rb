# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "golden_helper"

RSpec.describe "Golden JSON Import Tests" do
  JSON_IMPORT_GOLDEN_DIR = find_golden_dir

  # No known gaps — all golden tests must pass

  def self.load_json_import_tests
    tests = []
    import_dir = File.join(JSON_IMPORT_GOLDEN_DIR, "json-import")
    return tests unless File.directory?(import_dir)

    Dir[File.join(import_dir, "*.json")].sort.each do |json_file|
      next if File.basename(json_file) == "manifest.json"

      suite = JSON.parse(File.read(json_file))
      suite_name = suite["suite"] || File.basename(json_file, ".json")
      (suite["tests"] || []).each do |test|
        test_id = test["id"] || "unknown"
        tests << ["#{suite_name}/#{test_id}", test]
      end
    end
    tests
  end

  load_json_import_tests.each do |display_name, test_case|
    it "golden json-import: #{display_name}" do
      transform_text = test_case["transform"]
      input_data = test_case["input"]

      transform = Odin.parse_transform(transform_text)
      source = Odin::Transform::SourceParsers.parse_json(input_data.is_a?(String) ? input_data : JSON.generate(input_data))
      result = Odin.execute_transform(transform, source)

      expect(result.success?).to be(true), "Transform failed for #{test_case['id']}: #{result.errors.map(&:message).join(', ')}"

      expected = test_case["expected"]
      next unless expected && expected["output"]

      output_seg = result.output_dv&.get("output")
      expect(output_seg).not_to be_nil, "Missing 'output' segment for #{test_case['id']}"

      assert_golden_value_matches(output_seg, expected["output"], "output", test_case["id"])
    end
  end

  private

  def assert_golden_value_matches(actual, expected, path, test_id)
    case expected
    when Hash
      expected.each do |key, exp_val|
        act_val = actual&.get(key)
        expect(act_val).not_to be_nil, "[#{test_id}] Missing field '#{key}' at #{path}"
        assert_golden_value_matches(act_val, exp_val, "#{path}.#{key}", test_id)
      end
    when NilClass
      expect(actual.null?).to be(true), "[#{test_id}] Expected null at #{path}"
    when true, false
      expect(actual.as_bool).to eq(expected), "[#{test_id}] Bool mismatch at #{path}"
    when Integer
      expect(actual.as_int).to eq(expected), "[#{test_id}] Int mismatch at #{path}: #{actual.as_int} != #{expected}"
    when Float
      expect(actual.as_float).to be_within(0.00001).of(expected), "[#{test_id}] Float mismatch at #{path}"
    when String
      expect(actual.as_string).to eq(expected), "[#{test_id}] String mismatch at #{path}"
    end
  end
end
