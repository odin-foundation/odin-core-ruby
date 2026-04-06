# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "golden_helper"

RSpec.describe "Golden Try-It Verb Tests" do
  TRYIT_GOLDEN_DIR = find_golden_dir

  # No known gaps — all golden tests must pass

  def self.discover_try_it_tests
    tests = []
    try_it_dir = File.join(TRYIT_GOLDEN_DIR, "transform", "verbs", "try-it")
    return tests unless File.directory?(try_it_dir)

    Dir[File.join(try_it_dir, "*.expected.odin")].sort.each do |expected_file|
      verb_name = File.basename(expected_file).sub(".expected.odin", "")
      input_file = File.join(try_it_dir, "#{verb_name}.input.json")
      transform_file = File.join(try_it_dir, "#{verb_name}.transform.odin")

      next unless File.exist?(input_file) && File.exist?(transform_file)

      tests << [verb_name, input_file, transform_file, expected_file]
    end
    tests
  end

  discover_try_it_tests.each do |verb_name, input_file, transform_file, expected_file|
    it "try-it/#{verb_name}" do
      # All tests must pass — no skipping

      source = JSON.parse(File.read(input_file, encoding: "UTF-8"))
      transform_text = File.read(transform_file, encoding: "UTF-8").gsub("\r\n", "\n")
      expected_odin = File.read(expected_file, encoding: "UTF-8").gsub("\r\n", "\n").strip

      parser = Odin::Transform::TransformParser.new
      transform_def = parser.parse(transform_text)

      # Ensure target format is odin for formatted output
      unless transform_def.target_format
        transform_def.header.instance_variable_set(:@target_format, "odin")
      end

      engine = Odin::Transform::TransformEngine.new
      result = engine.execute(transform_def, source)

      expect(result.formatted).not_to be_nil,
        "No formatted output for verb '#{verb_name}'"

      actual = result.formatted.gsub("\r\n", "\n").strip

      expect(actual).to eq(expected_odin),
        "Output mismatch for verb '#{verb_name}':\n  EXPECTED:\n#{expected_odin}\n  ACTUAL:\n#{actual}"
    end
  end
end
