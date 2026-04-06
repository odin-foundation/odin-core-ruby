# frozen_string_literal: true

require "spec_helper"

RSpec.describe Odin::Parsing::ValueParser do
  TT = Odin::Parsing::TokenType
  Token = Odin::Parsing::Token

  def make_token(type, value, line: 1, col: 1)
    Token.new(type, value, line, col)
  end

  describe ".parse_value" do
    # --- String ---
    it "parses a string token" do
      v = described_class.parse_value(make_token(TT::STRING, "hello"))
      expect(v.type).to eq(:string)
      expect(v.value).to eq("hello")
    end

    it "parses an empty string" do
      v = described_class.parse_value(make_token(TT::STRING, ""))
      expect(v.type).to eq(:string)
      expect(v.value).to eq("")
    end

    # --- Number ---
    it "parses a number token" do
      v = described_class.parse_value(make_token(TT::NUMBER, "3.14"))
      expect(v.type).to eq(:number)
      expect(v.value).to be_within(1e-10).of(3.14)
    end

    it "parses negative number" do
      v = described_class.parse_value(make_token(TT::NUMBER, "-273.15"))
      expect(v.type).to eq(:number)
      expect(v.value).to be_within(1e-10).of(-273.15)
    end

    it "parses scientific notation" do
      v = described_class.parse_value(make_token(TT::NUMBER, "6.022e23"))
      expect(v.type).to eq(:number)
      expect(v.value).to be_within(1e15).of(6.022e23)
    end

    it "parses zero" do
      v = described_class.parse_value(make_token(TT::NUMBER, "0"))
      expect(v.type).to eq(:number)
      expect(v.value).to eq(0.0)
    end

    it "stores raw for high-precision numbers" do
      v = described_class.parse_value(make_token(TT::NUMBER, "3.141592653589793238"))
      expect(v.raw).to eq("3.141592653589793238")
    end

    it "raises P006 for empty number" do
      expect {
        described_class.parse_value(make_token(TT::NUMBER, ""))
      }.to raise_error(Odin::Errors::ParseError) { |e| expect(e.code).to eq("P006") }
    end

    # --- Integer ---
    it "parses an integer token" do
      v = described_class.parse_value(make_token(TT::INTEGER, "42"))
      expect(v.type).to eq(:integer)
      expect(v.value).to eq(42)
    end

    it "parses negative integer" do
      v = described_class.parse_value(make_token(TT::INTEGER, "-100"))
      expect(v.type).to eq(:integer)
      expect(v.value).to eq(-100)
    end

    it "parses zero integer" do
      v = described_class.parse_value(make_token(TT::INTEGER, "0"))
      expect(v.type).to eq(:integer)
      expect(v.value).to eq(0)
    end

    it "stores raw for large integers" do
      v = described_class.parse_value(make_token(TT::INTEGER, "9007199254740992"))
      expect(v.raw).to eq("9007199254740992")
    end

    # --- Currency ---
    it "parses currency" do
      v = described_class.parse_value(make_token(TT::CURRENCY, "99.99"))
      expect(v.type).to eq(:currency)
      expect(v.value.to_f).to be_within(1e-10).of(99.99)
      expect(v.decimal_places).to eq(2)
    end

    it "parses currency with code" do
      v = described_class.parse_value(make_token(TT::CURRENCY, "99.99:USD"))
      expect(v.type).to eq(:currency)
      expect(v.currency_code).to eq("USD")
    end

    it "parses negative currency" do
      v = described_class.parse_value(make_token(TT::CURRENCY, "-50.00"))
      expect(v.value.to_f).to be_within(1e-10).of(-50.0)
    end

    it "counts 3 decimal places" do
      v = described_class.parse_value(make_token(TT::CURRENCY, "19.995"))
      expect(v.decimal_places).to eq(3)
    end

    # --- Percent ---
    it "parses percent" do
      v = described_class.parse_value(make_token(TT::PERCENT, "0.15"))
      expect(v.type).to eq(:percent)
      expect(v.value).to be_within(1e-10).of(0.15)
    end

    it "parses negative percent" do
      v = described_class.parse_value(make_token(TT::PERCENT, "-0.05"))
      expect(v.value).to be_within(1e-10).of(-0.05)
    end

    # --- Boolean ---
    it "parses true" do
      v = described_class.parse_value(make_token(TT::BOOLEAN, "true"))
      expect(v.type).to eq(:boolean)
      expect(v.value).to eq(true)
    end

    it "parses false" do
      v = described_class.parse_value(make_token(TT::BOOLEAN, "false"))
      expect(v.type).to eq(:boolean)
      expect(v.value).to eq(false)
    end

    # --- Null ---
    it "parses null" do
      v = described_class.parse_value(make_token(TT::NULL, "~"))
      expect(v.type).to eq(:null)
    end

    # --- Date ---
    it "parses a date" do
      v = described_class.parse_value(make_token(TT::DATE, "2024-06-15"))
      expect(v.type).to eq(:date)
      expect(v.raw).to eq("2024-06-15")
    end

    it "raises for invalid date (non-leap year)" do
      expect {
        described_class.parse_value(make_token(TT::DATE, "2023-02-29"))
      }.to raise_error(Odin::Errors::ParseError) { |e| expect(e.code).to eq("P001") }
    end

    it "accepts leap year date" do
      v = described_class.parse_value(make_token(TT::DATE, "2024-02-29"))
      expect(v.type).to eq(:date)
    end

    # --- Timestamp ---
    it "parses a timestamp" do
      v = described_class.parse_value(make_token(TT::TIMESTAMP, "2024-06-15T14:30:00Z"))
      expect(v.type).to eq(:timestamp)
      expect(v.raw).to eq("2024-06-15T14:30:00Z")
    end

    # --- Time ---
    it "parses a time" do
      v = described_class.parse_value(make_token(TT::TIME, "T14:30:00"))
      expect(v.type).to eq(:time)
      expect(v.value).to eq("T14:30:00")
    end

    # --- Duration ---
    it "parses a duration" do
      v = described_class.parse_value(make_token(TT::DURATION, "P1Y2M3D"))
      expect(v.type).to eq(:duration)
      expect(v.value).to eq("P1Y2M3D")
    end

    # --- Reference ---
    it "parses a reference" do
      v = described_class.parse_value(make_token(TT::REFERENCE, "drivers[0]"))
      expect(v.type).to eq(:reference)
      expect(v.path).to eq("drivers[0]")
    end

    it "parses bare @ reference (empty path)" do
      v = described_class.parse_value(make_token(TT::REFERENCE, ""))
      expect(v.type).to eq(:reference)
      expect(v.path).to eq("")
    end

    # --- Binary ---
    it "parses binary" do
      v = described_class.parse_value(make_token(TT::BINARY, "SGVsbG8="))
      expect(v.type).to eq(:binary)
      expect(v.data).to eq("SGVsbG8=")
    end

    it "parses binary with algorithm" do
      v = described_class.parse_value(make_token(TT::BINARY, "sha256:n4bQgYhMfWWaL28"))
      expect(v.type).to eq(:binary)
      expect(v.algorithm).to eq("sha256")
    end

    it "parses empty binary" do
      v = described_class.parse_value(make_token(TT::BINARY, ""))
      expect(v.type).to eq(:binary)
      expect(v.data).to eq("")
    end

    # --- Verb ---
    it "parses verb name" do
      v = described_class.parse_value(make_token(TT::VERB, "upper"))
      expect(v.type).to eq(:verb)
      expect(v.verb).to eq("upper")
      expect(v.custom?).to eq(false)
    end

    it "parses custom verb name" do
      v = described_class.parse_value(make_token(TT::VERB, "&myVerb"))
      expect(v.type).to eq(:verb)
      expect(v.verb).to eq("myVerb")
      expect(v.custom?).to eq(true)
    end

    # --- Additional Number Tests ---
    it "parses integer with leading plus" do
      v = described_class.parse_value(make_token(TT::INTEGER, "+42"))
      expect(v.type).to eq(:integer)
      expect(v.value).to eq(42)
    end

    it "parses number with leading plus" do
      v = described_class.parse_value(make_token(TT::NUMBER, "+3.14"))
      expect(v.type).to eq(:number)
      expect(v.value).to be_within(1e-10).of(3.14)
    end

    it "parses large number" do
      v = described_class.parse_value(make_token(TT::NUMBER, "123456789.123456"))
      expect(v.type).to eq(:number)
    end

    # --- Additional Currency Tests ---
    it "parses currency with EUR code" do
      v = described_class.parse_value(make_token(TT::CURRENCY, "42.50:EUR"))
      expect(v.currency_code).to eq("EUR")
      expect(v.decimal_places).to eq(2)
    end

    it "parses currency with no code" do
      v = described_class.parse_value(make_token(TT::CURRENCY, "100"))
      expect(v.type).to eq(:currency)
      expect(v.currency_code).to be_nil
    end

    # --- Additional Percent Tests ---
    it "parses negative percent" do
      v = described_class.parse_value(make_token(TT::PERCENT, "-0.05"))
      expect(v.type).to eq(:percent)
      expect(v.value).to be_within(1e-10).of(-0.05)
    end

    it "parses large percent" do
      v = described_class.parse_value(make_token(TT::PERCENT, "1.5"))
      expect(v.type).to eq(:percent)
      expect(v.value).to be_within(1e-10).of(1.5)
    end

    # --- Additional Date Tests ---
    it "raises for invalid month" do
      expect {
        described_class.parse_value(make_token(TT::DATE, "2024-13-01"))
      }.to raise_error(Odin::Errors::ParseError)
    end

    it "raises for invalid day" do
      expect {
        described_class.parse_value(make_token(TT::DATE, "2024-04-31"))
      }.to raise_error(Odin::Errors::ParseError)
    end

    it "parses end of year date" do
      v = described_class.parse_value(make_token(TT::DATE, "2024-12-31"))
      expect(v.type).to eq(:date)
    end

    # --- Additional Timestamp Tests ---
    it "parses timestamp with milliseconds" do
      v = described_class.parse_value(make_token(TT::TIMESTAMP, "2024-01-15T10:30:00.123Z"))
      expect(v.type).to eq(:timestamp)
    end

    # --- Additional Reference Tests ---
    it "parses reference with simple path" do
      v = described_class.parse_value(make_token(TT::REFERENCE, "name"))
      expect(v.path).to eq("name")
    end

    it "parses reference with nested array" do
      v = described_class.parse_value(make_token(TT::REFERENCE, "items[0].sub[1]"))
      expect(v.path).to eq("items[0].sub[1]")
    end

    # --- Error ---
    it "raises for unknown token type" do
      expect {
        described_class.parse_value(make_token(TT::EQUALS, "="))
      }.to raise_error(Odin::Errors::ParseError)
    end
  end
end
