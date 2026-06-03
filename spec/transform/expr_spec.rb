# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "%expr macro" do
  let(:engine) { Odin::Transform::TransformEngine.new }
  let(:parser) { Odin::Transform::TransformParser.new }

  let(:header) do
    <<~ODIN
      {$}
      odin = "1.0.0"
      transform = "1.0.0"
      direction = "json->json"
    ODIN
  end

  def run(body, source = { "seed" => 0 })
    transform_def = parser.parse(header + "\n" + body)
    engine.execute(transform_def, source)
  end

  def evaluate(formula, source = { "seed" => 0 })
    run("{out}\nr = %expr #{formula}", source).output["out"]["r"]
  end

  # ── precedence and associativity ──

  describe "precedence and associativity" do
    it "applies multiplication before addition" do
      expect(evaluate('"2 + 3 * 4"')).to eq(14)
    end

    it "treats power as right-associative (2^3^2 = 512)" do
      expect(evaluate('"2^3^2"')).to eq(512)
    end

    it "binds unary minus looser than power (-2^2 = -4)" do
      expect(evaluate('"-2^2"')).to eq(-4)
    end

    it "negates the base inside parentheses ((-2)^2 = 4)" do
      expect(evaluate('"(-2)^2"')).to eq(4)
    end
  end

  # ── operators ──

  describe "operators" do
    it "divides to a fraction" do
      expect(evaluate('"1 / 2"')).to eq(0.5)
    end

    it "computes a modulo" do
      expect(evaluate('"5 % 2"')).to eq(1)
    end

    it "yields null on division by zero" do
      expect(evaluate('"1 / 0"')).to be_nil
    end
  end

  # ── functions ──

  describe "functions" do
    it "applies abs" do
      expect(evaluate('"abs(-7)"')).to eq(7)
    end

    it "sums variadic min and max" do
      expect(evaluate('"min(3, 5, 1) + max(3, 5, 1)"')).to eq(6)
    end

    it "rounds with a default scale of 0" do
      expect(evaluate('"round(3.7)"')).to eq(4)
    end

    it "computes a pythagorean hypotenuse from a bindings object" do
      out = run("{out}\nr = %expr \"sqrt(x^2 + y^2)\" @.v", { "v" => { "x" => 3, "y" => 4 } })
      expect(out.output["out"]["r"]).to eq(5)
    end
  end

  # ── variables ──

  describe "variables" do
    it "resolves names under the explicit bindings object" do
      out = run("{out}\nr = %expr \"a + b\" @.vars", { "vars" => { "a" => 10, "b" => 5 } })
      expect(out.output["out"]["r"]).to eq(15)
    end
  end

  # ── compile errors ──

  describe "compile errors" do
    it "rejects an unknown function" do
      expect { parser.parse(header + "\n{out}\nr = %expr \"sin(1)\"") }
        .to raise_error(Odin::Transform::Expr::ExprSyntaxError)
    end

    it "rejects unbalanced parentheses" do
      expect { parser.parse(header + "\n{out}\nr = %expr \"(1 + 2\"") }
        .to raise_error(Odin::Transform::Expr::ExprSyntaxError)
    end

    it "rejects a variable with no bindings object" do
      expect { parser.parse(header + "\n{out}\nr = %expr \"a + 1\"") }
        .to raise_error(Odin::Transform::Expr::ExprSyntaxError)
    end
  end
end
