# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "golden_helper"

RSpec.describe "Golden Canonical Tests" do
  CANONICAL_GOLDEN_DIR = find_golden_dir

  def self.load_canonical_tests
    tests = []
    canonical_dir = File.join(CANONICAL_GOLDEN_DIR, "canonical")
    Dir[File.join(canonical_dir, "*.json")].sort.each do |json_file|
      suite = JSON.parse(File.read(json_file))
      suite_name = File.basename(json_file, ".json")
      (suite["tests"] || []).each do |test|
        tests << [test["id"] || "#{suite_name}-unknown", test, suite_name]
      end
    end
    tests
  end

  # No known gaps — all golden tests must pass

  load_canonical_tests.each do |id, test_case, suite_name|
    it "golden canonical: #{id}" do
      input = test_case["input"]

      if suite_name == "binary-output"
        # Binary output tests verify hex encoding and byte length
        expected = test_case["expected"]
        doc = Odin.parse(input)
        canonical = Odin.canonicalize(doc)
        canonical_bytes = canonical.encode("UTF-8").bytes

        expected_hex = expected["hex"]
        actual_hex = canonical_bytes.map { |b| format("%02x", b) }.join
        expect(actual_hex).to eq(expected_hex), "Hex mismatch for #{id}:\n  expected: #{expected_hex}\n  actual:   #{actual_hex}\n  text: #{canonical.inspect}"

        expect(canonical_bytes.length).to eq(expected["byteLength"]),
          "Byte length mismatch for #{id}: expected #{expected["byteLength"]}, got #{canonical_bytes.length}"
      else
        # Standard canonical tests: compare canonical string output
        expected_canonical = test_case["expected"]
        # Handle case where expected is a hash with "canonical" key
        if expected_canonical.is_a?(Hash)
          expected_canonical = expected_canonical["canonical"]
        end

        doc = Odin.parse(input)
        canonical = Odin.canonicalize(doc)
        expect(canonical.force_encoding("UTF-8")).to eq(expected_canonical),
          "Canonical mismatch for #{id}:\n  expected: #{expected_canonical.inspect}\n  actual:   #{canonical.inspect}"
      end
    end
  end
end
