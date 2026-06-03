# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe "Extra Financial Verbs" do
  let(:engine) { Odin::Transform::TransformEngine.new }
  let(:ctx) { Odin::Transform::VerbContext.new }
  let(:dv) { Odin::Types::DynValue }

  def invoke(name, *args)
    engine.invoke_verb(name, args, ctx)
  end

  def amounts
    dv.of_array([
      dv.of_float(-1000.0),
      dv.of_float(110.0),
      dv.of_float(110.0),
      dv.of_float(110.0),
      dv.of_float(1100.0)
    ])
  end

  def dates
    dv.of_array(
      %w[2020-01-01 2021-01-01 2022-01-01 2023-01-01 2024-01-01].map { |d| dv.of_date(d) }
    )
  end

  # ── xnpv ──

  describe "xnpv" do
    it "discounts dated cash flows on a 365-day basis" do
      result = invoke("xnpv", dv.of_float(0.09), amounts, dates)
      expect(result.value).to be_within(1e-6).of(57.460446077146344)
    end

    it "returns null when amounts and dates differ in length" do
      short_dates = dv.of_array([dv.of_date("2020-01-01"), dv.of_date("2021-01-01")])
      expect(invoke("xnpv", dv.of_float(0.09), amounts, short_dates).null?).to be true
    end

    it "returns null with fewer than three arguments" do
      expect(invoke("xnpv", dv.of_float(0.09), amounts).null?).to be true
    end
  end

  # ── xirr ──

  describe "xirr" do
    it "solves for the dated internal rate of return" do
      result = invoke("xirr", amounts, dates)
      expect(result.value).to be_within(1e-6).of(0.10777982564924497)
    end

    it "honors an explicit guess argument" do
      result = invoke("xirr", amounts, dates, dv.of_float(0.05))
      expect(result.value).to be_within(1e-6).of(0.10777982564924497)
    end

    it "returns null with fewer than two cash flows" do
      single = dv.of_array([dv.of_float(-1000.0)])
      one_date = dv.of_array([dv.of_date("2020-01-01")])
      expect(invoke("xirr", single, one_date).null?).to be true
    end
  end
end
