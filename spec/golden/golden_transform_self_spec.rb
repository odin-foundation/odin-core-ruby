# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "golden_helper"

RSpec.describe "Golden Transform Self Tests" do
  SELF_TEST_GOLDEN_DIR = find_golden_dir

  # No known gaps — all golden tests must pass

  def self.discover_self_tests
    tests = []
    verb_dir = File.join(SELF_TEST_GOLDEN_DIR, "transform", "verbs")
    return tests unless File.directory?(verb_dir)

    Dir[File.join(verb_dir, "*.test.odin")].sort.each do |test_file|
      verb_name = File.basename(test_file, ".test.odin")
      tests << [verb_name, test_file]
    end
    tests
  end

  discover_self_tests.each do |verb_name, test_file|
    it "self-test/#{verb_name}" do
      # All tests must pass — no skipping

      transform_text = File.read(test_file, encoding: "UTF-8").gsub("\r\n", "\n")

      parser = Odin::Transform::TransformParser.new
      transform_def = parser.parse(transform_text)

      engine = Odin::Transform::TransformEngine.new
      result = engine.execute(transform_def, {})

      output = result.output
      expect(output).not_to be_nil, "No output for #{verb_name}"

      # The output should have a TestResult key
      test_result = output["TestResult"]
      expect(test_result).not_to be_nil, "No TestResult segment in output for #{verb_name}"

      success_field = test_result["success"]
      expect(success_field).not_to be_nil, "No success field in TestResult for #{verb_name}"

      passed = test_result["passed"]
      failed = test_result["failed"]
      total = test_result["total"]

      detail = "[#{verb_name}] passed=#{passed}, failed=#{failed}, total=#{total}"

      # success should be true
      expect(success_field).to eq(true), "Self-test FAILED: #{detail}"
    end
  end
end
