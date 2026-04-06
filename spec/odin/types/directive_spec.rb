# frozen_string_literal: true

require "spec_helper"

RSpec.describe Odin::Types::OdinDirective do
  it "stores name and value" do
    d = described_class.new("type", "string")
    expect(d.name).to eq("type")
    expect(d.value).to eq("string")
  end

  it "value defaults to nil" do
    d = described_class.new("required")
    expect(d.value).to be_nil
  end

  it "is frozen" do
    expect(described_class.new("x")).to be_frozen
  end

  it "equality works" do
    a = described_class.new("type", "int")
    b = described_class.new("type", "int")
    c = described_class.new("type", "string")
    expect(a).to eq(b)
    expect(a).not_to eq(c)
  end

  it "hash is consistent with ==" do
    a = described_class.new("x", "y")
    b = described_class.new("x", "y")
    expect(a.hash).to eq(b.hash)
  end

  it "to_s includes name" do
    expect(described_class.new("type", "int").to_s).to include("type")
  end
end
