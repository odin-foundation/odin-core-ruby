# frozen_string_literal: true

require "bigdecimal"

module Odin
  module Transform
    module Verbs
      # Mulberry32 PRNG — matches TypeScript/Rust implementations
      class Mulberry32
        def initialize(seed)
          @state = seed & 0xFFFFFFFF
        end

        def next_float
          @state = (@state + 0x6D2B79F5) & 0xFFFFFFFF
          t = @state
          t = ((t ^ (t >> 15)) * (t | 1)) & 0xFFFFFFFF
          t = (t ^ (t + (((t ^ (t >> 7)) * (t | 61)) & 0xFFFFFFFF))) & 0xFFFFFFFF
          t = (t ^ (t >> 14)) & 0xFFFFFFFF
          t / 4294967296.0
        end

        def next_int(range)
          (next_float * range).floor
        end
      end

      module NumericVerbs
        module_function

        def string_to_seed(s)
          h = 0
          s.each_byte { |b| h = ((h << 5) - h + b) & 0xFFFFFFFF }
          h
        end

        def away_from_zero_round(value, places)
          return value if places < 0
          # Use BigDecimal for precision to avoid floating-point issues like 1.005
          bd = BigDecimal(value.to_s)
          factor = BigDecimal("10") ** places
          scaled = bd * factor
          if value >= 0
            (scaled + BigDecimal("0.5")).floor.to_f / factor.to_f
          else
            (scaled - BigDecimal("0.5")).ceil.to_f / factor.to_f
          end
        end

        def to_double(v)
          return nil if v.nil? || v.null?
          case v.type
          when :integer then v.value.to_f
          when :float, :percent then v.value.to_f
          when :float_raw, :currency_raw then v.value.to_f
          when :currency then v.value.to_f
          when :string
            s = v.value.strip
            return nil if s.empty?
            Float(s) rescue nil
          when :bool then v.value ? 1.0 : 0.0
          else nil
          end
        end

        def numeric_result(val)
          if val == val.floor && val.abs < 2**53
            Types::DynValue.of_integer(val.to_i)
          else
            Types::DynValue.of_float(val)
          end
        end

        UNIT_FAMILIES = {
          "mass" => { "g" => 1.0, "kg" => 1000.0, "mg" => 0.001, "lb" => 453.592, "oz" => 28.3495, "ton" => 907185.0, "tonne" => 1000000.0 },
          "length" => { "m" => 1.0, "km" => 1000.0, "cm" => 0.01, "mm" => 0.001, "mi" => 1609.344, "yd" => 0.9144, "ft" => 0.3048, "in" => 0.0254 },
          "volume" => { "l" => 1.0, "ml" => 0.001, "gal" => 3.78541, "qt" => 0.946353, "pt" => 0.473176, "cup" => 0.236588, "floz" => 0.0295735 },
          "speed" => { "m/s" => 1.0, "km/h" => 0.277778, "mph" => 0.44704, "knot" => 0.514444, "ft/s" => 0.3048 },
          "area" => { "m2" => 1.0, "km2" => 1000000.0, "cm2" => 0.0001, "ha" => 10000.0, "acre" => 4046.86, "ft2" => 0.092903, "in2" => 0.00064516, "mi2" => 2589988.0 },
          "data" => { "B" => 1.0, "KB" => 1024.0, "MB" => 1048576.0, "GB" => 1073741824.0, "TB" => 1099511627776.0 },
          "time" => { "s" => 1.0, "ms" => 0.001, "min" => 60.0, "h" => 3600.0, "d" => 86400.0, "wk" => 604800.0 }
        }.freeze

        def find_unit_family(unit)
          UNIT_FAMILIES.each do |family_name, units|
            return [family_name, units[unit]] if units.key?(unit)
          end
          nil
        end

        def register(registry)
          dv = Types::DynValue

          registry["formatNumber"] = ->(args, _ctx) {
            raw = NumericVerbs.to_double(args[0])
            return dv.of_null if raw.nil?
            places = NumericVerbs.to_double(args[1])&.to_i || 0
            rounded = NumericVerbs.away_from_zero_round(raw, places)
            dv.of_string(format("%.#{places}f", rounded))
          }

          registry["formatInteger"] = ->(args, _ctx) {
            raw = NumericVerbs.to_double(args[0])
            return dv.of_null if raw.nil?
            rounded = NumericVerbs.away_from_zero_round(raw, 0).to_i
            dv.of_string(rounded.to_s)
          }

          registry["formatCurrency"] = ->(args, _ctx) {
            raw = NumericVerbs.to_double(args[0])
            return dv.of_null if raw.nil?
            rounded = NumericVerbs.away_from_zero_round(raw, 2)
            dv.of_string(format("%.2f", rounded))
          }

          registry["formatPercent"] = ->(args, _ctx) {
            raw = NumericVerbs.to_double(args[0])
            return dv.of_null if raw.nil?
            places = NumericVerbs.to_double(args[1])&.to_i || 0
            pct = raw * 100.0
            rounded = NumericVerbs.away_from_zero_round(pct, places)
            dv.of_string("#{format("%.#{places}f", rounded)}%")
          }

          registry["add"] = ->(args, _ctx) {
            a, b = args
            av = NumericVerbs.to_double(a)
            bv = NumericVerbs.to_double(b)
            return dv.of_null if av.nil? || bv.nil?
            result = av + bv
            NumericVerbs.numeric_result(result)
          }

          registry["subtract"] = ->(args, _ctx) {
            a, b = args
            av = NumericVerbs.to_double(a)
            bv = NumericVerbs.to_double(b)
            return dv.of_null if av.nil? || bv.nil?
            result = av - bv
            NumericVerbs.numeric_result(result)
          }

          registry["multiply"] = ->(args, _ctx) {
            a, b = args
            av = NumericVerbs.to_double(a)
            bv = NumericVerbs.to_double(b)
            return dv.of_null if av.nil? || bv.nil?
            result = av * bv
            NumericVerbs.numeric_result(result)
          }

          registry["divide"] = ->(args, _ctx) {
            a, b = args
            av = NumericVerbs.to_double(a)
            bv = NumericVerbs.to_double(b)
            return dv.of_null if av.nil? || bv.nil? || bv == 0.0
            dv.of_float(av / bv)
          }

          registry["mod"] = ->(args, _ctx) {
            a, b = args
            av = NumericVerbs.to_double(a)
            bv = NumericVerbs.to_double(b)
            return dv.of_null if av.nil? || bv.nil? || bv == 0.0
            result = av.to_i % bv.to_i
            dv.of_integer(result)
          }

          registry["abs"] = ->(args, _ctx) {
            v = args[0]
            n = NumericVerbs.to_double(v)
            return dv.of_null if n.nil?
            v.integer? ? dv.of_integer(n.abs.to_i) : dv.of_float(n.abs)
          }

          registry["floor"] = ->(args, _ctx) {
            n = NumericVerbs.to_double(args[0])
            return dv.of_null if n.nil?
            dv.of_integer(n.floor)
          }

          registry["ceil"] = ->(args, _ctx) {
            n = NumericVerbs.to_double(args[0])
            return dv.of_null if n.nil?
            dv.of_integer(n.ceil)
          }

          registry["round"] = ->(args, _ctx) {
            n = NumericVerbs.to_double(args[0])
            return dv.of_null if n.nil?
            places = NumericVerbs.to_double(args[1])&.to_i || 0
            rounded = NumericVerbs.away_from_zero_round(n, places)
            if rounded == rounded.to_i
              dv.of_integer(rounded.to_i)
            else
              dv.of_float(rounded)
            end
          }

          registry["negate"] = ->(args, _ctx) {
            v = args[0]
            n = NumericVerbs.to_double(v)
            return dv.of_null if n.nil?
            v.integer? ? dv.of_integer(-n.to_i) : dv.of_float(-n)
          }

          registry["sign"] = ->(args, _ctx) {
            n = NumericVerbs.to_double(args[0])
            return dv.of_null if n.nil?
            dv.of_integer(n > 0 ? 1 : (n < 0 ? -1 : 0))
          }

          registry["trunc"] = ->(args, _ctx) {
            n = NumericVerbs.to_double(args[0])
            return dv.of_null if n.nil?
            dv.of_integer(n.truncate)
          }

          registry["random"] = ->(args, _ctx) {
            if args.length == 1 && args[0]&.type == :string
              # Seeded float mode: random("seed") -> deterministic [0,1)
              seed = NumericVerbs.string_to_seed(args[0].to_string)
              rng = Mulberry32.new(seed)
              dv.of_float(rng.next_float)
            elsif args.length == 3 && args[2]&.type == :string
              # Seeded integer range: random(min, max, "seed") -> deterministic int in [min,max]
              min_v = (NumericVerbs.to_double(args[0]) || 0.0).to_i
              max_v = (NumericVerbs.to_double(args[1]) || 1.0).to_i
              seed = NumericVerbs.string_to_seed(args[2].to_string)
              rng = Mulberry32.new(seed)
              dv.of_integer(min_v + rng.next_int(max_v - min_v + 1))
            elsif args.length >= 2
              min_v = NumericVerbs.to_double(args[0]) || 0.0
              max_v = NumericVerbs.to_double(args[1]) || 1.0
              places = NumericVerbs.to_double(args[2])&.to_i || 2
              val = min_v + rand * (max_v - min_v)
              factor = 10.0**places
              val = (val * factor).round / factor
              dv.of_float(val)
            else
              dv.of_float(rand)
            end
          }

          registry["minOf"] = ->(args, _ctx) {
            # Flatten any array args
            items = []
            args.each do |a|
              if a&.array?
                a.value.each { |item| items << item }
              else
                items << a
              end
            end
            nums = items.filter_map { |a| NumericVerbs.to_double(a) }
            return dv.of_null if nums.empty?
            result = nums.min
            NumericVerbs.numeric_result(result)
          }

          registry["maxOf"] = ->(args, _ctx) {
            items = []
            args.each do |a|
              if a&.array?
                a.value.each { |item| items << item }
              else
                items << a
              end
            end
            nums = items.filter_map { |a| NumericVerbs.to_double(a) }
            return dv.of_null if nums.empty?
            result = nums.max
            NumericVerbs.numeric_result(result)
          }

          registry["parseInt"] = ->(args, _ctx) {
            s = args[0]&.to_string || ""
            radix = NumericVerbs.to_double(args[1])&.to_i || 10
            begin
              dv.of_integer(s.to_i(radix))
            rescue ArgumentError
              dv.of_null
            end
          }

          registry["safeDivide"] = ->(args, _ctx) {
            a, b, default_val = args
            av = NumericVerbs.to_double(a)
            bv = NumericVerbs.to_double(b)
            if bv.nil? || bv == 0.0
              default_val || dv.of_null
            else
              av ||= 0.0
              dv.of_float(av / bv)
            end
          }

          registry["formatLocaleNumber"] = ->(args, _ctx) {
            raw = NumericVerbs.to_double(args[0])
            return dv.of_null if raw.nil?
            places = NumericVerbs.to_double(args[1])&.to_i || 2
            rounded = NumericVerbs.away_from_zero_round(raw, places)
            formatted = format("%.#{places}f", rounded)
            # Add comma thousands separator
            int_part, dec_part = formatted.split(".")
            int_part = int_part.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1,')
            result = dec_part ? "#{int_part}.#{dec_part}" : int_part
            dv.of_string(result)
          }

          registry["log"] = ->(args, _ctx) {
            v = NumericVerbs.to_double(args[0])
            base = NumericVerbs.to_double(args[1])
            return dv.of_null if v.nil? || base.nil? || v <= 0 || base <= 0 || base == 1
            result = Math.log(v) / Math.log(base)
            return dv.of_null if result.nan? || result.infinite?
            NumericVerbs.numeric_result(result)
          }

          registry["ln"] = ->(args, _ctx) {
            v = NumericVerbs.to_double(args[0])
            return dv.of_null if v.nil? || v <= 0
            result = Math.log(v)
            return dv.of_null if result.nan? || result.infinite?
            dv.of_float(result)
          }

          registry["log10"] = ->(args, _ctx) {
            v = NumericVerbs.to_double(args[0])
            return dv.of_null if v.nil? || v <= 0
            result = Math.log10(v)
            return dv.of_null if result.nan? || result.infinite?
            NumericVerbs.numeric_result(result)
          }

          registry["exp"] = ->(args, _ctx) {
            v = NumericVerbs.to_double(args[0])
            return dv.of_null if v.nil?
            result = Math.exp(v)
            return dv.of_null if result.nan? || result.infinite?
            dv.of_float(result)
          }

          registry["pow"] = ->(args, _ctx) {
            base = NumericVerbs.to_double(args[0])
            exp = NumericVerbs.to_double(args[1])
            return dv.of_null if base.nil? || exp.nil?
            result = base**exp
            return dv.of_null if result.nan? || result.infinite?
            NumericVerbs.numeric_result(result)
          }

          registry["sqrt"] = ->(args, _ctx) {
            v = NumericVerbs.to_double(args[0])
            return dv.of_null if v.nil? || v < 0
            result = Math.sqrt(v)
            return dv.of_null if result.nan? || result.infinite?
            NumericVerbs.numeric_result(result)
          }

          registry["clamp"] = ->(args, _ctx) {
            v = NumericVerbs.to_double(args[0])
            min_v = NumericVerbs.to_double(args[1])
            max_v = NumericVerbs.to_double(args[2])
            return dv.of_null if v.nil? || min_v.nil? || max_v.nil?
            result = [[v, min_v].max, max_v].min
            NumericVerbs.numeric_result(result)
          }

          registry["isFinite"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_bool(false) if v.nil? || v.null?
            n = NumericVerbs.to_double(v)
            dv.of_bool(!n.nil? && !n.nan? && !n.infinite?)
          }

          registry["isNaN"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_bool(true) if v.nil? || v.null?
            n = NumericVerbs.to_double(v)
            dv.of_bool(n.nil? || n.nan?)
          }

          registry["convertUnit"] = ->(args, _ctx) {
            return dv.of_null if args.length < 3
            value = NumericVerbs.to_double(args[0])
            return dv.of_null if value.nil?
            from_unit = args[1]&.to_string
            to_unit = args[2]&.to_string
            return dv.of_null if from_unit.nil? || to_unit.nil?

            temp_units = %w[C F K]
            if temp_units.include?(from_unit) && temp_units.include?(to_unit)
              # Convert to Celsius first
              celsius = case from_unit
                        when "F" then (value - 32) * 5.0 / 9.0
                        when "K" then value - 273.15
                        else value
                        end
              result = case to_unit
                       when "F" then celsius * 9.0 / 5.0 + 32
                       when "K" then celsius + 273.15
                       else celsius
                       end
              result = (result * 1_000_000).round / 1_000_000.0
              next NumericVerbs.numeric_result(result)
            end

            # One is temp, other is not → incompatible
            if temp_units.include?(from_unit) || temp_units.include?(to_unit)
              next dv.of_null
            end

            from_info = NumericVerbs.find_unit_family(from_unit)
            to_info = NumericVerbs.find_unit_family(to_unit)
            if from_info.nil? || to_info.nil?
              next dv.of_null
            end

            from_family, from_factor = from_info
            to_family, to_factor = to_info
            if from_family != to_family
              next dv.of_null
            end

            result = value * from_factor / to_factor
            result = (result * 1_000_000).round / 1_000_000.0
            NumericVerbs.numeric_result(result)
          }
        end
      end
    end
  end
end
