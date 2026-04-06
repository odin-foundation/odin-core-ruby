# frozen_string_literal: true

module Odin
  module Transform
    module Verbs
      module CollectionVerbs
        module_function

        def extract_items(v)
          return [] if v.nil? || v.null?
          return v.value if v.array?
          if v.string?
            begin
              parsed = Types::DynValue.extract_array(v.value)
              return parsed.value
            rescue
              return []
            end
          end
          []
        end

        def compare_dyn_values(a, b)
          av = NumericVerbs.to_double(a)
          bv = NumericVerbs.to_double(b)
          if av && bv
            av <=> bv
          else
            a.to_string <=> b.to_string
          end
        end

        def values_equal?(a, b)
          return true if a.nil? && b.nil?
          return false if a.nil? || b.nil?
          return true if a.null? && b.null?
          a.to_string == b.to_string
        end

        def register(registry)
          dv = Types::DynValue

          registry["filter"] = ->(args, _ctx) {
            arr_val = args[0]
            items = CollectionVerbs.extract_items(arr_val)
            return dv.of_array([]) if items.empty?

            if args.length >= 4
              # filter(array, fieldName, operator, compareValue)
              field = args[1]&.to_string || ""
              op = args[2]&.to_string || "="
              compare = args[3]

              filtered = items.select do |item|
                val = item.object? ? item.get(field) : item
                next false if val.nil? || val.null?

                case op
                when "=", "=="
                  val.to_string == compare.to_string
                when "!=", "<>"
                  val.to_string != compare.to_string
                when "<"
                  (NumericVerbs.to_double(val) || 0) < (NumericVerbs.to_double(compare) || 0)
                when "<="
                  (NumericVerbs.to_double(val) || 0) <= (NumericVerbs.to_double(compare) || 0)
                when ">"
                  (NumericVerbs.to_double(val) || 0) > (NumericVerbs.to_double(compare) || 0)
                when ">="
                  (NumericVerbs.to_double(val) || 0) >= (NumericVerbs.to_double(compare) || 0)
                when "contains"
                  val.to_string.include?(compare.to_string)
                when "startsWith"
                  val.to_string.start_with?(compare.to_string)
                when "endsWith"
                  val.to_string.end_with?(compare.to_string)
                else
                  val.truthy?
                end
              end
              dv.of_array(filtered)
            elsif args.length >= 2
              # filter(array, fieldName) — truthy on field
              field = args[1]&.to_string || ""
              filtered = items.select do |item|
                val = item.object? ? item.get(field) : item
                val&.truthy? || false
              end
              dv.of_array(filtered)
            else
              # filter(array) — truthy items only
              dv.of_array(items.select(&:truthy?))
            end
          }

          registry["flatten"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            result = []
            items.each do |item|
              if item.array?
                result.concat(item.value)
              else
                result << item
              end
            end
            dv.of_array(result)
          }

          registry["distinct"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            seen = {}
            result = items.select do |item|
              key = item.to_string
              if seen.key?(key)
                false
              else
                seen[key] = true
                true
              end
            end
            dv.of_array(result)
          }
          registry["unique"] = registry["distinct"]

          registry["sort"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            sorted = items.sort { |a, b| CollectionVerbs.compare_dyn_values(a, b) }
            dv.of_array(sorted)
          }

          registry["sortDesc"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            sorted = items.sort { |a, b| CollectionVerbs.compare_dyn_values(b, a) }
            dv.of_array(sorted)
          }

          registry["sortBy"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            field = args[1]&.to_string || ""
            sorted = items.sort do |a, b|
              av = a.object? ? a.get(field) : dv.of_null
              bv = b.object? ? b.get(field) : dv.of_null
              CollectionVerbs.compare_dyn_values(av || dv.of_null, bv || dv.of_null)
            end
            dv.of_array(sorted)
          }

          registry["map"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            field = args[1]&.to_string || ""
            result = items.map do |item|
              if item.object?
                item.get(field) || dv.of_null
              else
                item
              end
            end
            dv.of_array(result)
          }

          registry["pluck"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            field = args[1]&.to_string || ""
            result = items.map do |item|
              if item.object?
                item.get(field) || dv.of_null
              else
                dv.of_null
              end
            end
            dv.of_array(result)
          }

          registry["indexOf"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            search = args[1]
            idx = items.index { |item| CollectionVerbs.values_equal?(item, search) }
            dv.of_integer(idx || -1)
          }

          registry["at"] = ->(args, _ctx) {
            arr = args[0]
            return dv.of_null unless arr&.array?
            idx = NumericVerbs.to_double(args[1])&.to_i || 0
            items = arr.value
            idx = items.length + idx if idx < 0
            (idx >= 0 && idx < items.length) ? items[idx] : dv.of_null
          }

          registry["slice"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            start_idx = NumericVerbs.to_double(args[1])&.to_i || 0
            end_idx = args[2] ? (NumericVerbs.to_double(args[2])&.to_i || items.length) : items.length
            start_idx = items.length + start_idx if start_idx < 0
            end_idx = items.length + end_idx if end_idx < 0
            start_idx = [[start_idx, 0].max, items.length].min
            end_idx = [[end_idx, 0].max, items.length].min
            dv.of_array(start_idx < end_idx ? items[start_idx...end_idx] : [])
          }

          registry["reverse"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            dv.of_array(items.reverse)
          }

          registry["every"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            return dv.of_bool(true) if items.empty?
            if args.length >= 2
              field = args[1]&.to_string || ""
              dv.of_bool(items.all? { |item| (item.object? ? item.get(field) : item)&.truthy? || false })
            else
              dv.of_bool(items.all?(&:truthy?))
            end
          }

          registry["some"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            return dv.of_bool(false) if items.empty?
            if args.length >= 2
              field = args[1]&.to_string || ""
              dv.of_bool(items.any? { |item| (item.object? ? item.get(field) : item)&.truthy? || false })
            else
              dv.of_bool(items.any?(&:truthy?))
            end
          }

          registry["find"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            if args.length >= 2
              field = args[1]&.to_string || ""
              found = items.find { |item| (item.object? ? item.get(field) : item)&.truthy? || false }
            else
              found = items.find(&:truthy?)
            end
            found || dv.of_null
          }

          registry["findIndex"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            if args.length >= 2
              field = args[1]&.to_string || ""
              idx = items.index { |item| (item.object? ? item.get(field) : item)&.truthy? || false }
            else
              idx = items.index(&:truthy?)
            end
            dv.of_integer(idx || -1)
          }

          registry["includes"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            search = args[1]
            dv.of_bool(items.any? { |item| CollectionVerbs.values_equal?(item, search) })
          }

          registry["concatArrays"] = ->(args, _ctx) {
            result = []
            args.each do |a|
              if a&.array?
                result.concat(a.value)
              elsif !a.nil? && !a.null?
                result << a
              end
            end
            dv.of_array(result)
          }

          registry["zip"] = ->(args, _ctx) {
            arrays = args.map { |a| CollectionVerbs.extract_items(a) }
            return dv.of_array([]) if arrays.empty?
            max_len = arrays.map(&:length).max || 0
            result = (0...max_len).map do |i|
              pair = arrays.map { |arr| i < arr.length ? arr[i] : dv.of_null }
              dv.of_array(pair)
            end
            dv.of_array(result)
          }

          registry["groupBy"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            field = args[1]&.to_string || ""
            groups = {}
            items.each do |item|
              key = if item.object?
                       (item.get(field) || dv.of_null).to_string
                     else
                       item.to_string
                     end
              groups[key] ||= []
              groups[key] << item
            end
            obj = groups.transform_values { |v| dv.of_array(v) }
            dv.of_object(obj)
          }

          registry["partition"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            if args.length >= 2
              field = args[1]&.to_string || ""
              pass_items, fail_items = items.partition { |item| (item.object? ? item.get(field) : item)&.truthy? || false }
            else
              pass_items, fail_items = items.partition(&:truthy?)
            end
            dv.of_array([dv.of_array(pass_items), dv.of_array(fail_items)])
          }

          registry["take"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            n = NumericVerbs.to_double(args[1])&.to_i || 0
            dv.of_array(items.first([n, 0].max))
          }
          registry["limit"] = registry["take"]

          registry["drop"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            n = NumericVerbs.to_double(args[1])&.to_i || 0
            dv.of_array(items.drop([n, 0].max))
          }

          registry["chunk"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            size = NumericVerbs.to_double(args[1])&.to_i || 1
            size = 1 if size < 1
            chunks = items.each_slice(size).map { |c| dv.of_array(c) }
            dv.of_array(chunks)
          }

          registry["range"] = ->(args, _ctx) {
            if args.length == 1
              end_val = NumericVerbs.to_double(args[0])&.to_i || 0
              start_val = 0
              step = 1
            elsif args.length == 2
              start_val = NumericVerbs.to_double(args[0])&.to_i || 0
              end_val = NumericVerbs.to_double(args[1])&.to_i || 0
              step = start_val <= end_val ? 1 : -1
            else
              start_val = NumericVerbs.to_double(args[0])&.to_i || 0
              end_val = NumericVerbs.to_double(args[1])&.to_i || 0
              step = NumericVerbs.to_double(args[2])&.to_i || 1
              step = 1 if step == 0
            end

            result = []
            max_items = 10_000
            if step > 0
              i = start_val
              while i < end_val && result.length < max_items
                result << dv.of_integer(i)
                i += step
              end
            else
              i = start_val
              while i > end_val && result.length < max_items
                result << dv.of_integer(i)
                i += step
              end
            end
            dv.of_array(result)
          }

          registry["compact"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            dv.of_array(items.reject { |item| item.null? || (item.string? && item.value.empty?) })
          }

          registry["rowNumber"] = ->(args, ctx) {
            name = "_rowNumber"
            current = ctx.get_accumulator(name)
            if current.null?
              ctx.set_accumulator(name, dv.of_integer(1))
              dv.of_integer(1)
            else
              next_val = current.to_number.to_i + 1
              ctx.set_accumulator(name, dv.of_integer(next_val))
              dv.of_integer(next_val)
            end
          }

          registry["sample"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            count = NumericVerbs.to_double(args[1])&.to_i || 1
            seed_arg = args[2]
            if seed_arg
              # Deterministic sampling using Mulberry32 Fisher-Yates
              seed_val = if seed_arg.type == :string
                           NumericVerbs.string_to_seed(seed_arg.to_string)
                         else
                           (NumericVerbs.to_double(seed_arg)&.to_i || 0)
                         end
              rng = Mulberry32.new(seed_val)
              shuffled = items.dup
              (shuffled.length - 1).downto(1) do |i|
                j = rng.next_int(i + 1)
                shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
              end
              dv.of_array(shuffled.first([count, shuffled.length].min))
            else
              rng = Random.new
              shuffled = items.dup
              (shuffled.length - 1).downto(1) do |i|
                j = rng.rand(i + 1)
                shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
              end
              dv.of_array(shuffled.first([count, shuffled.length].min))
            end
          }

          registry["dedupe"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            field = args[1]&.to_string
            result = []
            last_key = nil
            items.each do |item|
              key = if field && item.object?
                       (item.get(field) || dv.of_null).to_string
                     else
                       item.to_string
                     end
              if key != last_key
                result << item
                last_key = key
              end
            end
            dv.of_array(result)
          }

          registry["cumsum"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            sum = 0.0
            result = items.map do |item|
              n = NumericVerbs.to_double(item)
              if n.nil?
                dv.of_null
              else
                sum += n
                NumericVerbs.numeric_result(sum)
              end
            end
            dv.of_array(result)
          }

          registry["cumprod"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            prod = 1.0
            result = items.map do |item|
              n = NumericVerbs.to_double(item)
              if n.nil?
                dv.of_null
              else
                prod *= n
                NumericVerbs.numeric_result(prod)
              end
            end
            dv.of_array(result)
          }

          registry["diff"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            lag = args[1] ? (NumericVerbs.to_double(args[1])&.to_i || 1) : 1
            result = items.each_with_index.map do |item, i|
              if i < lag
                dv.of_null
              else
                curr = NumericVerbs.to_double(item)
                prev = NumericVerbs.to_double(items[i - lag])
                if curr.nil? || prev.nil?
                  dv.of_null
                else
                  NumericVerbs.numeric_result(curr - prev)
                end
              end
            end
            dv.of_array(result)
          }

          registry["pctChange"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            lag = args[1] ? (NumericVerbs.to_double(args[1])&.to_i || 1) : 1
            result = items.each_with_index.map do |item, i|
              if i < lag
                dv.of_null
              else
                curr = NumericVerbs.to_double(item)
                prev = NumericVerbs.to_double(items[i - lag])
                if curr.nil? || prev.nil? || prev == 0.0
                  dv.of_null
                else
                  dv.of_float((curr - prev) / prev)
                end
              end
            end
            dv.of_array(result)
          }

          registry["shift"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            n = NumericVerbs.to_double(args[1])&.to_i || 0
            fill = args[2] || dv.of_null
            result = Array.new(items.length, fill)
            items.each_with_index do |item, i|
              new_idx = i + n
              result[new_idx] = item if new_idx >= 0 && new_idx < items.length
            end
            dv.of_array(result)
          }

          registry["lag"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            n = NumericVerbs.to_double(args[1])&.to_i || 1
            fill = args[2] || dv.of_null
            result = items.each_with_index.map do |_item, i|
              prev_idx = i - n
              prev_idx >= 0 ? items[prev_idx] : fill
            end
            dv.of_array(result)
          }

          registry["lead"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            n = NumericVerbs.to_double(args[1])&.to_i || 1
            fill = args[2] || dv.of_null
            result = items.each_with_index.map do |_item, i|
              next_idx = i + n
              next_idx < items.length ? items[next_idx] : fill
            end
            dv.of_array(result)
          }

          registry["rank"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            field = args[1]&.to_string
            direction = args[2]&.to_string || "desc"

            values = items.map do |item|
              if field && item.object?
                NumericVerbs.to_double(item.get(field))
              else
                NumericVerbs.to_double(item)
              end
            end

            sorted_unique = values.compact.uniq.sort
            sorted_unique.reverse! if direction == "desc"

            rank_map = {}
            sorted_unique.each_with_index { |v, i| rank_map[v] = i + 1 }

            result = values.map do |v|
              v.nil? ? dv.of_null : dv.of_integer(rank_map[v])
            end
            dv.of_array(result)
          }

          registry["fillMissing"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            strategy = args[1]&.to_string || "value"
            fill_val = args[2] || dv.of_null

            case strategy
            when "forward"
              last_val = dv.of_null
              result = items.map do |item|
                if item.null?
                  last_val
                else
                  last_val = item
                  item
                end
              end
            when "backward"
              last_val = dv.of_null
              result = items.reverse.map do |item|
                if item.null?
                  last_val
                else
                  last_val = item
                  item
                end
              end.reverse
            else
              result = items.map { |item| item.null? ? fill_val : item }
            end
            dv.of_array(result)
          }
          registry["reduce"] = ->(args, _ctx) {
            return dv.of_null if args.length < 3
            arr = args[0]
            return dv.of_null unless arr&.array?
            verb_name = args[1]&.to_string
            return dv.of_null if verb_name.nil?
            accumulator = args[2]
            verb_fn = registry[verb_name]
            return dv.of_null unless verb_fn
            arr.as_array.each do |item|
              accumulator = verb_fn.call([accumulator, item], _ctx)
            end
            accumulator
          }

          registry["pivot"] = ->(args, _ctx) {
            return dv.of_null if args.length < 3
            arr = args[0]
            return dv.of_null unless arr&.array?
            key_field = args[1]&.to_string
            value_field = args[2]&.to_string
            return dv.of_null if key_field.nil? || value_field.nil?
            result = {}
            arr.as_array.each do |item|
              next unless item.object?
              k = item.get(key_field)
              next if k.nil? || k.null?
              key_str = k.to_string
              v = item.get(value_field) || dv.of_null
              result[key_str] = v
            end
            dv.of_object(result)
          }

          registry["unpivot"] = ->(args, _ctx) {
            return dv.of_null if args.length < 3
            obj = args[0]
            return dv.of_null unless obj&.object?
            key_name = args[1]&.to_string
            value_name = args[2]&.to_string
            return dv.of_null if key_name.nil? || value_name.nil?
            result = []
            obj.as_object.each do |k, v|
              result << dv.of_object({
                key_name => dv.of_string(k.to_s),
                value_name => v
              })
            end
            dv.of_array(result)
          }
        end
      end
    end
  end
end
