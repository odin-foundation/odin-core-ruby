# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe "Extra Numeric Verbs" do
  let(:engine) { Odin::Transform::TransformEngine.new }
  let(:ctx) { Odin::Transform::VerbContext.new }
  let(:dv) { Odin::Types::DynValue }

  def invoke(name, *args)
    engine.invoke_verb(name, args, ctx)
  end

  # ── gcd ──

  describe "gcd" do
    it "computes the greatest common divisor" do
      expect(invoke("gcd", dv.of_integer(12), dv.of_integer(18)).value).to eq(6)
    end

    it "returns the other operand when one is zero" do
      expect(invoke("gcd", dv.of_integer(0), dv.of_integer(12)).value).to eq(12)
    end

    it "ignores sign" do
      expect(invoke("gcd", dv.of_integer(-12), dv.of_integer(18)).value).to eq(6)
    end

    it "returns null with fewer than two arguments" do
      expect(invoke("gcd", dv.of_integer(12)).null?).to be true
    end
  end

  # ── lcm ──

  describe "lcm" do
    it "computes the least common multiple" do
      expect(invoke("lcm", dv.of_integer(4), dv.of_integer(6)).value).to eq(12)
    end

    it "returns zero when an operand is zero" do
      expect(invoke("lcm", dv.of_integer(0), dv.of_integer(4)).value).to eq(0)
    end

    it "returns null with fewer than two arguments" do
      expect(invoke("lcm", dv.of_integer(4)).null?).to be true
    end
  end

  # ── factorial ──

  describe "factorial" do
    it "computes factorial of 5" do
      expect(invoke("factorial", dv.of_integer(5)).value).to eq(120)
    end

    it "returns 1 for zero" do
      expect(invoke("factorial", dv.of_integer(0)).value).to eq(1)
    end

    it "computes factorial at the upper bound of 18" do
      expect(invoke("factorial", dv.of_integer(18)).value).to eq(6_402_373_705_728_000)
    end

    it "returns null past the upper bound" do
      expect(invoke("factorial", dv.of_integer(19)).null?).to be true
    end

    it "returns null for a negative input" do
      expect(invoke("factorial", dv.of_integer(-1)).null?).to be true
    end

    it "returns null for a non-integer input" do
      expect(invoke("factorial", dv.of_float(3.5)).null?).to be true
    end

    it "returns null for no arguments" do
      expect(invoke("factorial").null?).to be true
    end
  end
end
