# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "golden_helper"

RSpec.describe "Golden Diff Tests" do
  GOLDEN_DIFF_DIR = find_golden_dir

  def self.load_diff_tests
    tests = []
    diff_dir = File.join(GOLDEN_DIFF_DIR, "diff")
    Dir[File.join(diff_dir, "*.json")].sort.each do |json_file|
      suite = JSON.parse(File.read(json_file))
      (suite["tests"] || []).each do |test|
        tests << [test["id"] || File.basename(json_file, ".json"), test]
      end
    end
    tests
  end

  # No known gaps — all golden tests must pass

  load_diff_tests.each do |id, test_case|
    it "golden diff: #{id}" do
      doc_a = Odin.parse(test_case["doc1"])
      doc_b = Odin.parse(test_case["doc2"])
      d = Odin.diff(doc_a, doc_b)

      expected = test_case["expected"]

      if expected["isEmpty"] == true
        expect(d).to be_empty, "Expected empty diff for #{id} but got: added=#{d.added.length}, removed=#{d.removed.length}, changed=#{d.changed.length}, moved=#{d.moved.length}"
      elsif expected["isEmpty"] == false
        expect(d).not_to be_empty, "Expected non-empty diff for #{id}"
      end

      # Verify modifications (changed)
      if expected["modifications"]
        expect(d.changed.length).to eq(expected["modifications"].length),
          "Expected #{expected['modifications'].length} modifications but got #{d.changed.length} for #{id}"
        expected["modifications"].each_with_index do |exp, i|
          expect(d.changed[i].path).to eq(exp["path"]),
            "Expected modification path '#{exp['path']}' at index #{i} for #{id}"
        end
      end

      # Verify additions
      if expected["additions"]
        expect(d.added.length).to eq(expected["additions"].length),
          "Expected #{expected['additions'].length} additions but got #{d.added.length} for #{id}"
        expected["additions"].each_with_index do |exp, i|
          expect(d.added[i].path).to eq(exp["path"]),
            "Expected addition path '#{exp['path']}' at index #{i} for #{id}"
        end
      end

      # Verify deletions (removed)
      if expected["deletions"]
        expect(d.removed.length).to eq(expected["deletions"].length),
          "Expected #{expected['deletions'].length} deletions but got #{d.removed.length} for #{id}"
        expected["deletions"].each_with_index do |exp, i|
          expect(d.removed[i].path).to eq(exp["path"]),
            "Expected deletion path '#{exp['path']}' at index #{i} for #{id}"
        end
      end

      # Verify moves
      if expected["moves"]
        expect(d.moved.length).to eq(expected["moves"].length),
          "Expected #{expected['moves'].length} moves but got #{d.moved.length} for #{id}"
        expected["moves"].each_with_index do |exp, i|
          expect(d.moved[i].from_path).to eq(exp["fromPath"]),
            "Expected move fromPath '#{exp['fromPath']}' at index #{i} for #{id}"
          expect(d.moved[i].to_path).to eq(exp["toPath"]),
            "Expected move toPath '#{exp['toPath']}' at index #{i} for #{id}"
        end
      end

      # Roundtrip: patch(a, diff(a, b)) should produce doc equal to b
      patched = Odin.patch(doc_a, d)
      doc_b.paths.each do |path|
        expect(patched.get(path)).to eq(doc_b.get(path)),
          "Roundtrip failed at path '#{path}' for #{id}: expected #{doc_b.get(path)}, got #{patched.get(path)}"
      end
      expect(patched.paths.sort).to eq(doc_b.paths.sort),
        "Roundtrip path mismatch for #{id}: expected #{doc_b.paths.sort}, got #{patched.paths.sort}"
    end
  end
end
