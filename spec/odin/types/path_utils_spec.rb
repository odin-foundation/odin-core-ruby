# frozen_string_literal: true

require "spec_helper"

RSpec.describe Odin::Utils::PathUtils do
  describe ".build" do
    it "joins segments with dots" do
      expect(described_class.build("a", "b", "c")).to eq("a.b.c")
    end

    it "skips empty segments" do
      expect(described_class.build("a", "", "c")).to eq("a.c")
    end

    it "handles single segment" do
      expect(described_class.build("a")).to eq("a")
    end
  end

  describe ".split" do
    it "splits on dots" do
      expect(described_class.split("a.b.c")).to eq(["a", "b", "c"])
    end

    it "handles array indices" do
      expect(described_class.split("items[0].name")).to eq(["items", "[0]", "name"])
    end
  end

  describe ".parent" do
    it "returns parent path" do
      expect(described_class.parent("a.b.c")).to eq("a.b")
    end

    it "returns nil for root" do
      expect(described_class.parent("root")).to be_nil
    end
  end

  describe ".leaf" do
    it "returns last segment" do
      expect(described_class.leaf("a.b.c")).to eq("c")
    end

    it "returns whole path if no dots" do
      expect(described_class.leaf("root")).to eq("root")
    end
  end
end
