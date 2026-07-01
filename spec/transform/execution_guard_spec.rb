# frozen_string_literal: true

require_relative "../spec_helper"

# Transform execution guard: fuel budget (T016), wall-clock timeout (T017), and
# expression-depth enforcement (T018). Guards charge only when their limit is set
# (> 0); depth uses its standing default. Aborts are not downgraded by onError and
# surface as a failed result, never raised past execute.
RSpec.describe "transform execution guard" do
  let(:parser) { Odin::Transform::TransformParser.new }
  let(:engine) { Odin::Transform::TransformEngine.new }

  def base_header
    %({$}\nodin = "1.0.0"\ntransform = "1.0.0"\ndirection = "json->json"\n\n)
  end

  def header_with(on_error)
    base_header + %({$target}\nformat = "json"\nonError = "#{on_error}"\n\n)
  end

  def run(body, source = {}, head = base_header)
    engine.execute(parser.parse(head + body), source)
  end

  # Chain of n nested unary verbs, evaluated one level per node.
  def nest_abs(n)
    "{out}\nr = " + ("%abs " * n) + "##1"
  end

  # Descending array of the given length so a sort does real work.
  def descending(n)
    (0...n).map { |i| n - i }
  end

  after do
    %w[ODIN_MAX_TRANSFORM_FUEL ODIN_TRANSFORM_TIMEOUT_MS ODIN_MAX_EXPRESSION_DEPTH].each { |k| ENV.delete(k) }
  end

  describe "unbounded when unset" do
    it "runs a normal transform to completion with all limits off" do
      r = run(%({out}\nr = %upper "hi"))
      expect(r.success?).to be(true)
      expect(r.errors).to be_empty
    end

    it "does not charge fuel when the cap is unset" do
      r = run(%({out}\nr = %sort @big), { "big" => descending(500) })
      expect(r.success?).to be(true)
    end
  end

  describe "fuel budget (T016)" do
    it "aborts an over-computing transform with a failed result" do
      ENV["ODIN_MAX_TRANSFORM_FUEL"] = "50"
      r = run(%({out}\nr = %sort @big), { "big" => descending(200) })
      expect(r.success?).to be(false)
      expect(r.errors.map(&:code)).to include("T016")
    end

    it "charges array verbs proportional to width, so a large array cannot escape" do
      ENV["ODIN_MAX_TRANSFORM_FUEL"] = "50"
      small = run(%({out}\nr = %sort @big), { "big" => [3, 1, 2] })
      expect(small.success?).to be(true)

      large = run(%({out}\nr = %sort @big), { "big" => descending(200) })
      expect(large.success?).to be(false)
      expect(large.errors.map(&:code)).to include("T016")
    end
  end

  describe "wall-clock timeout (T017)" do
    it "aborts when elapsed exceeds the timeout" do
      ENV["ODIN_TRANSFORM_TIMEOUT_MS"] = "100"
      # Each read jumps well past the bound, so any read after start reports
      # elapsed > timeout regardless of ordering.
      clock = 0
      allow(engine).to receive(:monotonic_ms) { clock += 10_000 }
      r = run(%({out}\nr = %sort @big), { "big" => descending(2000) })
      expect(r.success?).to be(false)
      expect(r.errors.map(&:code)).to include("T017")
    end
  end

  describe "expression depth (T018)" do
    it "yields a clean depth error under a low cap" do
      ENV["ODIN_MAX_EXPRESSION_DEPTH"] = "8"
      r = run(nest_abs(30))
      expect(r.success?).to be(false)
      expect(r.errors.map(&:code)).to include("T018")
    end

    it "converts deep nesting into a typed error, not a stack overflow" do
      expect { run(nest_abs(200)) }.not_to raise_error
      r = run(nest_abs(200))
      expect(r.success?).to be(false)
      expect(r.errors.map(&:code)).to include("T018")
    end
  end

  describe "non-swallowable abort" do
    it "is not downgraded to a warning by onError" do
      ENV["ODIN_MAX_TRANSFORM_FUEL"] = "50"
      r = run(%({out}\nr = %sort @big), { "big" => descending(200) }, header_with("warn"))
      expect(r.success?).to be(false)
      expect(r.errors.map(&:code)).to include("T016")
      expect(r.warnings.map { |w| w.respond_to?(:code) ? w.code : nil }).not_to include("T016")
    end
  end
end
