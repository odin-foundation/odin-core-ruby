# frozen_string_literal: true

require "spec_helper"

RSpec.describe Odin::Types::DynValue do
  describe "factory methods" do
    it ".of_null creates null" do
      v = described_class.of_null
      expect(v.type).to eq(:null)
      expect(v.null?).to be true
      expect(v.value).to be_nil
    end

    it ".of_bool creates bool" do
      v = described_class.of_bool(true)
      expect(v.type).to eq(:bool)
      expect(v.bool?).to be true
      expect(v.as_bool).to be true
    end

    it ".of_bool false" do
      v = described_class.of_bool(false)
      expect(v.as_bool).to be false
    end

    it ".of_integer creates integer" do
      v = described_class.of_integer(42)
      expect(v.type).to eq(:integer)
      expect(v.integer?).to be true
      expect(v.as_int).to eq(42)
    end

    it ".of_float creates float" do
      v = described_class.of_float(3.14)
      expect(v.type).to eq(:float)
      expect(v.float?).to be true
      expect(v.as_float).to be_within(0.001).of(3.14)
    end

    it ".of_float_raw creates float_raw" do
      v = described_class.of_float_raw("1.23e10")
      expect(v.type).to eq(:float_raw)
      expect(v.float?).to be true
      expect(v.value).to eq("1.23e10")
    end

    it ".of_string creates string" do
      v = described_class.of_string("hello")
      expect(v.type).to eq(:string)
      expect(v.string?).to be true
      expect(v.as_string).to eq("hello")
    end

    it ".of_array creates array" do
      items = [described_class.of_integer(1), described_class.of_integer(2)]
      v = described_class.of_array(items)
      expect(v.type).to eq(:array)
      expect(v.array?).to be true
      expect(v.as_array.size).to eq(2)
    end

    it ".of_object creates object" do
      entries = { "key" => described_class.of_string("val") }
      v = described_class.of_object(entries)
      expect(v.type).to eq(:object)
      expect(v.object?).to be true
      expect(v.get("key").as_string).to eq("val")
    end

    it ".of_currency creates currency" do
      v = described_class.of_currency(99.99, 2, "USD")
      expect(v.type).to eq(:currency)
      expect(v.currency?).to be true
      expect(v.decimal_places).to eq(2)
      expect(v.currency_code).to eq("USD")
    end

    it ".of_currency_raw creates currency_raw" do
      v = described_class.of_currency_raw("100.50", 2, "EUR")
      expect(v.type).to eq(:currency_raw)
      expect(v.currency?).to be true
      expect(v.value).to eq("100.50")
      expect(v.currency_code).to eq("EUR")
    end

    it ".of_percent creates percent" do
      v = described_class.of_percent(0.15)
      expect(v.type).to eq(:percent)
      expect(v.percent?).to be true
    end

    it ".of_reference creates reference" do
      v = described_class.of_reference("policy.id")
      expect(v.type).to eq(:reference)
      expect(v.reference?).to be true
      expect(v.value).to eq("policy.id")
    end

    it ".of_binary creates binary" do
      v = described_class.of_binary("SGVsbG8=")
      expect(v.type).to eq(:binary)
      expect(v.binary?).to be true
    end

    it ".of_date creates date" do
      v = described_class.of_date("2024-01-15")
      expect(v.type).to eq(:date)
      expect(v.date?).to be true
    end

    it ".of_timestamp creates timestamp" do
      v = described_class.of_timestamp("2024-01-15T10:30:00Z")
      expect(v.type).to eq(:timestamp)
      expect(v.timestamp?).to be true
    end

    it ".of_time creates time" do
      v = described_class.of_time("10:30:00")
      expect(v.type).to eq(:time)
      expect(v.time?).to be true
    end

    it ".of_duration creates duration" do
      v = described_class.of_duration("P1Y6M")
      expect(v.type).to eq(:duration)
      expect(v.duration?).to be true
    end
  end

  describe ".extract_array" do
    it "parses JSON array string" do
      v = described_class.extract_array('[1, "two", true, null]')
      expect(v.array?).to be true
      items = v.as_array
      expect(items.size).to eq(4)
      expect(items[0].integer?).to be true
      expect(items[1].string?).to be true
      expect(items[2].bool?).to be true
      expect(items[3].null?).to be true
    end

    it "raises for non-array JSON" do
      expect { described_class.extract_array('{"a": 1}') }.to raise_error(ArgumentError)
    end
  end

  describe ".extract_object" do
    it "parses JSON object string" do
      v = described_class.extract_object('{"name": "test", "count": 42}')
      expect(v.object?).to be true
      expect(v.get("name").as_string).to eq("test")
      expect(v.get("count").as_int).to eq(42)
    end

    it "raises for non-object JSON" do
      expect { described_class.extract_object("[1, 2]") }.to raise_error(ArgumentError)
    end
  end

  describe ".from_json_value" do
    it "handles nil" do
      expect(described_class.from_json_value(nil).null?).to be true
    end

    it "handles boolean" do
      expect(described_class.from_json_value(true).bool?).to be true
    end

    it "handles integer" do
      expect(described_class.from_json_value(42).integer?).to be true
    end

    it "handles float" do
      expect(described_class.from_json_value(3.14).float?).to be true
    end

    it "handles string" do
      expect(described_class.from_json_value("hi").string?).to be true
    end

    it "handles nested array" do
      v = described_class.from_json_value([1, [2, 3]])
      expect(v.array?).to be true
      expect(v.get_index(1).array?).to be true
    end

    it "handles nested object" do
      v = described_class.from_json_value({ "a" => { "b" => 1 } })
      expect(v.object?).to be true
      expect(v.get("a").object?).to be true
    end
  end

  describe "numeric? predicate" do
    it "returns true for integer, float, currency, percent" do
      expect(described_class.of_integer(1).numeric?).to be true
      expect(described_class.of_float(1.0).numeric?).to be true
      expect(described_class.of_currency(1.0).numeric?).to be true
      expect(described_class.of_percent(0.1).numeric?).to be true
    end

    it "returns false for non-numeric" do
      expect(described_class.of_string("x").numeric?).to be false
      expect(described_class.of_null.numeric?).to be false
    end
  end

  describe "immutability" do
    it "is frozen" do
      expect(described_class.of_null).to be_frozen
      expect(described_class.of_string("x")).to be_frozen
    end
  end

  describe "equality" do
    it "equal values are ==" do
      expect(described_class.of_integer(42)).to eq(described_class.of_integer(42))
    end

    it "different values are not ==" do
      expect(described_class.of_integer(1)).not_to eq(described_class.of_integer(2))
    end

    it "different types are not ==" do
      expect(described_class.of_integer(1)).not_to eq(described_class.of_float(1.0))
    end
  end

  describe "#get_index" do
    it "accesses array items by index" do
      v = described_class.of_array([described_class.of_string("a"), described_class.of_string("b")])
      expect(v.get_index(0).as_string).to eq("a")
      expect(v.get_index(1).as_string).to eq("b")
    end

    it "returns nil for non-array" do
      expect(described_class.of_string("x").get_index(0)).to be_nil
    end
  end

  describe "#get" do
    it "returns nil for non-object" do
      expect(described_class.of_string("x").get("key")).to be_nil
    end
  end
end
