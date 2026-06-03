# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "Transform engine behaviors" do
  let(:engine) { Odin::Transform::TransformEngine.new }
  let(:parser) { Odin::Transform::TransformParser.new }

  def run(transform_text, source)
    transform_def = parser.parse(transform_text)
    engine.execute(transform_def, source)
  end

  # ── Multi-sink: two accumulators advance in one loop pass ──

  describe "multi-sink accumulation" do
    it "advances a running total and a count in the same loop pass" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {$accumulator}
        total = ##0
        total._persist = true
        count = ##0
        count._persist = true

        {_loopSink[]}
        :loop items
        _t = "%accumulate total @.amount"
        _c = "%accumulate count ##1"

        {Summary}
        total = "@$accumulator.total"
        count = "@$accumulator.count"
      ODIN
      result = run(text, { "items" => [{ "amount" => 10 }, { "amount" => 20 }, { "amount" => 30 }] })
      expect(result.output["Summary"]).to eq({ "total" => 60, "count" => 3 })
    end
  end

  # ── Lazy control flow: only the selected branch runs ──

  describe "lazy control-flow evaluation" do
    it "runs only the selected ifElse branch and short-circuits and/or" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {$accumulator}
        andRhs = ##0
        andRhs._persist = true
        orRhs = ##0
        orRhs._persist = true
        chosen = ##0
        chosen._persist = true
        skipped = ##0
        skipped._persist = true

        {_eval}
        _a = %and ?false %accumulate andRhs ##1
        _b = %or ?true %accumulate orRhs ##1
        _c = %ifElse ?true %accumulate chosen ##1 %accumulate skipped ##1

        {out}
        andRhsRan = "@$accumulator.andRhs"
        orRhsRan = "@$accumulator.orRhs"
        chosenRan = "@$accumulator.chosen"
        skippedRan = "@$accumulator.skipped"
      ODIN
      result = run(text, { "seed" => 0 })
      expect(result.output["out"]).to eq({
        "andRhsRan" => 0,
        "orRhsRan" => 0,
        "chosenRan" => 1,
        "skippedRan" => 0
      })
    end

    it "skips the unselected coalesce/ifNull/ifEmpty operands" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {$accumulator}
        side = ##0
        side._persist = true

        {_eval}
        _c = %coalesce "present" %accumulate side ##1
        _n = %ifNull "value" %accumulate side ##1
        _e = %ifEmpty "value" %accumulate side ##1

        {out}
        sideRan = "@$accumulator.side"
      ODIN
      result = run(text, { "seed" => 0 })
      expect(result.output["out"]).to eq({ "sideRan" => 0 })
    end
  end
end
