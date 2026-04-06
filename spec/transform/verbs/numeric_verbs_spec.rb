# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Numeric Verbs" do
  let(:engine) { Odin::Transform::TransformEngine.new }
  let(:ctx) { Odin::Transform::VerbContext.new }
  let(:dv) { Odin::Types::DynValue }

  # Helper
  def invoke(name, *args)
    engine.invoke_verb(name, args, ctx)
  end

  # ---------------------------------------------------------------------------
  # add
  # ---------------------------------------------------------------------------
  describe "add" do
    it "adds two integers" do
      result = invoke("add", dv.of_integer(3), dv.of_integer(2))
      expect(result.value).to eq(5)
      expect(result.integer?).to be true
    end

    it "adds integer and float returning float" do
      result = invoke("add", dv.of_integer(3), dv.of_float(1.5))
      expect(result.value).to eq(4.5)
      expect(result.float?).to be true
    end

    it "adds float and integer returning float" do
      result = invoke("add", dv.of_float(2.5), dv.of_integer(1))
      expect(result.value).to eq(3.5)
      expect(result.float?).to be true
    end

    it "adds two floats" do
      result = invoke("add", dv.of_float(1.1), dv.of_float(2.2))
      expect(result.value).to be_within(0.0001).of(3.3)
      expect(result.float?).to be true
    end

    it "adds numeric strings" do
      result = invoke("add", dv.of_string("3"), dv.of_string("4"))
      expect(result.value).to eq(7.0)
    end

    it "returns null when both args are null" do
      result = invoke("add", dv.of_null, dv.of_null)
      expect(result.null?).to be true
    end

    it "returns null when first arg is null" do
      result = invoke("add", dv.of_null, dv.of_integer(5))
      expect(result.null?).to be true
    end

    it "returns null when second arg is null" do
      result = invoke("add", dv.of_integer(5), dv.of_null)
      expect(result.null?).to be true
    end

    it "adds zero" do
      result = invoke("add", dv.of_integer(7), dv.of_integer(0))
      expect(result.value).to eq(7)
      expect(result.integer?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # subtract
  # ---------------------------------------------------------------------------
  describe "subtract" do
    it "subtracts two integers" do
      result = invoke("subtract", dv.of_integer(10), dv.of_integer(3))
      expect(result.value).to eq(7)
      expect(result.integer?).to be true
    end

    it "subtracts integer and float returning float" do
      result = invoke("subtract", dv.of_integer(5), dv.of_float(1.5))
      expect(result.value).to eq(3.5)
      expect(result.float?).to be true
    end

    it "subtracts float and integer returning float" do
      result = invoke("subtract", dv.of_float(5.5), dv.of_integer(2))
      expect(result.value).to eq(3.5)
      expect(result.float?).to be true
    end

    it "subtracts two floats" do
      result = invoke("subtract", dv.of_float(5.5), dv.of_float(2.2))
      expect(result.value).to be_within(0.0001).of(3.3)
      expect(result.float?).to be true
    end

    it "returns null when first arg is null" do
      result = invoke("subtract", dv.of_null, dv.of_integer(5))
      expect(result.null?).to be true
    end

    it "returns null when second arg is null" do
      result = invoke("subtract", dv.of_integer(5), dv.of_null)
      expect(result.null?).to be true
    end

    it "returns null when both args are null" do
      result = invoke("subtract", dv.of_null, dv.of_null)
      expect(result.null?).to be true
    end

    it "subtracts zero" do
      result = invoke("subtract", dv.of_integer(7), dv.of_integer(0))
      expect(result.value).to eq(7)
      expect(result.integer?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # multiply
  # ---------------------------------------------------------------------------
  describe "multiply" do
    it "multiplies two integers" do
      result = invoke("multiply", dv.of_integer(4), dv.of_integer(3))
      expect(result.value).to eq(12)
      expect(result.integer?).to be true
    end

    it "multiplies integer and float returning float" do
      result = invoke("multiply", dv.of_integer(3), dv.of_float(2.5))
      expect(result.value).to eq(7.5)
      expect(result.float?).to be true
    end

    it "multiplies float and integer returning integer when whole" do
      result = invoke("multiply", dv.of_float(2.5), dv.of_integer(4))
      expect(result.value).to eq(10)
      expect(result.integer?).to be true
    end

    it "multiplies two floats" do
      result = invoke("multiply", dv.of_float(2.5), dv.of_float(3.0))
      expect(result.value).to eq(7.5)
      expect(result.float?).to be true
    end

    it "returns null when first arg is null" do
      result = invoke("multiply", dv.of_null, dv.of_integer(5))
      expect(result.null?).to be true
    end

    it "returns null when second arg is null" do
      result = invoke("multiply", dv.of_integer(5), dv.of_null)
      expect(result.null?).to be true
    end

    it "multiplies by zero" do
      result = invoke("multiply", dv.of_integer(100), dv.of_integer(0))
      expect(result.value).to eq(0)
    end
  end

  # ---------------------------------------------------------------------------
  # divide
  # ---------------------------------------------------------------------------
  describe "divide" do
    it "divides two integers returning float" do
      result = invoke("divide", dv.of_integer(10), dv.of_integer(3))
      expect(result.value).to be_within(0.0001).of(3.3333)
      expect(result.float?).to be true
    end

    it "divides evenly still returning float" do
      result = invoke("divide", dv.of_integer(10), dv.of_integer(2))
      expect(result.value).to eq(5.0)
      expect(result.float?).to be true
    end

    it "divides float by integer" do
      result = invoke("divide", dv.of_float(7.5), dv.of_integer(3))
      expect(result.value).to eq(2.5)
      expect(result.float?).to be true
    end

    it "returns null for divide by zero" do
      result = invoke("divide", dv.of_integer(10), dv.of_integer(0))
      expect(result.null?).to be true
    end

    it "returns null for divide by zero float" do
      result = invoke("divide", dv.of_float(10.0), dv.of_float(0.0))
      expect(result.null?).to be true
    end

    it "returns null when first arg is null" do
      result = invoke("divide", dv.of_null, dv.of_integer(5))
      expect(result.null?).to be true
    end

    it "returns null when second arg is null" do
      result = invoke("divide", dv.of_integer(5), dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # mod
  # ---------------------------------------------------------------------------
  describe "mod" do
    it "returns remainder of integer division" do
      result = invoke("mod", dv.of_integer(10), dv.of_integer(3))
      expect(result.value).to eq(1)
    end

    it "returns zero when evenly divisible" do
      result = invoke("mod", dv.of_integer(10), dv.of_integer(5))
      expect(result.value).to eq(0)
    end

    it "returns null for mod by zero" do
      result = invoke("mod", dv.of_integer(10), dv.of_integer(0))
      expect(result.null?).to be true
    end

    it "returns null when first arg is null" do
      result = invoke("mod", dv.of_null, dv.of_integer(3))
      expect(result.null?).to be true
    end

    it "returns null when second arg is null" do
      result = invoke("mod", dv.of_integer(10), dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # abs
  # ---------------------------------------------------------------------------
  describe "abs" do
    it "returns positive for positive integer" do
      result = invoke("abs", dv.of_integer(5))
      expect(result.value).to eq(5)
      expect(result.integer?).to be true
    end

    it "returns positive for negative integer" do
      result = invoke("abs", dv.of_integer(-5))
      expect(result.value).to eq(5)
      expect(result.integer?).to be true
    end

    it "returns positive for negative float" do
      result = invoke("abs", dv.of_float(-3.14))
      expect(result.value).to eq(3.14)
      expect(result.float?).to be true
    end

    it "preserves positive float" do
      result = invoke("abs", dv.of_float(3.14))
      expect(result.value).to eq(3.14)
      expect(result.float?).to be true
    end

    it "returns null for null" do
      result = invoke("abs", dv.of_null)
      expect(result.null?).to be true
    end

    it "returns zero for zero" do
      result = invoke("abs", dv.of_integer(0))
      expect(result.value).to eq(0)
    end
  end

  # ---------------------------------------------------------------------------
  # floor
  # ---------------------------------------------------------------------------
  describe "floor" do
    it "floors positive float" do
      result = invoke("floor", dv.of_float(3.7))
      expect(result.value).to eq(3)
    end

    it "floors negative float" do
      result = invoke("floor", dv.of_float(-3.7))
      expect(result.value).to eq(-4)
    end

    it "floors already-integer float" do
      result = invoke("floor", dv.of_float(5.0))
      expect(result.value).to eq(5)
    end

    it "returns null for null" do
      result = invoke("floor", dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # ceil
  # ---------------------------------------------------------------------------
  describe "ceil" do
    it "ceils positive float" do
      result = invoke("ceil", dv.of_float(3.2))
      expect(result.value).to eq(4)
    end

    it "ceils negative float" do
      result = invoke("ceil", dv.of_float(-3.2))
      expect(result.value).to eq(-3)
    end

    it "ceils already-integer float" do
      result = invoke("ceil", dv.of_float(5.0))
      expect(result.value).to eq(5)
    end

    it "returns null for null" do
      result = invoke("ceil", dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # round (AWAY FROM ZERO)
  # ---------------------------------------------------------------------------
  describe "round" do
    it "rounds 2.5 up to 3 (away from zero)" do
      result = invoke("round", dv.of_float(2.5), dv.of_integer(0))
      expect(result.value).to eq(3)
    end

    it "rounds -2.5 down to -3 (away from zero)" do
      result = invoke("round", dv.of_float(-2.5), dv.of_integer(0))
      expect(result.value).to eq(-3)
    end

    it "rounds 1.005 to 2 decimal places" do
      result = invoke("round", dv.of_float(1.005), dv.of_integer(2))
      expect(result.value).to eq(1.01)
    end

    it "rounds zero to zero" do
      result = invoke("round", dv.of_float(0.0), dv.of_integer(0))
      expect(result.value).to eq(0)
    end

    it "rounds 3.14159 to 2 decimal places" do
      result = invoke("round", dv.of_float(3.14159), dv.of_integer(2))
      expect(result.value).to eq(3.14)
    end

    it "rounds 3.145 to 2 decimal places (away from zero)" do
      result = invoke("round", dv.of_float(3.145), dv.of_integer(2))
      expect(result.value).to eq(3.15)
    end

    it "returns null for null" do
      result = invoke("round", dv.of_null, dv.of_integer(0))
      expect(result.null?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # negate
  # ---------------------------------------------------------------------------
  describe "negate" do
    it "negates positive integer" do
      result = invoke("negate", dv.of_integer(5))
      expect(result.value).to eq(-5)
      expect(result.integer?).to be true
    end

    it "negates negative integer" do
      result = invoke("negate", dv.of_integer(-3))
      expect(result.value).to eq(3)
      expect(result.integer?).to be true
    end

    it "negates positive float" do
      result = invoke("negate", dv.of_float(2.5))
      expect(result.value).to eq(-2.5)
      expect(result.float?).to be true
    end

    it "negates negative float" do
      result = invoke("negate", dv.of_float(-2.5))
      expect(result.value).to eq(2.5)
      expect(result.float?).to be true
    end

    it "returns null for null" do
      result = invoke("negate", dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # sign
  # ---------------------------------------------------------------------------
  describe "sign" do
    it "returns 1 for positive" do
      result = invoke("sign", dv.of_integer(42))
      expect(result.value).to eq(1)
    end

    it "returns -1 for negative" do
      result = invoke("sign", dv.of_integer(-42))
      expect(result.value).to eq(-1)
    end

    it "returns 0 for zero" do
      result = invoke("sign", dv.of_integer(0))
      expect(result.value).to eq(0)
    end

    it "returns 1 for positive float" do
      result = invoke("sign", dv.of_float(0.001))
      expect(result.value).to eq(1)
    end

    it "returns -1 for negative float" do
      result = invoke("sign", dv.of_float(-0.001))
      expect(result.value).to eq(-1)
    end

    it "returns null for null" do
      result = invoke("sign", dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # trunc
  # ---------------------------------------------------------------------------
  describe "trunc" do
    it "truncates positive float toward zero" do
      result = invoke("trunc", dv.of_float(3.7))
      expect(result.value).to eq(3)
    end

    it "truncates negative float toward zero" do
      result = invoke("trunc", dv.of_float(-3.7))
      expect(result.value).to eq(-3)
    end

    it "truncates positive float with large fraction" do
      result = invoke("trunc", dv.of_float(9.999))
      expect(result.value).to eq(9)
    end

    it "returns null for null" do
      result = invoke("trunc", dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # random
  # ---------------------------------------------------------------------------
  describe "random" do
    it "returns a float" do
      result = invoke("random")
      expect(result.float?).to be true
    end

    it "returns value between 0 and 1 with no args" do
      result = invoke("random")
      expect(result.value).to be >= 0
      expect(result.value).to be < 1
    end

    it "returns value within min/max range" do
      result = invoke("random", dv.of_integer(10), dv.of_integer(20))
      expect(result.value).to be >= 10
      expect(result.value).to be <= 20
    end
  end

  # ---------------------------------------------------------------------------
  # minOf
  # ---------------------------------------------------------------------------
  describe "minOf" do
    it "returns the smaller of two integers" do
      result = invoke("minOf", dv.of_integer(3), dv.of_integer(7))
      expect(result.value).to eq(3)
    end

    it "returns the smallest of three values" do
      result = invoke("minOf", dv.of_integer(5), dv.of_integer(2), dv.of_integer(8))
      expect(result.value).to eq(2)
    end

    it "works with floats" do
      result = invoke("minOf", dv.of_float(3.5), dv.of_float(1.2))
      expect(result.value).to eq(1.2)
    end

    it "works with an array argument" do
      arr = dv.of_array([dv.of_integer(10), dv.of_integer(3), dv.of_integer(7)])
      result = invoke("minOf", arr)
      expect(result.value).to eq(3)
    end

    it "skips null values" do
      result = invoke("minOf", dv.of_integer(5), dv.of_null, dv.of_integer(2))
      expect(result.value).to eq(2)
    end

    it "returns null for empty input" do
      arr = dv.of_array([])
      result = invoke("minOf", arr)
      expect(result.null?).to be true
    end

    it "returns null when all values are null" do
      result = invoke("minOf", dv.of_null, dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # maxOf
  # ---------------------------------------------------------------------------
  describe "maxOf" do
    it "returns the larger of two integers" do
      result = invoke("maxOf", dv.of_integer(3), dv.of_integer(7))
      expect(result.value).to eq(7)
    end

    it "returns the largest of three values" do
      result = invoke("maxOf", dv.of_integer(5), dv.of_integer(2), dv.of_integer(8))
      expect(result.value).to eq(8)
    end

    it "works with floats" do
      result = invoke("maxOf", dv.of_float(3.5), dv.of_float(1.2))
      expect(result.value).to eq(3.5)
    end

    it "works with an array argument" do
      arr = dv.of_array([dv.of_integer(10), dv.of_integer(3), dv.of_integer(7)])
      result = invoke("maxOf", arr)
      expect(result.value).to eq(10)
    end

    it "skips null values" do
      result = invoke("maxOf", dv.of_integer(5), dv.of_null, dv.of_integer(12))
      expect(result.value).to eq(12)
    end

    it "returns null for empty input" do
      arr = dv.of_array([])
      result = invoke("maxOf", arr)
      expect(result.null?).to be true
    end

    it "returns null when all values are null" do
      result = invoke("maxOf", dv.of_null, dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # parseInt
  # ---------------------------------------------------------------------------
  describe "parseInt" do
    it "parses hex string FF with radix 16" do
      result = invoke("parseInt", dv.of_string("FF"), dv.of_integer(16))
      expect(result.value).to eq(255)
      expect(result.integer?).to be true
    end

    it "parses binary string 1010 with radix 2" do
      result = invoke("parseInt", dv.of_string("1010"), dv.of_integer(2))
      expect(result.value).to eq(10)
      expect(result.integer?).to be true
    end

    it "parses decimal string with radix 10" do
      result = invoke("parseInt", dv.of_string("10"), dv.of_integer(10))
      expect(result.value).to eq(10)
      expect(result.integer?).to be true
    end

    it "parses octal string with radix 8" do
      result = invoke("parseInt", dv.of_string("77"), dv.of_integer(8))
      expect(result.value).to eq(63)
      expect(result.integer?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # safeDivide
  # ---------------------------------------------------------------------------
  describe "safeDivide" do
    it "divides normally when divisor is non-zero" do
      result = invoke("safeDivide", dv.of_integer(10), dv.of_integer(2), dv.of_integer(0))
      expect(result.value).to eq(5.0)
    end

    it "returns default when divisor is zero" do
      result = invoke("safeDivide", dv.of_integer(10), dv.of_integer(0), dv.of_integer(-1))
      expect(result.value).to eq(-1)
    end

    it "returns default when divisor is null" do
      result = invoke("safeDivide", dv.of_integer(10), dv.of_null, dv.of_integer(99))
      expect(result.value).to eq(99)
    end

    it "returns default when dividend is null" do
      result = invoke("safeDivide", dv.of_null, dv.of_integer(5), dv.of_integer(0))
      expect(result.value).to eq(0)
    end
  end

  # ---------------------------------------------------------------------------
  # formatNumber
  # ---------------------------------------------------------------------------
  describe "formatNumber" do
    it "formats to 2 decimal places" do
      result = invoke("formatNumber", dv.of_float(3.14159), dv.of_integer(2))
      expect(result.value).to eq("3.14")
    end

    it "formats with away-from-zero rounding" do
      result = invoke("formatNumber", dv.of_float(2.555), dv.of_integer(2))
      expect(result.value).to eq("2.56")
    end

    it "formats integer to 2 decimal places" do
      result = invoke("formatNumber", dv.of_integer(5), dv.of_integer(2))
      expect(result.value).to eq("5.00")
    end

    it "formats to 0 decimal places" do
      result = invoke("formatNumber", dv.of_float(3.7), dv.of_integer(0))
      expect(result.value).to eq("4")
    end
  end

  # ---------------------------------------------------------------------------
  # formatInteger
  # ---------------------------------------------------------------------------
  describe "formatInteger" do
    it "formats integer without commas" do
      result = invoke("formatInteger", dv.of_integer(1234567))
      expect(result.value).to eq("1234567")
    end

    it "rounds float to integer" do
      result = invoke("formatInteger", dv.of_float(1234.7))
      expect(result.value).to eq("1235")
    end

    it "formats zero" do
      result = invoke("formatInteger", dv.of_integer(0))
      expect(result.value).to eq("0")
    end

    it "formats negative integer" do
      result = invoke("formatInteger", dv.of_integer(-42))
      expect(result.value).to eq("-42")
    end
  end

  # ---------------------------------------------------------------------------
  # formatCurrency
  # ---------------------------------------------------------------------------
  describe "formatCurrency" do
    it "formats with 2 decimal places" do
      result = invoke("formatCurrency", dv.of_float(1234.5))
      expect(result.value).to eq("1234.50")
    end

    it "formats integer with 2 decimal places" do
      result = invoke("formatCurrency", dv.of_integer(100))
      expect(result.value).to eq("100.00")
    end

    it "rounds away from zero" do
      result = invoke("formatCurrency", dv.of_float(99.995))
      expect(result.value).to eq("100.00")
    end

    it "formats zero" do
      result = invoke("formatCurrency", dv.of_float(0.0))
      expect(result.value).to eq("0.00")
    end
  end

  # ---------------------------------------------------------------------------
  # formatPercent
  # ---------------------------------------------------------------------------
  describe "formatPercent" do
    it "formats 0.1234 with 1 decimal place" do
      result = invoke("formatPercent", dv.of_float(0.1234), dv.of_integer(1))
      expect(result.value).to eq("12.3%")
    end

    it "formats 0.5 with 0 decimal places" do
      result = invoke("formatPercent", dv.of_float(0.5), dv.of_integer(0))
      expect(result.value).to eq("50%")
    end

    it "formats 1.0 as 100%" do
      result = invoke("formatPercent", dv.of_float(1.0), dv.of_integer(0))
      expect(result.value).to eq("100%")
    end

    it "formats 0 as 0%" do
      result = invoke("formatPercent", dv.of_float(0.0), dv.of_integer(0))
      expect(result.value).to eq("0%")
    end
  end

  # ---------------------------------------------------------------------------
  # formatLocaleNumber
  # ---------------------------------------------------------------------------
  describe "formatLocaleNumber" do
    it "formats with comma separators and 2 decimals" do
      result = invoke("formatLocaleNumber", dv.of_float(1234567.89), dv.of_integer(2))
      expect(result.value).to eq("1,234,567.89")
    end

    it "formats integer with commas" do
      result = invoke("formatLocaleNumber", dv.of_integer(1000000), dv.of_integer(0))
      expect(result.value).to eq("1,000,000")
    end

    it "formats small number without commas" do
      result = invoke("formatLocaleNumber", dv.of_float(999.99), dv.of_integer(2))
      expect(result.value).to eq("999.99")
    end
  end

  # ---------------------------------------------------------------------------
  # log
  # ---------------------------------------------------------------------------
  describe "log" do
    it "calculates log base 10 of 100" do
      result = invoke("log", dv.of_integer(100), dv.of_integer(10))
      expect(result.value).to be_within(0.0001).of(2.0)
    end

    it "calculates log base 2 of 8" do
      result = invoke("log", dv.of_integer(8), dv.of_integer(2))
      expect(result.value).to be_within(0.0001).of(3.0)
    end

    it "returns null for log of 0" do
      result = invoke("log", dv.of_integer(0), dv.of_integer(10))
      expect(result.null?).to be true
    end

    it "returns null for log of negative number" do
      result = invoke("log", dv.of_integer(-5), dv.of_integer(10))
      expect(result.null?).to be true
    end

    it "returns null for null input" do
      result = invoke("log", dv.of_null, dv.of_integer(10))
      expect(result.null?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # ln
  # ---------------------------------------------------------------------------
  describe "ln" do
    it "calculates ln(e) = 1" do
      result = invoke("ln", dv.of_float(Math::E))
      expect(result.value).to be_within(0.0001).of(1.0)
    end

    it "calculates ln(1) = 0" do
      result = invoke("ln", dv.of_integer(1))
      expect(result.value).to be_within(0.0001).of(0.0)
    end

    it "returns null for ln(0)" do
      result = invoke("ln", dv.of_integer(0))
      expect(result.null?).to be true
    end

    it "returns null for ln(-1)" do
      result = invoke("ln", dv.of_integer(-1))
      expect(result.null?).to be true
    end

    it "returns null for null" do
      result = invoke("ln", dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # log10
  # ---------------------------------------------------------------------------
  describe "log10" do
    it "calculates log10(100) = 2" do
      result = invoke("log10", dv.of_integer(100))
      expect(result.value).to be_within(0.0001).of(2.0)
    end

    it "calculates log10(1000) = 3" do
      result = invoke("log10", dv.of_integer(1000))
      expect(result.value).to be_within(0.0001).of(3.0)
    end

    it "calculates log10(1) = 0" do
      result = invoke("log10", dv.of_integer(1))
      expect(result.value).to be_within(0.0001).of(0.0)
    end

    it "returns null for log10(0)" do
      result = invoke("log10", dv.of_integer(0))
      expect(result.null?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # exp
  # ---------------------------------------------------------------------------
  describe "exp" do
    it "calculates exp(0) = 1" do
      result = invoke("exp", dv.of_integer(0))
      expect(result.value).to be_within(0.0001).of(1.0)
    end

    it "calculates exp(1) = e" do
      result = invoke("exp", dv.of_integer(1))
      expect(result.value).to be_within(0.0001).of(Math::E)
    end

    it "calculates exp(2)" do
      result = invoke("exp", dv.of_integer(2))
      expect(result.value).to be_within(0.0001).of(Math::E**2)
    end

    it "returns null for null" do
      result = invoke("exp", dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # pow
  # ---------------------------------------------------------------------------
  describe "pow" do
    it "calculates 2^10 = 1024" do
      result = invoke("pow", dv.of_integer(2), dv.of_integer(10))
      expect(result.value).to eq(1024)
    end

    it "calculates 3^0 = 1" do
      result = invoke("pow", dv.of_integer(3), dv.of_integer(0))
      expect(result.value).to eq(1)
    end

    it "calculates 5^2 = 25" do
      result = invoke("pow", dv.of_integer(5), dv.of_integer(2))
      expect(result.value).to eq(25)
    end

    it "calculates float power" do
      result = invoke("pow", dv.of_float(2.0), dv.of_float(0.5))
      expect(result.value).to be_within(0.0001).of(Math.sqrt(2))
    end

    it "returns null for null base" do
      result = invoke("pow", dv.of_null, dv.of_integer(2))
      expect(result.null?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # sqrt
  # ---------------------------------------------------------------------------
  describe "sqrt" do
    it "calculates sqrt(4) = 2" do
      result = invoke("sqrt", dv.of_integer(4))
      expect(result.value).to eq(2.0)
    end

    it "calculates sqrt(0) = 0" do
      result = invoke("sqrt", dv.of_integer(0))
      expect(result.value).to eq(0.0)
    end

    it "calculates sqrt(2)" do
      result = invoke("sqrt", dv.of_integer(2))
      expect(result.value).to be_within(0.0001).of(1.4142)
    end

    it "returns null for sqrt(-1)" do
      result = invoke("sqrt", dv.of_integer(-1))
      expect(result.null?).to be true
    end

    it "returns null for null" do
      result = invoke("sqrt", dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # clamp
  # ---------------------------------------------------------------------------
  describe "clamp" do
    it "clamps value above max to max" do
      result = invoke("clamp", dv.of_integer(15), dv.of_integer(0), dv.of_integer(10))
      expect(result.value).to eq(10)
    end

    it "clamps value below min to min" do
      result = invoke("clamp", dv.of_integer(-5), dv.of_integer(0), dv.of_integer(10))
      expect(result.value).to eq(0)
    end

    it "returns value when within range" do
      result = invoke("clamp", dv.of_integer(5), dv.of_integer(0), dv.of_integer(10))
      expect(result.value).to eq(5)
    end

    it "clamps float value" do
      result = invoke("clamp", dv.of_float(3.5), dv.of_float(1.0), dv.of_float(3.0))
      expect(result.value).to eq(3.0)
    end

    it "returns value at exact min boundary" do
      result = invoke("clamp", dv.of_integer(0), dv.of_integer(0), dv.of_integer(10))
      expect(result.value).to eq(0)
    end

    it "returns value at exact max boundary" do
      result = invoke("clamp", dv.of_integer(10), dv.of_integer(0), dv.of_integer(10))
      expect(result.value).to eq(10)
    end

    it "returns null for null value" do
      result = invoke("clamp", dv.of_null, dv.of_integer(0), dv.of_integer(10))
      expect(result.null?).to be true
    end
  end
end
