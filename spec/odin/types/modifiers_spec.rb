# frozen_string_literal: true

require "spec_helper"

RSpec.describe Odin::Types::OdinModifiers do
  describe "construction" do
    it "defaults all flags to false" do
      m = described_class.new
      expect(m.required).to be false
      expect(m.confidential).to be false
      expect(m.deprecated).to be false
      expect(m.attr).to be_nil
    end

    it "accepts required flag" do
      m = described_class.new(required: true)
      expect(m.required).to be true
    end

    it "accepts confidential flag" do
      m = described_class.new(confidential: true)
      expect(m.confidential).to be true
    end

    it "accepts deprecated flag" do
      m = described_class.new(deprecated: true)
      expect(m.deprecated).to be true
    end

    it "accepts attr" do
      m = described_class.new(attr: "xml_attr")
      expect(m.attr).to eq("xml_attr")
    end

    it "accepts all flags combined" do
      m = described_class.new(required: true, confidential: true, deprecated: true)
      expect(m.required).to be true
      expect(m.confidential).to be true
      expect(m.deprecated).to be true
    end
  end

  describe "NONE constant" do
    it "exists and has all flags false" do
      expect(described_class::NONE.required).to be false
      expect(described_class::NONE.confidential).to be false
      expect(described_class::NONE.deprecated).to be false
    end

    it "is frozen" do
      expect(described_class::NONE).to be_frozen
    end
  end

  describe "#any?" do
    it "returns false when all flags false" do
      expect(described_class.new.any?).to be false
    end

    it "returns true when required" do
      expect(described_class.new(required: true).any?).to be true
    end

    it "returns true when confidential" do
      expect(described_class.new(confidential: true).any?).to be true
    end

    it "returns true when deprecated" do
      expect(described_class.new(deprecated: true).any?).to be true
    end
  end

  describe "equality" do
    it "equal modifiers are ==" do
      a = described_class.new(required: true)
      b = described_class.new(required: true)
      expect(a).to eq(b)
    end

    it "different modifiers are not ==" do
      a = described_class.new(required: true)
      b = described_class.new(confidential: true)
      expect(a).not_to eq(b)
    end

    it "hash is consistent with ==" do
      a = described_class.new(required: true, confidential: true)
      b = described_class.new(required: true, confidential: true)
      expect(a.hash).to eq(b.hash)
    end
  end

  describe "#to_s" do
    it "shows none for default" do
      expect(described_class.new.to_s).to include("none")
    end

    it "shows flags" do
      m = described_class.new(required: true, confidential: true)
      expect(m.to_s).to include("required")
      expect(m.to_s).to include("confidential")
    end
  end
end
