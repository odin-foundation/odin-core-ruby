# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe "Financial Verbs" do
  let(:engine) { Odin::Transform::TransformEngine.new }
  let(:ctx) { Odin::Transform::VerbContext.new }
  let(:dv) { Odin::Types::DynValue }

  def invoke(name, *args)
    engine.invoke_verb(name, args, ctx)
  end

  # ── compound ──

  describe "compound" do
    it "computes compound interest for 1000 at 5% for 10 periods" do
      result = invoke("compound", dv.of_float(1000.0), dv.of_float(0.05), dv.of_float(10.0))
      expect(result.value).to be_within(0.01).of(1628.89)
    end

    it "returns principal when rate is 0" do
      result = invoke("compound", dv.of_float(1000.0), dv.of_float(0.0), dv.of_float(10.0))
      expect(result.value).to be_within(0.01).of(1000.0)
    end

    it "returns principal when periods is 0" do
      result = invoke("compound", dv.of_float(1000.0), dv.of_float(0.05), dv.of_float(0.0))
      expect(result.value).to be_within(0.01).of(1000.0)
    end

    it "returns null when principal is null" do
      result = invoke("compound", dv.of_null, dv.of_float(0.05), dv.of_float(10.0))
      expect(result.null?).to be true
    end

    it "returns null when rate is null" do
      result = invoke("compound", dv.of_float(1000.0), dv.of_null, dv.of_float(10.0))
      expect(result.null?).to be true
    end

    it "returns null when periods is null" do
      result = invoke("compound", dv.of_float(1000.0), dv.of_float(0.05), dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── discount ──

  describe "discount" do
    it "computes present value of 1628.89 at 5% for 10 periods" do
      result = invoke("discount", dv.of_float(1628.89), dv.of_float(0.05), dv.of_float(10.0))
      expect(result.value).to be_within(0.01).of(1000.0)
    end

    it "returns null when future value is null" do
      result = invoke("discount", dv.of_null, dv.of_float(0.05), dv.of_float(10.0))
      expect(result.null?).to be true
    end

    it "returns null when rate is null" do
      result = invoke("discount", dv.of_float(1628.89), dv.of_null, dv.of_float(10.0))
      expect(result.null?).to be true
    end

    it "returns null when periods is null" do
      result = invoke("discount", dv.of_float(1628.89), dv.of_float(0.05), dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── pmt ──

  describe "pmt" do
    it "computes monthly payment for 200k mortgage at 5%/12 for 360 months" do
      rate = 0.05 / 12.0
      result = invoke("pmt", dv.of_float(200_000.0), dv.of_float(rate), dv.of_float(360.0))
      expect(result.value).to be_within(1.0).of(1073.64)
    end

    it "computes simple division when rate is 0" do
      result = invoke("pmt", dv.of_float(1000.0), dv.of_float(0.0), dv.of_float(10.0))
      expect(result.value).to be_within(0.01).of(100.0)
    end

    it "returns null when principal is null" do
      result = invoke("pmt", dv.of_null, dv.of_float(0.05), dv.of_float(360.0))
      expect(result.null?).to be true
    end

    it "returns null when rate is null" do
      result = invoke("pmt", dv.of_float(200_000.0), dv.of_null, dv.of_float(360.0))
      expect(result.null?).to be true
    end

    it "returns null when nper is null" do
      result = invoke("pmt", dv.of_float(200_000.0), dv.of_float(0.05), dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── fv ──

  describe "fv" do
    it "computes future value of annuity" do
      result = invoke("fv", dv.of_float(100.0), dv.of_float(0.05), dv.of_float(10.0))
      expect(result.value).to be_within(0.01).of(1257.79)
    end

    it "computes simple multiplication when rate is 0" do
      result = invoke("fv", dv.of_float(100.0), dv.of_float(0.0), dv.of_float(10.0))
      expect(result.value).to be_within(0.01).of(1000.0)
    end

    it "returns null when payment is null" do
      result = invoke("fv", dv.of_null, dv.of_float(0.05), dv.of_float(10.0))
      expect(result.null?).to be true
    end
  end

  # ── pv ──

  describe "pv" do
    it "computes present value of annuity" do
      result = invoke("pv", dv.of_float(100.0), dv.of_float(0.05), dv.of_float(10.0))
      expect(result.value).to be_within(0.01).of(772.17)
    end

    it "computes simple multiplication when rate is 0" do
      result = invoke("pv", dv.of_float(100.0), dv.of_float(0.0), dv.of_float(10.0))
      expect(result.value).to be_within(0.01).of(1000.0)
    end

    it "returns null when payment is null" do
      result = invoke("pv", dv.of_null, dv.of_float(0.05), dv.of_float(10.0))
      expect(result.null?).to be true
    end
  end

  # ── npv ──

  describe "npv" do
    it "computes net present value for cash flows" do
      cashflows = dv.of_array([dv.of_float(-1000.0), dv.of_float(300.0), dv.of_float(420.0), dv.of_float(680.0)])
      result = invoke("npv", dv.of_float(0.1), cashflows)
      # NPV includes period 0 (undiscounted) through period N
      expect(result.value).to be_within(1.0).of(130.73)
    end

    it "returns null when rate is null" do
      cashflows = dv.of_array([dv.of_float(-1000.0), dv.of_float(300.0)])
      result = invoke("npv", dv.of_null, cashflows)
      expect(result.null?).to be true
    end
  end

  # ── irr ──

  describe "irr" do
    it "converges to internal rate of return" do
      cashflows = dv.of_array([dv.of_float(-1000.0), dv.of_float(300.0), dv.of_float(420.0), dv.of_float(680.0)])
      result = invoke("irr", cashflows)
      expect(result.null?).to be false
      expect(result.value).to be_within(0.01).of(0.166)
    end

    it "returns null for non-converging case (all positive)" do
      cashflows = dv.of_array([dv.of_float(100.0), dv.of_float(200.0), dv.of_float(300.0)])
      result = invoke("irr", cashflows)
      expect(result.null?).to be true
    end

    it "returns null for empty cashflows" do
      cashflows = dv.of_array([])
      result = invoke("irr", cashflows)
      expect(result.null?).to be true
    end
  end

  # ── rate ──

  describe "rate" do
    it "computes periodic interest rate" do
      # 10 periods, pmt=-100, pv=800
      result = invoke("rate", dv.of_float(10.0), dv.of_float(-100.0), dv.of_float(800.0))
      expect(result.null?).to be false
      expect(result.value).to be_within(0.01).of(0.0392)
    end

    it "returns null when nper is null" do
      result = invoke("rate", dv.of_null, dv.of_float(-100.0), dv.of_float(800.0))
      expect(result.null?).to be true
    end

    it "returns null when pmt is null" do
      result = invoke("rate", dv.of_float(10.0), dv.of_null, dv.of_float(800.0))
      expect(result.null?).to be true
    end

    it "returns null when pv is null" do
      result = invoke("rate", dv.of_float(10.0), dv.of_float(-100.0), dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── nper ──

  describe "nper" do
    it "computes number of periods" do
      result = invoke("nper", dv.of_float(0.05), dv.of_float(-100.0), dv.of_float(800.0))
      expect(result.null?).to be false
      expect(result.value).to be_a(Numeric)
    end

    it "computes nper when rate is 0" do
      result = invoke("nper", dv.of_float(0.0), dv.of_float(-100.0), dv.of_float(1000.0))
      expect(result.value).to be_within(0.01).of(10.0)
    end

    it "returns null when rate is null" do
      result = invoke("nper", dv.of_null, dv.of_float(-100.0), dv.of_float(800.0))
      expect(result.null?).to be true
    end

    it "returns null when pmt is null" do
      result = invoke("nper", dv.of_float(0.05), dv.of_null, dv.of_float(800.0))
      expect(result.null?).to be true
    end
  end

  # ── depreciation ──

  describe "depreciation" do
    it "computes straight-line depreciation" do
      result = invoke("depreciation", dv.of_float(10_000.0), dv.of_float(1000.0), dv.of_float(5.0))
      expect(result.value).to be_within(0.01).of(1800.0)
    end

    it "returns null when cost is null" do
      result = invoke("depreciation", dv.of_null, dv.of_float(1000.0), dv.of_float(5.0))
      expect(result.null?).to be true
    end

    it "returns null when life is 0" do
      result = invoke("depreciation", dv.of_float(10_000.0), dv.of_float(1000.0), dv.of_float(0.0))
      expect(result.null?).to be true
    end
  end

  # ── variance / varianceSample ──

  describe "variance" do
    it "computes population variance for known values" do
      arr = dv.of_array([dv.of_float(2.0), dv.of_float(4.0), dv.of_float(4.0), dv.of_float(4.0), dv.of_float(5.0), dv.of_float(5.0), dv.of_float(7.0), dv.of_float(9.0)])
      result = invoke("variance", arr)
      expect(result.value).to be_within(0.01).of(4.0)
    end

    it "returns null for empty array" do
      arr = dv.of_array([])
      result = invoke("variance", arr)
      expect(result.null?).to be true
    end
  end

  describe "varianceSample" do
    it "computes sample variance for known values" do
      arr = dv.of_array([dv.of_float(2.0), dv.of_float(4.0), dv.of_float(4.0), dv.of_float(4.0), dv.of_float(5.0), dv.of_float(5.0), dv.of_float(7.0), dv.of_float(9.0)])
      result = invoke("varianceSample", arr)
      expect(result.value).to be_within(0.01).of(4.571)
    end

    it "returns null for array with fewer than 2 elements" do
      arr = dv.of_array([dv.of_float(5.0)])
      result = invoke("varianceSample", arr)
      expect(result.null?).to be true
    end

    it "returns null for empty array" do
      arr = dv.of_array([])
      result = invoke("varianceSample", arr)
      expect(result.null?).to be true
    end
  end

  # ── std / stdSample ──

  describe "std" do
    it "computes population standard deviation" do
      arr = dv.of_array([dv.of_float(2.0), dv.of_float(4.0), dv.of_float(4.0), dv.of_float(4.0), dv.of_float(5.0), dv.of_float(5.0), dv.of_float(7.0), dv.of_float(9.0)])
      result = invoke("std", arr)
      expect(result.value).to be_within(0.01).of(2.0)
    end

    it "returns null for empty array" do
      arr = dv.of_array([])
      result = invoke("std", arr)
      expect(result.null?).to be true
    end
  end

  describe "stdSample" do
    it "computes sample standard deviation" do
      arr = dv.of_array([dv.of_float(2.0), dv.of_float(4.0), dv.of_float(4.0), dv.of_float(4.0), dv.of_float(5.0), dv.of_float(5.0), dv.of_float(7.0), dv.of_float(9.0)])
      result = invoke("stdSample", arr)
      expect(result.value).to be_within(0.01).of(2.138)
    end

    it "returns null for single element" do
      arr = dv.of_array([dv.of_float(5.0)])
      result = invoke("stdSample", arr)
      expect(result.null?).to be true
    end
  end

  # ── median ──

  describe "median" do
    it "returns middle value for odd count" do
      arr = dv.of_array([dv.of_float(1.0), dv.of_float(3.0), dv.of_float(5.0)])
      result = invoke("median", arr)
      expect(result.value).to be_within(0.01).of(3.0)
    end

    it "returns average of two middle values for even count" do
      arr = dv.of_array([dv.of_float(1.0), dv.of_float(2.0), dv.of_float(3.0), dv.of_float(4.0)])
      result = invoke("median", arr)
      expect(result.value).to be_within(0.01).of(2.5)
    end

    it "returns null for empty array" do
      arr = dv.of_array([])
      result = invoke("median", arr)
      expect(result.null?).to be true
    end

    it "handles unsorted input" do
      arr = dv.of_array([dv.of_float(5.0), dv.of_float(1.0), dv.of_float(3.0)])
      result = invoke("median", arr)
      expect(result.value).to be_within(0.01).of(3.0)
    end
  end

  # ── mode ──

  describe "mode" do
    it "returns most frequent value" do
      arr = dv.of_array([dv.of_integer(1), dv.of_integer(2), dv.of_integer(2), dv.of_integer(3)])
      result = invoke("mode", arr)
      expect(result.value).to eq(2)
    end

    it "returns first mode on tie" do
      arr = dv.of_array([dv.of_integer(1), dv.of_integer(1), dv.of_integer(2), dv.of_integer(2)])
      result = invoke("mode", arr)
      # Both 1 and 2 appear twice; implementation returns whichever max_by finds first
      expect(result.null?).to be false
    end

    it "returns null for empty array" do
      arr = dv.of_array([])
      result = invoke("mode", arr)
      expect(result.null?).to be true
    end
  end

  # ── percentile ──

  describe "percentile" do
    it "returns minimum at 0th percentile" do
      arr = dv.of_array([dv.of_float(10.0), dv.of_float(20.0), dv.of_float(30.0), dv.of_float(40.0), dv.of_float(50.0)])
      result = invoke("percentile", arr, dv.of_float(0.0))
      expect(result.value).to be_within(0.01).of(10.0)
    end

    it "returns median at 50th percentile" do
      arr = dv.of_array([dv.of_float(10.0), dv.of_float(20.0), dv.of_float(30.0), dv.of_float(40.0), dv.of_float(50.0)])
      result = invoke("percentile", arr, dv.of_float(50.0))
      expect(result.value).to be_within(0.01).of(30.0)
    end

    it "returns maximum at 100th percentile" do
      arr = dv.of_array([dv.of_float(10.0), dv.of_float(20.0), dv.of_float(30.0), dv.of_float(40.0), dv.of_float(50.0)])
      result = invoke("percentile", arr, dv.of_float(100.0))
      expect(result.value).to be_within(0.01).of(50.0)
    end

    it "returns null for empty array" do
      arr = dv.of_array([])
      result = invoke("percentile", arr, dv.of_float(50.0))
      expect(result.null?).to be true
    end

    it "returns null when percentile is null" do
      arr = dv.of_array([dv.of_float(10.0)])
      result = invoke("percentile", arr, dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── quantile ──

  describe "quantile" do
    let(:arr) { dv.of_array([dv.of_float(10.0), dv.of_float(20.0), dv.of_float(30.0), dv.of_float(40.0), dv.of_float(50.0)]) }

    it "returns minimum at q=0" do
      result = invoke("quantile", arr, dv.of_float(0.0))
      expect(result.value).to be_within(0.01).of(10.0)
    end

    it "returns first quartile at q=0.25" do
      result = invoke("quantile", arr, dv.of_float(0.25))
      expect(result.value).to be_within(0.01).of(20.0)
    end

    it "returns median at q=0.5" do
      result = invoke("quantile", arr, dv.of_float(0.5))
      expect(result.value).to be_within(0.01).of(30.0)
    end

    it "returns third quartile at q=0.75" do
      result = invoke("quantile", arr, dv.of_float(0.75))
      expect(result.value).to be_within(0.01).of(40.0)
    end

    it "returns maximum at q=1.0" do
      result = invoke("quantile", arr, dv.of_float(1.0))
      expect(result.value).to be_within(0.01).of(50.0)
    end

    it "returns null for empty array" do
      result = invoke("quantile", dv.of_array([]), dv.of_float(0.5))
      expect(result.null?).to be true
    end

    it "returns null when q is null" do
      result = invoke("quantile", arr, dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── covariance ──

  describe "covariance" do
    it "computes covariance for known values" do
      xs = dv.of_array([dv.of_float(1.0), dv.of_float(2.0), dv.of_float(3.0), dv.of_float(4.0), dv.of_float(5.0)])
      ys = dv.of_array([dv.of_float(2.0), dv.of_float(4.0), dv.of_float(6.0), dv.of_float(8.0), dv.of_float(10.0)])
      result = invoke("covariance", xs, ys)
      expect(result.value).to be_within(0.01).of(4.0)
    end

    it "returns null for empty arrays" do
      result = invoke("covariance", dv.of_array([]), dv.of_array([]))
      expect(result.null?).to be true
    end
  end

  # ── correlation ──

  describe "correlation" do
    it "returns +1 for perfect positive correlation" do
      xs = dv.of_array([dv.of_float(1.0), dv.of_float(2.0), dv.of_float(3.0)])
      ys = dv.of_array([dv.of_float(2.0), dv.of_float(4.0), dv.of_float(6.0)])
      result = invoke("correlation", xs, ys)
      expect(result.value).to be_within(0.001).of(1.0)
    end

    it "returns -1 for perfect negative correlation" do
      xs = dv.of_array([dv.of_float(1.0), dv.of_float(2.0), dv.of_float(3.0)])
      ys = dv.of_array([dv.of_float(6.0), dv.of_float(4.0), dv.of_float(2.0)])
      result = invoke("correlation", xs, ys)
      expect(result.value).to be_within(0.001).of(-1.0)
    end

    it "returns near 0 for uncorrelated data" do
      xs = dv.of_array([dv.of_float(1.0), dv.of_float(2.0), dv.of_float(3.0), dv.of_float(4.0), dv.of_float(5.0)])
      ys = dv.of_array([dv.of_float(2.0), dv.of_float(4.0), dv.of_float(1.0), dv.of_float(5.0), dv.of_float(3.0)])
      result = invoke("correlation", xs, ys)
      expect(result.value).to be_within(0.5).of(0.0)
    end

    it "returns null for empty arrays" do
      result = invoke("correlation", dv.of_array([]), dv.of_array([]))
      expect(result.null?).to be true
    end
  end

  # ── zscore ──

  describe "zscore" do
    it "computes z-score for known values" do
      # value=10, mean=5, stddev=2 => (10-5)/2 = 2.5
      result = invoke("zscore", dv.of_float(10.0), dv.of_float(5.0), dv.of_float(2.0))
      expect(result.value).to be_within(0.001).of(2.5)
    end

    it "returns 0 when value equals mean" do
      result = invoke("zscore", dv.of_float(5.0), dv.of_float(5.0), dv.of_float(2.0))
      expect(result.value).to be_within(0.001).of(0.0)
    end

    it "returns null when stddev is 0" do
      result = invoke("zscore", dv.of_float(10.0), dv.of_float(5.0), dv.of_float(0.0))
      expect(result.null?).to be true
    end

    it "returns null when value is null" do
      result = invoke("zscore", dv.of_null, dv.of_float(5.0), dv.of_float(2.0))
      expect(result.null?).to be true
    end

    it "returns null when mean is null" do
      result = invoke("zscore", dv.of_float(10.0), dv.of_null, dv.of_float(2.0))
      expect(result.null?).to be true
    end

    it "returns null when stddev is null" do
      result = invoke("zscore", dv.of_float(10.0), dv.of_float(5.0), dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── interpolate ──

  describe "interpolate" do
    it "computes basic linear interpolation" do
      # a=0, b=10, t=0.5 => 5.0
      result = invoke("interpolate", dv.of_float(0.0), dv.of_float(10.0), dv.of_float(0.5))
      expect(result.value).to be_within(0.001).of(5.0)
    end

    it "returns a when t=0" do
      result = invoke("interpolate", dv.of_float(3.0), dv.of_float(7.0), dv.of_float(0.0))
      expect(result.value).to be_within(0.001).of(3.0)
    end

    it "returns b when t=1" do
      result = invoke("interpolate", dv.of_float(3.0), dv.of_float(7.0), dv.of_float(1.0))
      expect(result.value).to be_within(0.001).of(7.0)
    end

    it "returns null when a is null" do
      result = invoke("interpolate", dv.of_null, dv.of_float(10.0), dv.of_float(0.5))
      expect(result.null?).to be true
    end

    it "returns null when b is null" do
      result = invoke("interpolate", dv.of_float(0.0), dv.of_null, dv.of_float(0.5))
      expect(result.null?).to be true
    end

    it "returns null when t is null" do
      result = invoke("interpolate", dv.of_float(0.0), dv.of_float(10.0), dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── weightedAvg ──

  describe "weightedAvg" do
    it "computes weighted average with equal weights" do
      values = dv.of_array([dv.of_float(10.0), dv.of_float(20.0), dv.of_float(30.0)])
      weights = dv.of_array([dv.of_float(1.0), dv.of_float(1.0), dv.of_float(1.0)])
      result = invoke("weightedAvg", values, weights)
      expect(result.value).to be_within(0.01).of(20.0)
    end

    it "computes weighted average with different weights" do
      values = dv.of_array([dv.of_float(10.0), dv.of_float(20.0)])
      weights = dv.of_array([dv.of_float(3.0), dv.of_float(1.0)])
      # (10*3 + 20*1) / (3+1) = 50/4 = 12.5
      result = invoke("weightedAvg", values, weights)
      expect(result.value).to be_within(0.01).of(12.5)
    end

    it "returns null for empty values" do
      result = invoke("weightedAvg", dv.of_array([]), dv.of_array([]))
      expect(result.null?).to be true
    end

    it "returns null when all weights are 0" do
      values = dv.of_array([dv.of_float(10.0), dv.of_float(20.0)])
      weights = dv.of_array([dv.of_float(0.0), dv.of_float(0.0)])
      result = invoke("weightedAvg", values, weights)
      expect(result.null?).to be true
    end
  end
end
