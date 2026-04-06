# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Odin::Transform::VerbContext do
  subject(:ctx) { described_class.new }

  describe "default initialization" do
    it "source is DynValue null" do
      expect(ctx.source).to eq(Odin::Types::DynValue.of_null)
    end

    it "current_item is nil" do
      expect(ctx.current_item).to be_nil
    end

    it "loop_index is 0" do
      expect(ctx.loop_index).to eq(0)
    end

    it "loop_length is 0" do
      expect(ctx.loop_length).to eq(0)
    end

    it "loop_vars is empty hash" do
      expect(ctx.loop_vars).to eq({})
      expect(ctx.loop_vars).to be_a(Hash)
    end

    it "accumulators is empty hash" do
      expect(ctx.accumulators).to eq({})
      expect(ctx.accumulators).to be_a(Hash)
    end

    it "tables is empty hash" do
      expect(ctx.tables).to eq({})
      expect(ctx.tables).to be_a(Hash)
    end

    it "constants is empty hash" do
      expect(ctx.constants).to eq({})
      expect(ctx.constants).to be_a(Hash)
    end

    it "global_output is empty hash" do
      expect(ctx.global_output).to eq({})
      expect(ctx.global_output).to be_a(Hash)
    end

    it "sequences is empty hash" do
      expect(ctx.sequences).to eq({})
      expect(ctx.sequences).to be_a(Hash)
    end

    it "loop_depth is 0" do
      expect(ctx.loop_depth).to eq(0)
    end

    it "field_modifiers is empty hash" do
      expect(ctx.field_modifiers).to eq({})
      expect(ctx.field_modifiers).to be_a(Hash)
    end

    it "no collection fields are nil" do
      # This is the critical test — all collections must be initialized
      expect(ctx.loop_vars).not_to be_nil
      expect(ctx.accumulators).not_to be_nil
      expect(ctx.tables).not_to be_nil
      expect(ctx.constants).not_to be_nil
      expect(ctx.global_output).not_to be_nil
      expect(ctx.sequences).not_to be_nil
      expect(ctx.field_modifiers).not_to be_nil
    end
  end

  describe "#next_sequence" do
    it "returns 0 for first call" do
      expect(ctx.next_sequence("counter")).to eq(0)
    end

    it "increments on subsequent calls" do
      ctx.next_sequence("counter")
      expect(ctx.next_sequence("counter")).to eq(1)
      expect(ctx.next_sequence("counter")).to eq(2)
    end

    it "tracks independent sequences" do
      ctx.next_sequence("a")
      ctx.next_sequence("b")
      expect(ctx.next_sequence("a")).to eq(1)
      expect(ctx.next_sequence("b")).to eq(1)
    end
  end

  describe "#reset_sequence" do
    it "resets a sequence to 0" do
      3.times { ctx.next_sequence("counter") }
      ctx.reset_sequence("counter")
      expect(ctx.next_sequence("counter")).to eq(0)
    end
  end

  describe "accumulator operations" do
    it "returns null for unset accumulator" do
      expect(ctx.get_accumulator("missing")).to eq(Odin::Types::DynValue.of_null)
    end

    it "sets and gets accumulator" do
      val = Odin::Types::DynValue.of_integer(42)
      ctx.set_accumulator("count", val)
      expect(ctx.get_accumulator("count")).to eq(val)
    end

    it "overwrites accumulator" do
      ctx.set_accumulator("count", Odin::Types::DynValue.of_integer(1))
      ctx.set_accumulator("count", Odin::Types::DynValue.of_integer(2))
      expect(ctx.get_accumulator("count")).to eq(Odin::Types::DynValue.of_integer(2))
    end
  end

  describe "#get_constant" do
    it "returns null for unset constant" do
      expect(ctx.get_constant("missing")).to eq(Odin::Types::DynValue.of_null)
    end

    it "returns constant value" do
      ctx.constants["pi"] = Odin::Types::DynValue.of_float(3.14)
      expect(ctx.get_constant("pi")).to eq(Odin::Types::DynValue.of_float(3.14))
    end
  end

  describe "#in_loop?" do
    it "returns false when not in loop" do
      expect(ctx.in_loop?).to be false
    end

    it "returns true when current_item is set" do
      ctx.current_item = Odin::Types::DynValue.of_string("item")
      expect(ctx.in_loop?).to be true
    end
  end

  describe "#dup_for_loop" do
    it "creates new context with incremented loop_depth" do
      inner = ctx.dup_for_loop
      expect(inner.loop_depth).to eq(1)
    end

    it "shares accumulators with parent" do
      ctx.set_accumulator("x", Odin::Types::DynValue.of_integer(1))
      inner = ctx.dup_for_loop
      inner.set_accumulator("x", Odin::Types::DynValue.of_integer(2))
      expect(ctx.get_accumulator("x")).to eq(Odin::Types::DynValue.of_integer(2))
    end

    it "shares global_output with parent" do
      inner = ctx.dup_for_loop
      inner.global_output["key"] = "value"
      expect(ctx.global_output["key"]).to eq("value")
    end

    it "has independent loop_vars" do
      inner = ctx.dup_for_loop
      inner.loop_vars["x"] = Odin::Types::DynValue.of_integer(1)
      expect(ctx.loop_vars).not_to have_key("x")
    end

    it "preserves source" do
      ctx.source = Odin::Types::DynValue.of_string("root")
      inner = ctx.dup_for_loop
      expect(inner.source).to eq(Odin::Types::DynValue.of_string("root"))
    end
  end
end
