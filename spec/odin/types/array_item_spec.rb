# frozen_string_literal: true

require "spec_helper"

RSpec.describe Odin::Types::OdinArrayItem do
  describe ".from_value" do
    it "creates a value item" do
      val = Odin::Types::OdinString.new("test")
      item = described_class.from_value(val)
      expect(item.kind).to eq(:value)
      expect(item.value?).to be true
      expect(item.record?).to be false
      expect(item.value).to eq(val)
    end
  end

  describe ".record" do
    it "creates a record item" do
      fields = { "name" => Odin::Types::OdinString.new("test") }
      item = described_class.record(fields)
      expect(item.kind).to eq(:record)
      expect(item.record?).to be true
      expect(item.value?).to be false
      expect(item.fields).to eq(fields)
    end
  end

  it "is frozen" do
    expect(described_class.from_value(Odin::Types::NULL)).to be_frozen
  end

  it "equality works" do
    a = described_class.from_value(Odin::Types::OdinInteger.new(1))
    b = described_class.from_value(Odin::Types::OdinInteger.new(1))
    expect(a).to eq(b)
  end
end
