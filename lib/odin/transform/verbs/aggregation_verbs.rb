# frozen_string_literal: true

module Odin
  module Transform
    module Verbs
      module AggregationVerbs
        module_function

        def register(registry)
          dv = Types::DynValue

          registry["sum"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            return dv.of_integer(0) if items.empty?
            all_int = true
            total = 0.0
            items.each do |item|
              n = NumericVerbs.to_double(item)
              next if n.nil?
              total += n
              all_int = false unless item.integer?
            end
            all_int ? dv.of_integer(total.to_i) : dv.of_float(total)
          }

          registry["count"] = ->(args, _ctx) {
            v = args[0]
            if v.nil? || v.null?
              dv.of_integer(0)
            elsif v.array?
              dv.of_integer(v.value.length)
            else
              dv.of_integer(1)
            end
          }

          registry["min"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            nums = items.filter_map { |item| NumericVerbs.to_double(item) }
            return dv.of_null if nums.empty?
            NumericVerbs.numeric_result(nums.min)
          }

          registry["max"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            nums = items.filter_map { |item| NumericVerbs.to_double(item) }
            return dv.of_null if nums.empty?
            NumericVerbs.numeric_result(nums.max)
          }

          registry["avg"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            nums = items.filter_map { |item| NumericVerbs.to_double(item) }
            return dv.of_null if nums.empty?
            dv.of_float(nums.sum / nums.length.to_f)
          }

          registry["first"] = ->(args, _ctx) {
            v = args[0]
            if v&.array? && !v.value.empty?
              v.value.first
            else
              dv.of_null
            end
          }

          registry["last"] = ->(args, _ctx) {
            v = args[0]
            if v&.array? && !v.value.empty?
              v.value.last
            else
              dv.of_null
            end
          }

          registry["accumulate"] = ->(args, ctx) {
            name = args[0]&.to_string || ""
            increment = args[1] || dv.of_integer(0)
            current = ctx.get_accumulator(name)
            if current.null?
              ctx.set_accumulator(name, increment)
              increment
            else
              if current.string? || increment.string?
                new_val = dv.of_string(current.to_string + increment.to_string)
              elsif current.integer? && increment.integer?
                new_val = dv.of_integer((current.to_number || 0) + (increment.to_number || 0))
              else
                new_val = dv.of_float((current.to_number || 0).to_f + (increment.to_number || 0).to_f)
              end
              ctx.set_accumulator(name, new_val)
              new_val
            end
          }

          registry["set"] = ->(args, ctx) {
            name = args[0]&.to_string || ""
            value = args[1] || dv.of_null
            ctx.set_accumulator(name, value)
            value
          }
        end
      end
    end
  end
end
