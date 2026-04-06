# frozen_string_literal: true

require "spec_helper"
require "bigdecimal"

RSpec.describe Odin::Types::DynValue, "transform extensions" do
  DV = Odin::Types::DynValue unless defined?(DV)

  describe "factory methods return correct types" do
    it ".of_null" do
      v = DV.of_null
      expect(v.type).to eq(:null)
      expect(v.null?).to be true
      expect(v.value).to be_nil
    end

    it ".of_bool true" do
      v = DV.of_bool(true)
      expect(v.type).to eq(:bool)
      expect(v.bool?).to be true
      expect(v.value).to be true
    end

    it ".of_bool false" do
      v = DV.of_bool(false)
      expect(v.value).to be false
    end

    it ".of_integer" do
      v = DV.of_integer(42)
      expect(v.type).to eq(:integer)
      expect(v.integer?).to be true
      expect(v.value).to eq(42)
    end

    it ".of_float" do
      v = DV.of_float(3.14)
      expect(v.type).to eq(:float)
      expect(v.float?).to be true
      expect(v.value).to be_within(0.001).of(3.14)
    end

    it ".of_float_raw" do
      v = DV.of_float_raw("1.23e10")
      expect(v.float?).to be true
      expect(v.value).to eq("1.23e10")
    end

    it ".of_string" do
      v = DV.of_string("hello")
      expect(v.type).to eq(:string)
      expect(v.string?).to be true
      expect(v.value).to eq("hello")
    end

    it ".of_array" do
      v = DV.of_array([DV.of_integer(1)])
      expect(v.type).to eq(:array)
      expect(v.array?).to be true
    end

    it ".of_object" do
      v = DV.of_object({ "k" => DV.of_string("v") })
      expect(v.type).to eq(:object)
      expect(v.object?).to be true
    end

    it ".of_currency with BigDecimal" do
      v = DV.of_currency(BigDecimal("99.99"), 2, "USD")
      expect(v.currency?).to be true
      expect(v.decimal_places).to eq(2)
      expect(v.currency_code).to eq("USD")
    end

    it ".of_currency_raw" do
      v = DV.of_currency_raw("100.50", 2, "EUR")
      expect(v.currency?).to be true
      expect(v.value).to eq("100.50")
      expect(v.currency_code).to eq("EUR")
    end

    it ".of_percent" do
      v = DV.of_percent(0.15)
      expect(v.percent?).to be true
    end

    it ".of_reference" do
      v = DV.of_reference("policy.id")
      expect(v.reference?).to be true
      expect(v.value).to eq("policy.id")
    end

    it ".of_binary" do
      v = DV.of_binary("SGVsbG8=")
      expect(v.binary?).to be true
    end

    it ".of_date" do
      v = DV.of_date("2024-01-15")
      expect(v.date?).to be true
    end

    it ".of_timestamp" do
      v = DV.of_timestamp("2024-01-15T10:30:00Z")
      expect(v.timestamp?).to be true
    end

    it ".of_time" do
      v = DV.of_time("10:30:00")
      expect(v.time?).to be true
    end

    it ".of_duration" do
      v = DV.of_duration("P1Y6M")
      expect(v.duration?).to be true
    end
  end

  describe "#from_ruby" do
    it "converts nil" do
      expect(DV.from_ruby(nil).null?).to be true
    end

    it "converts true" do
      v = DV.from_ruby(true)
      expect(v.bool?).to be true
      expect(v.value).to be true
    end

    it "converts false" do
      v = DV.from_ruby(false)
      expect(v.bool?).to be true
      expect(v.value).to be false
    end

    it "converts Integer" do
      v = DV.from_ruby(42)
      expect(v.integer?).to be true
      expect(v.value).to eq(42)
    end

    it "converts Float" do
      v = DV.from_ruby(3.14)
      expect(v.float?).to be true
    end

    it "converts String" do
      v = DV.from_ruby("hello")
      expect(v.string?).to be true
      expect(v.value).to eq("hello")
    end

    it "converts Array recursively" do
      v = DV.from_ruby([1, "two", nil])
      expect(v.array?).to be true
      expect(v.value[0].integer?).to be true
      expect(v.value[1].string?).to be true
      expect(v.value[2].null?).to be true
    end

    it "converts Hash recursively" do
      v = DV.from_ruby({ "a" => 1, "b" => { "c" => true } })
      expect(v.object?).to be true
      expect(v.get("a").integer?).to be true
      expect(v.get("b").object?).to be true
      expect(v.get("b").get("c").bool?).to be true
    end

    it "converts BigDecimal" do
      v = DV.from_ruby(BigDecimal("99.99"))
      expect(v.float?).to be true
    end

    it "converts symbol keys to strings" do
      v = DV.from_ruby({ foo: "bar" })
      expect(v.get("foo").string?).to be true
    end
  end

  describe "#to_ruby" do
    it "null -> nil" do
      expect(DV.of_null.to_ruby).to be_nil
    end

    it "bool -> true/false" do
      expect(DV.of_bool(true).to_ruby).to be true
      expect(DV.of_bool(false).to_ruby).to be false
    end

    it "integer -> Integer" do
      expect(DV.of_integer(42).to_ruby).to eq(42)
    end

    it "float -> Float" do
      expect(DV.of_float(3.14).to_ruby).to be_within(0.001).of(3.14)
    end

    it "string -> String" do
      expect(DV.of_string("hi").to_ruby).to eq("hi")
    end

    it "array -> Array recursively" do
      v = DV.of_array([DV.of_integer(1), DV.of_string("x")])
      result = v.to_ruby
      expect(result).to eq([1, "x"])
    end

    it "object -> Hash recursively" do
      v = DV.of_object({ "a" => DV.of_integer(1) })
      expect(v.to_ruby).to eq({ "a" => 1 })
    end

    it "round-trips through from_ruby/to_ruby" do
      original = { "name" => "test", "count" => 42, "active" => true, "items" => [1, 2, 3] }
      result = DV.from_ruby(original).to_ruby
      expect(result).to eq(original)
    end
  end

  describe "#to_number" do
    it "integer returns value" do
      expect(DV.of_integer(42).to_number).to eq(42)
    end

    it "float returns value" do
      expect(DV.of_float(3.14).to_number).to be_within(0.001).of(3.14)
    end

    it "currency returns float" do
      expect(DV.of_currency(99.99).to_number).to be_within(0.01).of(99.99)
    end

    it "percent returns value" do
      expect(DV.of_percent(0.15).to_number).to be_within(0.001).of(0.15)
    end

    it "numeric string parses to number" do
      expect(DV.of_string("42").to_number).to eq(42)
      expect(DV.of_string("3.14").to_number).to be_within(0.001).of(3.14)
    end

    it "non-numeric string returns 0" do
      expect(DV.of_string("abc").to_number).to eq(0)
    end

    it "bool converts to 0/1" do
      expect(DV.of_bool(true).to_number).to eq(1)
      expect(DV.of_bool(false).to_number).to eq(0)
    end

    it "null returns 0" do
      expect(DV.of_null.to_number).to eq(0)
    end
  end

  describe "#to_string" do
    it "null returns empty string" do
      expect(DV.of_null.to_string).to eq("")
    end

    it "bool returns 'true'/'false'" do
      expect(DV.of_bool(true).to_string).to eq("true")
      expect(DV.of_bool(false).to_string).to eq("false")
    end

    it "integer returns string" do
      expect(DV.of_integer(42).to_string).to eq("42")
    end

    it "float returns string" do
      expect(DV.of_float(3.14).to_string).to eq("3.14")
    end

    it "string returns itself" do
      expect(DV.of_string("hello").to_string).to eq("hello")
    end

    it "array returns JSON" do
      v = DV.of_array([DV.of_integer(1), DV.of_integer(2)])
      expect(DV.of_null.to_string).to eq("")
      result = v.to_string
      expect(result).to include("1")
      expect(result).to include("2")
    end
  end

  describe "#truthy?" do
    it "null is falsy" do
      expect(DV.of_null.truthy?).to be false
    end

    it "false is falsy" do
      expect(DV.of_bool(false).truthy?).to be false
    end

    it "true is truthy" do
      expect(DV.of_bool(true).truthy?).to be true
    end

    it "0 is falsy" do
      expect(DV.of_integer(0).truthy?).to be false
    end

    it "non-zero integer is truthy" do
      expect(DV.of_integer(1).truthy?).to be true
    end

    it "empty string is falsy" do
      expect(DV.of_string("").truthy?).to be false
    end

    it "non-empty string is truthy" do
      expect(DV.of_string("x").truthy?).to be true
    end

    it "array is truthy" do
      expect(DV.of_array([]).truthy?).to be true
    end

    it "object is truthy" do
      expect(DV.of_object({}).truthy?).to be true
    end

    it "0.0 float is falsy" do
      expect(DV.of_float(0.0).truthy?).to be false
    end

    it "non-zero float is truthy" do
      expect(DV.of_float(1.5).truthy?).to be true
    end
  end

  describe "type predicates" do
    it "numeric? returns true for integer, float, currency, percent" do
      expect(DV.of_integer(1).numeric?).to be true
      expect(DV.of_float(1.0).numeric?).to be true
      expect(DV.of_currency(1.0).numeric?).to be true
      expect(DV.of_percent(0.1).numeric?).to be true
    end

    it "numeric? returns false for non-numeric" do
      expect(DV.of_string("x").numeric?).to be false
      expect(DV.of_null.numeric?).to be false
      expect(DV.of_bool(true).numeric?).to be false
    end

    it "temporal? returns true for date, timestamp, time, duration" do
      expect(DV.of_date("2024-01-01").temporal?).to be true
      expect(DV.of_timestamp("2024-01-01T00:00:00Z").temporal?).to be true
      expect(DV.of_time("10:00:00").temporal?).to be true
      expect(DV.of_duration("P1D").temporal?).to be true
    end

    it "temporal? returns false for non-temporal" do
      expect(DV.of_string("x").temporal?).to be false
      expect(DV.of_integer(1).temporal?).to be false
    end
  end

  describe ".extract_array" do
    it "parses valid JSON array" do
      v = DV.extract_array('[1, "two", true, null]')
      expect(v.array?).to be true
      expect(v.value.size).to eq(4)
    end

    it "raises on non-array JSON" do
      expect { DV.extract_array('{"a": 1}') }.to raise_error(ArgumentError)
    end

    it "raises on invalid JSON" do
      expect { DV.extract_array("not json") }.to raise_error(JSON::ParserError)
    end
  end

  describe ".extract_object" do
    it "parses valid JSON object" do
      v = DV.extract_object('{"name": "test", "count": 42}')
      expect(v.object?).to be true
      expect(v.get("name").value).to eq("test")
    end

    it "raises on non-object JSON" do
      expect { DV.extract_object("[1, 2]") }.to raise_error(ArgumentError)
    end
  end

  describe "immutability" do
    it "all factory methods return frozen values" do
      expect(DV.of_null).to be_frozen
      expect(DV.of_bool(true)).to be_frozen
      expect(DV.of_integer(1)).to be_frozen
      expect(DV.of_float(1.0)).to be_frozen
      expect(DV.of_string("x")).to be_frozen
    end
  end

  describe "equality" do
    it "same type and value are equal" do
      expect(DV.of_integer(42)).to eq(DV.of_integer(42))
      expect(DV.of_string("hi")).to eq(DV.of_string("hi"))
    end

    it "different values are not equal" do
      expect(DV.of_integer(1)).not_to eq(DV.of_integer(2))
    end

    it "different types are not equal" do
      expect(DV.of_integer(1)).not_to eq(DV.of_float(1.0))
    end

    it "currency equality includes code" do
      v1 = DV.of_currency(100, 2, "USD")
      v2 = DV.of_currency(100, 2, "EUR")
      v3 = DV.of_currency(100, 2, "USD")
      expect(v1).not_to eq(v2)
      expect(v1).to eq(v3)
    end
  end
end
