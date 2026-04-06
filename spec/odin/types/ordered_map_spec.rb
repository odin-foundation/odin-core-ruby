# frozen_string_literal: true

require "spec_helper"

RSpec.describe Odin::Types::OrderedMap do
  describe "basic operations" do
    it "preserves insertion order" do
      map = described_class.new
      map["b"] = 2
      map["a"] = 1
      map["c"] = 3
      expect(map.keys).to eq(["b", "a", "c"])
    end

    it "gets and sets values" do
      map = described_class.new
      map["key"] = "value"
      expect(map["key"]).to eq("value")
    end

    it "reports key existence" do
      map = described_class.new
      map["x"] = 1
      expect(map.key?("x")).to be true
      expect(map.key?("y")).to be false
    end

    it "deletes keys" do
      map = described_class.new
      map["x"] = 1
      map.delete("x")
      expect(map.key?("x")).to be false
    end

    it "reports size and empty?" do
      map = described_class.new
      expect(map.empty?).to be true
      expect(map.size).to eq(0)
      map["x"] = 1
      expect(map.empty?).to be false
      expect(map.size).to eq(1)
    end
  end

  describe "enumeration" do
    it "iterates in insertion order" do
      map = described_class.new
      map["a"] = 1
      map["b"] = 2
      pairs = map.map { |k, v| [k, v] }
      expect(pairs).to eq([["a", 1], ["b", 2]])
    end
  end

  describe "freeze" do
    it "prevents modification" do
      map = described_class.new
      map["x"] = 1
      map.freeze
      expect(map).to be_frozen
      expect { map["y"] = 2 }.to raise_error(FrozenError)
    end
  end

  describe "initialization from hash" do
    it "copies the hash" do
      h = { "a" => 1, "b" => 2 }
      map = described_class.new(h)
      expect(map["a"]).to eq(1)
      h["c"] = 3
      expect(map.key?("c")).to be false
    end
  end

  describe "equality" do
    it "equals another OrderedMap with same entries" do
      a = described_class.new({ "x" => 1 })
      b = described_class.new({ "x" => 1 })
      expect(a).to eq(b)
    end

    it "equals a Hash with same entries" do
      a = described_class.new({ "x" => 1 })
      expect(a).to eq({ "x" => 1 })
    end
  end

  describe "#to_h" do
    it "returns a plain hash copy" do
      map = described_class.new({ "a" => 1 })
      h = map.to_h
      expect(h).to be_a(Hash)
      expect(h).to eq({ "a" => 1 })
    end
  end

  describe "#dup" do
    it "creates independent copy" do
      map = described_class.new({ "a" => 1 })
      copy = map.dup
      copy["b"] = 2
      expect(map.key?("b")).to be false
    end
  end

  describe "#merge" do
    it "merges entries" do
      map = described_class.new({ "a" => 1 })
      result = map.merge({ "b" => 2 })
      expect(result["a"]).to eq(1)
      expect(result["b"]).to eq(2)
      expect(map.key?("b")).to be false
    end
  end
end
