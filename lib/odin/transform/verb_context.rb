# frozen_string_literal: true

module Odin
  module Transform
    class VerbContext
      attr_accessor :source,          # DynValue — current source root
                    :current_item,    # DynValue — current item in _each loop
                    :loop_index,      # Integer — current loop iteration (0-based)
                    :loop_length,     # Integer — total loop length
                    :loop_vars,       # Hash<String, DynValue> — named loop variables
                    :accumulators,    # Hash<String, DynValue> — accumulator state
                    :tables,          # Hash<String, LookupTable> — lookup tables
                    :constants,       # Hash<String, DynValue> — constant values
                    :global_output,   # Hash — the output being built (for cross-segment refs)
                    :sequences,       # Hash<String, Integer> — sequence counters
                    :loop_depth,      # Integer — nesting depth for security
                    :field_modifiers, # Hash<String, Array<Symbol>> — tracked field modifiers
                    :errors,          # Array<TransformEngine::TransformError> — collected errors
                    :source_format    # String — source format for directive handling

      MAX_LOOP_DEPTH = 10

      def initialize
        @source = Types::DynValue.of_null
        @current_item = nil
        @loop_index = 0
        @loop_length = 0
        @loop_vars = {}
        @accumulators = {}
        @tables = {}
        @constants = {}
        @global_output = {}
        @sequences = {}
        @loop_depth = 0
        @field_modifiers = {}
        @errors = []
        @source_format = ""
      end

      def next_sequence(name)
        @sequences[name] ||= 0
        val = @sequences[name]
        @sequences[name] += 1
        val
      end

      def reset_sequence(name)
        @sequences[name] = 0
      end

      def get_accumulator(name)
        @accumulators[name] || Types::DynValue.of_null
      end

      def set_accumulator(name, value)
        @accumulators[name] = value
      end

      def get_constant(name)
        @constants[name] || Types::DynValue.of_null
      end

      def get_table(name)
        @tables[name]
      end

      def in_loop?
        !@current_item.nil?
      end

      def dup_for_loop
        ctx = VerbContext.new
        ctx.source = @source
        ctx.loop_vars = @loop_vars.dup
        ctx.accumulators = @accumulators # shared reference
        ctx.tables = @tables
        ctx.constants = @constants
        ctx.global_output = @global_output # shared reference
        ctx.sequences = @sequences # shared reference
        ctx.loop_depth = @loop_depth + 1
        ctx.field_modifiers = @field_modifiers # shared reference
        ctx.errors = @errors # shared reference
        ctx
      end
    end
  end
end
