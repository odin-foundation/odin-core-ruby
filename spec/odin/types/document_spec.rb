# frozen_string_literal: true

require "spec_helper"

RSpec.describe Odin::Types::OdinDocument do
  let(:str_val) { Odin::Types::OdinString.new("hello") }
  let(:int_val) { Odin::Types::OdinInteger.new(42) }
  let(:mods) { Odin::Types::OdinModifiers.new(required: true) }

  let(:doc) do
    described_class.new(
      assignments: { "name" => str_val, "age" => int_val },
      metadata: { "odin" => Odin::Types::OdinString.new("1.0.0") },
      modifiers: { "name" => mods },
      comments: { "age" => "person's age" }
    )
  end

  describe "#get / #[]" do
    it "returns value by path" do
      expect(doc.get("name")).to eq(str_val)
      expect(doc["age"]).to eq(int_val)
    end

    it "returns nil for missing path" do
      expect(doc.get("missing")).to be_nil
    end
  end

  describe "#paths" do
    it "returns all paths in insertion order" do
      expect(doc.paths).to eq(["name", "age"])
    end
  end

  describe "#include? / #has_path?" do
    it "returns true for existing path" do
      expect(doc.include?("name")).to be true
      expect(doc.has_path?("age")).to be true
    end

    it "returns false for missing path" do
      expect(doc.include?("missing")).to be false
    end
  end

  describe "#size / #length" do
    it "returns assignment count" do
      expect(doc.size).to eq(2)
      expect(doc.length).to eq(2)
    end
  end

  describe "#metadata" do
    it "returns metadata hash" do
      expect(doc.metadata["odin"]).to eq(Odin::Types::OdinString.new("1.0.0"))
    end
  end

  describe "#modifiers_for" do
    it "returns modifiers for a path" do
      expect(doc.modifiers_for("name")).to eq(mods)
    end

    it "returns nil for path without modifiers" do
      expect(doc.modifiers_for("age")).to be_nil
    end
  end

  describe "#comment_for" do
    it "returns comment for a path" do
      expect(doc.comment_for("age")).to eq("person's age")
    end

    it "returns nil for path without comment" do
      expect(doc.comment_for("name")).to be_nil
    end
  end

  describe "#empty?" do
    it "returns false for non-empty doc" do
      expect(doc.empty?).to be false
    end

    it "returns true for empty doc" do
      empty = described_class.new(assignments: {}, metadata: {}, modifiers: {}, comments: {})
      expect(empty.empty?).to be true
    end
  end

  describe "#each_assignment" do
    it "yields each path-value pair" do
      pairs = []
      doc.each_assignment { |path, val| pairs << [path, val] }
      expect(pairs).to eq([["name", str_val], ["age", int_val]])
    end
  end

  describe "#each_metadata" do
    it "yields each metadata pair" do
      pairs = []
      doc.each_metadata { |key, val| pairs << key }
      expect(pairs).to eq(["odin"])
    end
  end

  describe "immutability" do
    it "document is frozen" do
      expect(doc).to be_frozen
    end
  end

  describe ".empty" do
    it "creates an empty document" do
      e = described_class.empty
      expect(e.empty?).to be true
      expect(e.size).to eq(0)
    end
  end

  describe "equality" do
    it "equal documents are ==" do
      a = described_class.new(assignments: { "x" => str_val }, metadata: {}, modifiers: {}, comments: {})
      b = described_class.new(assignments: { "x" => str_val }, metadata: {}, modifiers: {}, comments: {})
      expect(a).to eq(b)
    end

    it "different documents are not ==" do
      a = described_class.new(assignments: { "x" => str_val }, metadata: {}, modifiers: {}, comments: {})
      b = described_class.new(assignments: { "y" => str_val }, metadata: {}, modifiers: {}, comments: {})
      expect(a).not_to eq(b)
    end
  end
end
