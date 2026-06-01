# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Temporal semantic validation" do
  def parse(text)
    Odin.parse(text)
  end

  def expect_p001(text)
    expect { parse(text) }.to raise_error(Odin::Errors::ParseError) do |err|
      expect(err.code).to eq("P001")
    end
  end

  describe "timestamp" do
    # --- happy ---
    it "accepts a fully valid timestamp" do
      doc = parse("ts = 2024-06-15T23:59:59Z")
      expect(doc.get("ts").type).to eq(:timestamp)
      expect(doc.get("ts").raw).to eq("2024-06-15T23:59:59Z")
    end

    it "accepts a positive timezone offset" do
      doc = parse("ts = 2024-01-15T10:30:00+05:30")
      expect(doc.get("ts").raw).to eq("2024-01-15T10:30:00+05:30")
    end

    it "accepts a negative timezone offset" do
      doc = parse("ts = 2024-01-15T10:30:00-08:00")
      expect(doc.get("ts").raw).to eq("2024-01-15T10:30:00-08:00")
    end

    it "accepts fractional seconds" do
      doc = parse("ts = 2024-06-15T10:30:00.123Z")
      expect(doc.get("ts").raw).to eq("2024-06-15T10:30:00.123Z")
    end

    it "accepts a leap second (:60)" do
      doc = parse("ts = 2016-12-31T23:59:60Z")
      expect(doc.get("ts").raw).to eq("2016-12-31T23:59:60Z")
    end

    it "accepts hour 24 as end-of-day midnight" do
      doc = parse("ts = 2024-06-15T24:00:00Z")
      expect(doc.get("ts").raw).to eq("2024-06-15T24:00:00Z")
    end

    # --- error ---
    it "rejects an invalid month in the date portion (P001)" do
      expect_p001("ts = 2024-13-40T10:30:00Z")
    end

    it "rejects an invalid day in the date portion (P001)" do
      expect_p001("ts = 2024-02-30T10:30:00Z")
    end

    it "rejects hour > 23 (P001)" do
      expect_p001("ts = 2024-06-15T25:30:00Z")
    end

    it "rejects minute > 59 (P001)" do
      expect_p001("ts = 2024-06-15T10:61:00Z")
    end

    it "rejects second > 60 (P001)" do
      expect_p001("ts = 2024-06-15T10:30:61Z")
    end

    it "rejects an out-of-range timezone offset hour (P001)" do
      expect_p001("ts = 2024-06-15T10:30:00+25:00")
    end

    it "rejects an out-of-range timezone offset minute (P001)" do
      expect_p001("ts = 2024-06-15T10:30:00+05:99")
    end

    it "rejects a wholly malformed timestamp (P001)" do
      expect_p001("ts = 2024-13-40T99:99:99Z")
    end

    # --- edge ---
    it "rejects hour 24 with non-zero minutes (P001)" do
      expect_p001("ts = 2024-06-15T24:30:00Z")
    end

    it "rejects hour 24 with non-zero seconds (P001)" do
      expect_p001("ts = 2024-06-15T24:00:30Z")
    end

    it "accepts the maximum valid offset" do
      doc = parse("ts = 2024-06-15T10:30:00+23:59")
      expect(doc.get("ts").raw).to eq("2024-06-15T10:30:00+23:59")
    end
  end

  describe "time" do
    # --- happy ---
    it "accepts a valid time with seconds" do
      doc = parse("t = T14:30:00")
      expect(doc.get("t").type).to eq(:time)
      expect(doc.get("t").value).to eq("T14:30:00")
    end

    it "accepts a valid time without seconds" do
      doc = parse("t = T14:30")
      expect(doc.get("t").value).to eq("T14:30")
    end

    it "accepts fractional seconds" do
      doc = parse("t = T10:30:00.500")
      expect(doc.get("t").value).to eq("T10:30:00.500")
    end

    it "accepts a leap second (:60)" do
      doc = parse("t = T23:59:60")
      expect(doc.get("t").value).to eq("T23:59:60")
    end

    it "accepts hour 24 as end-of-day midnight" do
      doc = parse("t = T24:00:00")
      expect(doc.get("t").value).to eq("T24:00:00")
    end

    # --- error ---
    it "rejects hour > 23 non-midnight (P001)" do
      expect_p001("t = T25:00:00")
    end

    it "rejects minute > 59 (P001)" do
      expect_p001("t = T14:61:00")
    end

    it "rejects second > 60 (P001)" do
      expect_p001("t = T14:30:61")
    end

    # --- edge ---
    it "rejects hour 24 with non-zero minutes (P001)" do
      expect_p001("t = T24:30:00")
    end

    it "rejects hour 24 with non-zero seconds (P001)" do
      expect_p001("t = T24:00:30")
    end
  end
end
