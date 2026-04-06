# frozen_string_literal: true

require "date"
require "time"

module Odin
  module Transform
    module Verbs
      module DateTimeVerbs
        module_function

        def parse_date(s)
          return nil if s.nil?
          s = s.to_string if s.is_a?(Types::DynValue)
          s = s.to_s.strip
          return nil if s.empty?
          begin
            Date.parse(s)
          rescue ArgumentError, TypeError
            nil
          end
        end

        def parse_timestamp(s)
          return nil if s.nil?
          s = s.to_string if s.is_a?(Types::DynValue)
          s = s.to_s.strip
          return nil if s.empty?
          begin
            Time.parse(s).utc
          rescue ArgumentError, TypeError
            nil
          end
        end

        def format_date_str(d)
          d.strftime("%Y-%m-%d")
        end

        def format_timestamp_str(t)
          t.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ")
        end

        def parse_date_with_pattern(value, pattern)
          parts = {}

          find_pos = ->(pat) { pattern.index(pat) }

          yyyy = find_pos.call("YYYY")
          yy = find_pos.call("YY")
          mm = find_pos.call("MM")
          dd = find_pos.call("DD")

          if yyyy && yyyy >= 0
            parts[:year] = value[yyyy, 4]&.to_i
          elsif yy && yy >= 0
            parts[:year] = 2000 + (value[yy, 2]&.to_i || 0)
          end

          parts[:month] = value[mm, 2]&.to_i if mm && mm >= 0
          parts[:day] = value[dd, 2]&.to_i if dd && dd >= 0

          return nil unless parts[:year]

          begin
            Date.new(parts[:year], parts[:month] || 1, parts[:day] || 1)
          rescue ArgumentError
            nil
          end
        end

        def apply_date_pattern(dt, pattern)
          result = pattern.dup
          if dt.is_a?(Date) && !dt.is_a?(Time)
            t = Time.new(dt.year, dt.month, dt.day, 0, 0, 0, "+00:00").utc
          else
            t = dt.is_a?(Time) ? dt : Time.parse(dt.to_s).utc
          end
          d = t.to_date

          # Support both uppercase (YYYY, DD) and lowercase (yyyy, dd) patterns
          result.gsub!("YYYY", format("%04d", d.year))
          result.gsub!("yyyy", format("%04d", d.year))
          result.gsub!("YY", format("%02d", d.year % 100))
          result.gsub!("yy", format("%02d", d.year % 100))
          result.gsub!("MMMM", d.strftime("%B"))
          result.gsub!("MMM", d.strftime("%b"))
          result.gsub!("MM", format("%02d", d.month))
          result.gsub!("DD", format("%02d", d.day))
          result.gsub!("dd", format("%02d", d.day))
          result.gsub!("EEEE", d.strftime("%A"))
          result.gsub!("EEE", d.strftime("%a"))
          result.gsub!("HH", format("%02d", t.hour))
          result.gsub!("hh", format("%02d", t.hour % 12 == 0 ? 12 : t.hour % 12))
          result.gsub!("mm", format("%02d", t.min))
          result.gsub!("ss", format("%02d", t.sec))
          result.gsub!("SSS", format("%03d", (t.usec / 1000.0).round))
          result.gsub!("A", t.hour < 12 ? "AM" : "PM")
          result
        end

        def duration_part(n, unit)
          int_val = n.to_i
          if (n - int_val).abs < 1e-9
            int_val == 1 ? "1 #{unit}" : "#{int_val} #{unit}s"
          else
            n == 1.0 ? "1 #{unit}" : "#{n} #{unit}s"
          end
        end

        def register(registry)
          dv = Types::DynValue

          registry["today"] = ->(_args, _ctx) {
            dv.of_date(Time.now.utc.strftime("%Y-%m-%d"))
          }

          registry["now"] = ->(_args, _ctx) {
            dv.of_timestamp(Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ"))
          }

          registry["formatDate"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            pattern = args[1]&.to_string || "yyyy-MM-dd"
            dt = DateTimeVerbs.parse_date(v)
            return dv.of_null unless dt
            dv.of_string(DateTimeVerbs.apply_date_pattern(dt, pattern))
          }

          registry["parseDate"] = ->(args, _ctx) {
            s = args[0]&.to_string
            return dv.of_null if s.nil? || s.empty?

            if args[1] && !args[1].null?
              # Pattern-based parsing
              pattern = args[1].to_string
              dt = DateTimeVerbs.parse_date_with_pattern(s, pattern)
              return dv.of_null unless dt
              dv.of_string(DateTimeVerbs.format_date_str(dt))
            else
              dt = DateTimeVerbs.parse_date(s)
              return dv.of_null unless dt
              dv.of_string(DateTimeVerbs.format_date_str(dt))
            end
          }

          registry["formatTime"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            pattern = args[1]&.to_string || "HH:mm:ss"
            t = DateTimeVerbs.parse_timestamp(v)
            return dv.of_null unless t
            dv.of_string(DateTimeVerbs.apply_date_pattern(t, pattern))
          }

          registry["formatTimestamp"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            pattern = args[1]&.to_string
            t = DateTimeVerbs.parse_timestamp(v)
            return dv.of_null unless t
            if pattern
              dv.of_string(DateTimeVerbs.apply_date_pattern(t, pattern))
            else
              dv.of_string(DateTimeVerbs.format_timestamp_str(t))
            end
          }

          registry["parseTimestamp"] = ->(args, _ctx) {
            s = args[0]&.to_string
            return dv.of_null if s.nil? || s.empty?
            t = DateTimeVerbs.parse_timestamp(s)
            return dv.of_null unless t
            dv.of_timestamp(DateTimeVerbs.format_timestamp_str(t))
          }

          registry["addDays"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            n = NumericVerbs.to_double(args[1])&.to_i || 0
            if v.timestamp?
              t = DateTimeVerbs.parse_timestamp(v)
              return dv.of_null unless t
              t += n * 86400
              dv.of_string(DateTimeVerbs.format_timestamp_str(t))
            else
              d = DateTimeVerbs.parse_date(v)
              return dv.of_null unless d
              dv.of_string(DateTimeVerbs.format_date_str(d + n))
            end
          }

          registry["addMonths"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            n = NumericVerbs.to_double(args[1])&.to_i || 0
            if v.timestamp?
              t = DateTimeVerbs.parse_timestamp(v)
              return dv.of_null unless t
              d = t.to_date
              new_d = d >> n
              # Clamp day
              max_day = Date.new(new_d.year, new_d.month, -1).day
              day = [d.day, max_day].min
              new_d = Date.new(new_d.year, new_d.month, day)
              new_t = Time.utc(new_d.year, new_d.month, new_d.day, t.hour, t.min, t.sec)
              dv.of_timestamp(DateTimeVerbs.format_timestamp_str(new_t))
            else
              d = DateTimeVerbs.parse_date(v)
              return dv.of_null unless d
              new_d = d >> n
              max_day = Date.new(new_d.year, new_d.month, -1).day
              day = [d.day, max_day].min
              new_d = Date.new(new_d.year, new_d.month, day)
              dv.of_string(DateTimeVerbs.format_date_str(new_d))
            end
          }

          registry["addYears"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            n = NumericVerbs.to_double(args[1])&.to_i || 0
            if v.timestamp?
              t = DateTimeVerbs.parse_timestamp(v)
              return dv.of_null unless t
              d = t.to_date
              new_year = d.year + n
              max_day = Date.new(new_year, d.month, -1).day
              day = [d.day, max_day].min
              new_d = Date.new(new_year, d.month, day)
              new_t = Time.utc(new_d.year, new_d.month, new_d.day, t.hour, t.min, t.sec)
              dv.of_string(DateTimeVerbs.format_timestamp_str(new_t))
            else
              d = DateTimeVerbs.parse_date(v)
              return dv.of_null unless d
              new_year = d.year + n
              max_day = Date.new(new_year, d.month, -1).day
              day = [d.day, max_day].min
              new_d = Date.new(new_year, d.month, day)
              dv.of_string(DateTimeVerbs.format_date_str(new_d))
            end
          }

          registry["dateDiff"] = ->(args, ctx) {
            v1 = args[0]
            v2 = args[1]
            unit = args[2]&.to_string || "days"
            return dv.of_null if v1.nil? || v1.null? || v2.nil? || v2.null?

            case unit
            when "days"
              d1 = DateTimeVerbs.parse_date(v1)
              d2 = DateTimeVerbs.parse_date(v2)
              return dv.of_null unless d1 && d2
              dv.of_integer((d2 - d1).to_i)
            when "months"
              d1 = DateTimeVerbs.parse_date(v1)
              d2 = DateTimeVerbs.parse_date(v2)
              return dv.of_null unless d1 && d2
              months = (d2.year - d1.year) * 12 + (d2.month - d1.month)
              months -= 1 if d2.day < d1.day
              dv.of_integer(months)
            when "years"
              d1 = DateTimeVerbs.parse_date(v1)
              d2 = DateTimeVerbs.parse_date(v2)
              return dv.of_null unless d1 && d2
              years = d2.year - d1.year
              years -= 1 if d2.month < d1.month || (d2.month == d1.month && d2.day < d1.day)
              dv.of_integer(years)
            when "hours"
              t1 = DateTimeVerbs.parse_timestamp(v1)
              t2 = DateTimeVerbs.parse_timestamp(v2)
              return dv.of_null unless t1 && t2
              dv.of_float((t2 - t1) / 3600.0)
            when "minutes"
              t1 = DateTimeVerbs.parse_timestamp(v1)
              t2 = DateTimeVerbs.parse_timestamp(v2)
              return dv.of_null unless t1 && t2
              dv.of_float((t2 - t1) / 60.0)
            when "seconds"
              t1 = DateTimeVerbs.parse_timestamp(v1)
              t2 = DateTimeVerbs.parse_timestamp(v2)
              return dv.of_null unless t1 && t2
              dv.of_float(t2 - t1)
            else
              ctx.errors << TransformEngine.incompatible_conversion_error(
                "dateDiff", "unknown unit '#{unit}' (expected 'days', 'months', or 'years')"
              )
              dv.of_null
            end
          }

          registry["addHours"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            n = NumericVerbs.to_double(args[1]) || 0
            t = DateTimeVerbs.parse_timestamp(v)
            return dv.of_null unless t
            t += (n * 3600).to_i
            dv.of_timestamp(DateTimeVerbs.format_timestamp_str(t))
          }

          registry["addMinutes"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            n = NumericVerbs.to_double(args[1]) || 0
            t = DateTimeVerbs.parse_timestamp(v)
            return dv.of_null unless t
            t += (n * 60).to_i
            dv.of_timestamp(DateTimeVerbs.format_timestamp_str(t))
          }

          registry["addSeconds"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            n = NumericVerbs.to_double(args[1]) || 0
            t = DateTimeVerbs.parse_timestamp(v)
            return dv.of_null unless t
            t += n.to_i
            dv.of_timestamp(DateTimeVerbs.format_timestamp_str(t))
          }

          registry["startOfDay"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            d = DateTimeVerbs.parse_date(v)
            return dv.of_null unless d
            dv.of_timestamp("#{DateTimeVerbs.format_date_str(d)}T00:00:00.000Z")
          }

          registry["endOfDay"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            d = DateTimeVerbs.parse_date(v)
            return dv.of_null unless d
            dv.of_timestamp("#{DateTimeVerbs.format_date_str(d)}T23:59:59.999Z")
          }

          registry["startOfMonth"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            d = DateTimeVerbs.parse_date(v)
            return dv.of_null unless d
            dv.of_date(DateTimeVerbs.format_date_str(Date.new(d.year, d.month, 1)))
          }

          registry["endOfMonth"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            d = DateTimeVerbs.parse_date(v)
            return dv.of_null unless d
            last = Date.new(d.year, d.month, -1)
            dv.of_date(DateTimeVerbs.format_date_str(last))
          }

          registry["startOfYear"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            d = DateTimeVerbs.parse_date(v)
            return dv.of_null unless d
            dv.of_date(DateTimeVerbs.format_date_str(Date.new(d.year, 1, 1)))
          }

          registry["endOfYear"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            d = DateTimeVerbs.parse_date(v)
            return dv.of_null unless d
            dv.of_date(DateTimeVerbs.format_date_str(Date.new(d.year, 12, 31)))
          }

          registry["dayOfWeek"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            d = DateTimeVerbs.parse_date(v)
            return dv.of_null unless d
            # ISO 8601: 1=Monday, 7=Sunday
            dow = d.cwday
            dv.of_integer(dow)
          }

          registry["dayOfMonth"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            d = DateTimeVerbs.parse_date(v)
            return dv.of_null unless d
            dv.of_integer(d.day)
          }

          registry["dayOfYear"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            d = DateTimeVerbs.parse_date(v)
            return dv.of_null unless d
            dv.of_integer(d.yday)
          }

          registry["weekOfYear"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            d = DateTimeVerbs.parse_date(v)
            return dv.of_null unless d
            # ISO 8601 week number (cweek handles week 53 correctly)
            dv.of_integer(d.cweek)
          }

          registry["quarter"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            d = DateTimeVerbs.parse_date(v)
            return dv.of_null unless d
            dv.of_integer((d.month - 1) / 3 + 1)
          }

          registry["isLeapYear"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            year = if v.integer?
                     v.value
                   else
                     d = DateTimeVerbs.parse_date(v)
                     return dv.of_null unless d
                     d.year
                   end
            dv.of_bool(Date.leap?(year))
          }

          registry["isBefore"] = ->(args, _ctx) {
            v1, v2 = args
            return dv.of_null if v1.nil? || v1.null? || v2.nil? || v2.null?
            s1 = v1.to_string
            s2 = v2.to_string
            dv.of_bool(s1 < s2)
          }

          registry["isAfter"] = ->(args, _ctx) {
            v1, v2 = args
            return dv.of_null if v1.nil? || v1.null? || v2.nil? || v2.null?
            s1 = v1.to_string
            s2 = v2.to_string
            dv.of_bool(s1 > s2)
          }

          registry["isBetween"] = ->(args, _ctx) {
            v, v1, v2 = args
            return dv.of_null if v.nil? || v.null? || v1.nil? || v1.null? || v2.nil? || v2.null?
            s = v.to_string
            s1 = v1.to_string
            s2 = v2.to_string
            dv.of_bool(s >= s1 && s <= s2)
          }

          registry["toUnix"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            t = DateTimeVerbs.parse_timestamp(v)
            if t.nil?
              d = DateTimeVerbs.parse_date(v)
              return dv.of_null unless d
              t = Time.utc(d.year, d.month, d.day)
            end
            dv.of_integer(t.to_i)
          }

          registry["fromUnix"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            epoch = NumericVerbs.to_double(v)
            return dv.of_null if epoch.nil?
            t = Time.at(epoch.to_i).utc
            dv.of_timestamp(DateTimeVerbs.format_timestamp_str(t))
          }

          registry["daysBetweenDates"] = ->(args, _ctx) {
            v1, v2 = args
            return dv.of_null if v1.nil? || v1.null? || v2.nil? || v2.null?
            d1 = DateTimeVerbs.parse_date(v1)
            d2 = DateTimeVerbs.parse_date(v2)
            return dv.of_null unless d1 && d2
            dv.of_integer((d2 - d1).to_i.abs)
          }

          registry["ageFromDate"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            birth = DateTimeVerbs.parse_date(v)
            return dv.of_null unless birth
            ref = if args[1] && !args[1].null?
                     DateTimeVerbs.parse_date(args[1]) || Date.today
                   else
                     Date.today
                   end
            age = ref.year - birth.year
            age -= 1 if ref.month < birth.month || (ref.month == birth.month && ref.day < birth.day)
            dv.of_integer(age)
          }

          registry["isValidDate"] = ->(args, _ctx) {
            s = args[0]&.to_string
            return dv.of_bool(false) if s.nil? || s.empty?
            d = DateTimeVerbs.parse_date(s)
            dv.of_bool(!d.nil?)
          }

          registry["formatLocaleDate"] = ->(args, _ctx) {
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            locale = args[1]&.to_string || "en"
            fmt = args[2]&.to_string
            d = DateTimeVerbs.parse_date(v)
            return dv.of_null unless d

            if fmt
              dv.of_string(DateTimeVerbs.apply_date_pattern(d, fmt))
            else
              dv.of_string(DateTimeVerbs.format_date_str(d))
            end
          }

          registry["businessDays"] = ->(args, _ctx) {
            return dv.of_null if args.length < 2
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            d = DateTimeVerbs.parse_date(v)
            return dv.of_null unless d
            count = NumericVerbs.to_double(args[1])&.to_i
            return dv.of_null if count.nil?
            direction = count >= 0 ? 1 : -1
            abs_count = count.abs
            full_weeks = abs_count / 5
            remaining = abs_count % 5
            current = d + (direction * full_weeks * 7)
            while remaining > 0
              current += direction
              remaining -= 1 unless current.saturday? || current.sunday?
            end
            dv.of_string(DateTimeVerbs.format_date_str(current))
          }

          registry["nextBusinessDay"] = ->(args, _ctx) {
            return dv.of_null if args.empty?
            v = args[0]
            return dv.of_null if v.nil? || v.null?
            d = DateTimeVerbs.parse_date(v)
            return dv.of_null unless d
            if d.saturday?
              d += 2
            elsif d.sunday?
              d += 1
            end
            dv.of_string(DateTimeVerbs.format_date_str(d))
          }

          registry["formatDuration"] = ->(args, _ctx) {
            return dv.of_null if args.empty?
            iso = args[0]&.to_string
            return dv.of_null if iso.nil? || !iso.start_with?("P")
            parts = []
            in_time = false
            num_buf = String.new
            iso[1..].each_char do |ch|
              case ch
              when "T"
                in_time = true
              when "0".."9", "."
                num_buf << ch
              when "Y"
                unless in_time
                  n = num_buf.to_f
                  parts << DateTimeVerbs.duration_part(n, "year") unless n == 0
                  num_buf = String.new
                end
              when "M"
                n = num_buf.to_f
                if in_time
                  parts << DateTimeVerbs.duration_part(n, "minute") unless n == 0
                else
                  parts << DateTimeVerbs.duration_part(n, "month") unless n == 0
                end
                num_buf = String.new
              when "D"
                n = num_buf.to_f
                parts << DateTimeVerbs.duration_part(n, "day") unless n == 0
                num_buf = String.new
              when "H"
                n = num_buf.to_f
                parts << DateTimeVerbs.duration_part(n, "hour") unless n == 0
                num_buf = String.new
              when "S"
                n = num_buf.to_f
                parts << DateTimeVerbs.duration_part(n, "second") unless n == 0
                num_buf = String.new
              end
            end
            dv.of_string(parts.empty? ? "0 seconds" : parts.join(", "))
          }
        end
      end
    end
  end
end
