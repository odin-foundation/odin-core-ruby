# frozen_string_literal: true

require "spec_helper"

RSpec.describe Odin::Forms::Units do
  describe ".to_pixels" do
    it "converts inches at 96 DPI" do
      expect(described_class.to_pixels(1, "inch")).to eq(96)
      expect(described_class.to_pixels(2, "inch")).to eq(192)
      expect(described_class.to_pixels(0.5, "inch")).to eq(48)
    end

    it "converts points at 96/72" do
      expect(described_class.to_pixels(72, "pt")).to eq(96)
      expect(described_class.to_pixels(12, "pt")).to eq(16)
    end

    it "converts centimeters and millimeters" do
      expect(described_class.to_pixels(2.54, "cm")).to eq(96)
      expect(described_class.to_pixels(25.4, "mm")).to eq(96)
    end

    it "rounds to three decimals and keeps fractional results" do
      expect(described_class.to_pixels(0.02, "inch")).to eq(1.92)
      expect(described_class.to_pixels(4.6, "inch")).to eq(441.6)
    end

    it "raises on unknown unit" do
      expect { described_class.to_pixels(1, "furlong") }.to raise_error(ArgumentError)
    end
  end

  describe ".from_pixels" do
    it "inverts to_pixels for inches" do
      expect(described_class.from_pixels(96, "inch")).to eq(1)
      expect(described_class.from_pixels(48, "inch")).to eq(0.5)
    end

    it "raises on unknown unit" do
      expect { described_class.from_pixels(96, "league") }.to raise_error(ArgumentError)
    end
  end

  it "exposes conversions through the module facade" do
    expect(Odin::Forms.to_pixels(1, "inch")).to eq(96)
    expect(Odin::Forms.from_pixels(96, "inch")).to eq(1)
  end
end
