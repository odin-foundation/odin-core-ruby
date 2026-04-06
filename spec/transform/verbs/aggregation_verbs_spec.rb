# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe "Aggregation Verbs" do
  let(:engine) { Odin::Transform::TransformEngine.new }
  let(:ctx) { Odin::Transform::VerbContext.new }
  let(:dv) { Odin::Types::DynValue }

  def invoke(name, *args)
    engine.invoke_verb(name, args, ctx)
  end

  # ── sum ──

  describe "sum" do
    it "sums integers" do
      arr = dv.of_array([dv.of_integer(1), dv.of_integer(2), dv.of_integer(3)])
      result = invoke("sum", arr)
      expect(result.value).to eq(6)
    end

    it "returns 0 for empty array" do
      arr = dv.of_array([])
      result = invoke("sum", arr)
      expect(result.value).to eq(0)
    end

    it "sums floats" do
      arr = dv.of_array([dv.of_float(1.5), dv.of_float(2.5), dv.of_float(3.0)])
      result = invoke("sum", arr)
      expect(result.value).to be_within(0.01).of(7.0)
    end

    it "skips null values" do
      arr = dv.of_array([dv.of_integer(1), dv.of_null, dv.of_integer(3)])
      result = invoke("sum", arr)
      expect(result.value).to eq(4)
    end

    it "sums mixed integers and floats" do
      arr = dv.of_array([dv.of_integer(1), dv.of_float(2.5)])
      result = invoke("sum", arr)
      expect(result.value).to be_within(0.01).of(3.5)
    end

    it "returns integer type when all inputs are integers" do
      arr = dv.of_array([dv.of_integer(10), dv.of_integer(20)])
      result = invoke("sum", arr)
      expect(result.integer?).to be true
    end
  end

  # ── count ──

  describe "count" do
    it "returns array length" do
      arr = dv.of_array([dv.of_integer(1), dv.of_integer(2), dv.of_integer(3)])
      result = invoke("count", arr)
      expect(result.value).to eq(3)
    end

    it "returns 0 for null" do
      result = invoke("count", dv.of_null)
      expect(result.value).to eq(0)
    end

    it "returns 1 for non-array value" do
      result = invoke("count", dv.of_string("hello"))
      expect(result.value).to eq(1)
    end

    it "returns 0 for empty array" do
      arr = dv.of_array([])
      result = invoke("count", arr)
      expect(result.value).to eq(0)
    end

    it "returns integer type" do
      arr = dv.of_array([dv.of_integer(1)])
      result = invoke("count", arr)
      expect(result.integer?).to be true
    end
  end

  # ── min ──

  describe "min" do
    it "returns minimum value" do
      arr = dv.of_array([dv.of_float(3.0), dv.of_float(1.0), dv.of_float(2.0)])
      result = invoke("min", arr)
      expect(result.value).to be_within(0.01).of(1.0)
    end

    it "returns null for empty array" do
      arr = dv.of_array([])
      result = invoke("min", arr)
      expect(result.null?).to be true
    end

    it "skips null values" do
      arr = dv.of_array([dv.of_float(3.0), dv.of_null, dv.of_float(1.0)])
      result = invoke("min", arr)
      expect(result.value).to be_within(0.01).of(1.0)
    end

    it "works with integers" do
      arr = dv.of_array([dv.of_integer(5), dv.of_integer(2), dv.of_integer(8)])
      result = invoke("min", arr)
      expect(result.value).to eq(2)
    end
  end

  # ── max ──

  describe "max" do
    it "returns maximum value" do
      arr = dv.of_array([dv.of_float(3.0), dv.of_float(1.0), dv.of_float(2.0)])
      result = invoke("max", arr)
      expect(result.value).to be_within(0.01).of(3.0)
    end

    it "returns null for empty array" do
      arr = dv.of_array([])
      result = invoke("max", arr)
      expect(result.null?).to be true
    end

    it "skips null values" do
      arr = dv.of_array([dv.of_null, dv.of_float(5.0), dv.of_float(2.0)])
      result = invoke("max", arr)
      expect(result.value).to be_within(0.01).of(5.0)
    end

    it "works with integers" do
      arr = dv.of_array([dv.of_integer(5), dv.of_integer(2), dv.of_integer(8)])
      result = invoke("max", arr)
      expect(result.value).to eq(8)
    end
  end

  # ── avg ──

  describe "avg" do
    it "computes average" do
      arr = dv.of_array([dv.of_float(2.0), dv.of_float(4.0), dv.of_float(6.0)])
      result = invoke("avg", arr)
      expect(result.value).to be_within(0.01).of(4.0)
    end

    it "returns null for empty array" do
      arr = dv.of_array([])
      result = invoke("avg", arr)
      expect(result.null?).to be true
    end

    it "returns float type" do
      arr = dv.of_array([dv.of_integer(2), dv.of_integer(4)])
      result = invoke("avg", arr)
      expect(result.float?).to be true
    end

    it "skips null values" do
      arr = dv.of_array([dv.of_float(2.0), dv.of_null, dv.of_float(4.0)])
      result = invoke("avg", arr)
      expect(result.value).to be_within(0.01).of(3.0)
    end
  end

  # ── first ──

  describe "first" do
    it "returns first element" do
      arr = dv.of_array([dv.of_string("a"), dv.of_string("b"), dv.of_string("c")])
      result = invoke("first", arr)
      expect(result.value).to eq("a")
    end

    it "returns null for empty array" do
      arr = dv.of_array([])
      result = invoke("first", arr)
      expect(result.null?).to be true
    end

    it "returns null for null input" do
      result = invoke("first", dv.of_null)
      expect(result.null?).to be true
    end

    it "returns null for non-array" do
      result = invoke("first", dv.of_string("hello"))
      expect(result.null?).to be true
    end
  end

  # ── last ──

  describe "last" do
    it "returns last element" do
      arr = dv.of_array([dv.of_string("a"), dv.of_string("b"), dv.of_string("c")])
      result = invoke("last", arr)
      expect(result.value).to eq("c")
    end

    it "returns null for empty array" do
      arr = dv.of_array([])
      result = invoke("last", arr)
      expect(result.null?).to be true
    end

    it "returns null for null input" do
      result = invoke("last", dv.of_null)
      expect(result.null?).to be true
    end

    it "returns null for non-array" do
      result = invoke("last", dv.of_integer(42))
      expect(result.null?).to be true
    end
  end

  # ── accumulate ──

  describe "accumulate" do
    it "accumulates numeric values across calls" do
      r1 = invoke("accumulate", dv.of_string("total"), dv.of_integer(10))
      expect(r1.value).to eq(10)

      r2 = invoke("accumulate", dv.of_string("total"), dv.of_integer(20))
      expect(r2.value).to eq(30)

      r3 = invoke("accumulate", dv.of_string("total"), dv.of_integer(30))
      expect(r3.value).to eq(60)
    end

    it "concatenates strings" do
      invoke("accumulate", dv.of_string("buf"), dv.of_string("hello"))
      result = invoke("accumulate", dv.of_string("buf"), dv.of_string(" world"))
      expect(result.value).to eq("hello world")
    end

    it "uses initial value on first call" do
      result = invoke("accumulate", dv.of_string("fresh"), dv.of_integer(42))
      expect(result.value).to eq(42)
    end

    it "uses independent accumulators per name" do
      invoke("accumulate", dv.of_string("a"), dv.of_integer(10))
      invoke("accumulate", dv.of_string("b"), dv.of_integer(100))
      ra = invoke("accumulate", dv.of_string("a"), dv.of_integer(5))
      rb = invoke("accumulate", dv.of_string("b"), dv.of_integer(50))
      expect(ra.value).to eq(15)
      expect(rb.value).to eq(150)
    end
  end

  # ── set / get_accumulator ──

  describe "set" do
    it "stores a value retrievable via get_accumulator" do
      invoke("set", dv.of_string("mykey"), dv.of_integer(42))
      stored = ctx.get_accumulator("mykey")
      expect(stored.value).to eq(42)
    end

    it "overwrites previous value" do
      invoke("set", dv.of_string("mykey"), dv.of_integer(1))
      invoke("set", dv.of_string("mykey"), dv.of_integer(2))
      stored = ctx.get_accumulator("mykey")
      expect(stored.value).to eq(2)
    end

    it "returns the value that was set" do
      result = invoke("set", dv.of_string("mykey"), dv.of_string("hello"))
      expect(result.value).to eq("hello")
    end

    it "stores null value" do
      invoke("set", dv.of_string("mykey"), dv.of_null)
      stored = ctx.get_accumulator("mykey")
      expect(stored.null?).to be true
    end

    it "stores different types" do
      invoke("set", dv.of_string("k1"), dv.of_integer(1))
      invoke("set", dv.of_string("k2"), dv.of_string("hello"))
      invoke("set", dv.of_string("k3"), dv.of_bool(true))
      expect(ctx.get_accumulator("k1").integer?).to be true
      expect(ctx.get_accumulator("k2").string?).to be true
      expect(ctx.get_accumulator("k3").bool?).to be true
    end
  end
end
