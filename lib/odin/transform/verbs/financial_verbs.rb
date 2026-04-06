# frozen_string_literal: true

require "bigdecimal"

module Odin
  module Transform
    module Verbs
      module FinancialVerbs
        module_function

        def safe_result(val)
          return Types::DynValue.of_null if val.nil? || val.nan? || val.infinite?
          NumericVerbs.numeric_result(val)
        end

        def register(registry)
          dv = Types::DynValue

          registry["compound"] = ->(args, _ctx) {
            principal = NumericVerbs.to_double(args[0])
            rate = NumericVerbs.to_double(args[1])
            periods = NumericVerbs.to_double(args[2])
            return dv.of_null if principal.nil? || rate.nil? || periods.nil?
            result = principal * (1.0 + rate)**periods
            FinancialVerbs.safe_result(result)
          }

          registry["discount"] = ->(args, _ctx) {
            fv = NumericVerbs.to_double(args[0])
            rate = NumericVerbs.to_double(args[1])
            periods = NumericVerbs.to_double(args[2])
            return dv.of_null if fv.nil? || rate.nil? || periods.nil?
            result = fv / (1.0 + rate)**periods
            FinancialVerbs.safe_result(result)
          }

          registry["pmt"] = ->(args, _ctx) {
            principal = NumericVerbs.to_double(args[0])
            rate = NumericVerbs.to_double(args[1])
            nper = NumericVerbs.to_double(args[2])
            return dv.of_null if principal.nil? || rate.nil? || nper.nil?

            if rate == 0.0
              return dv.of_null if nper <= 0
              result = principal / nper
            else
              pwr = (1.0 + rate)**nper
              result = (principal * rate * pwr) / (pwr - 1.0)
            end
            FinancialVerbs.safe_result(result)
          }

          registry["fv"] = ->(args, _ctx) {
            payment = NumericVerbs.to_double(args[0])
            rate = NumericVerbs.to_double(args[1])
            nper = NumericVerbs.to_double(args[2])
            return dv.of_null if payment.nil? || rate.nil? || nper.nil?

            if rate == 0.0
              result = payment * nper
            else
              result = payment * ((1.0 + rate)**nper - 1.0) / rate
            end
            FinancialVerbs.safe_result(result)
          }

          registry["pv"] = ->(args, _ctx) {
            payment = NumericVerbs.to_double(args[0])
            rate = NumericVerbs.to_double(args[1])
            nper = NumericVerbs.to_double(args[2])
            return dv.of_null if payment.nil? || rate.nil? || nper.nil?

            if rate == 0.0
              result = payment * nper
            else
              result = payment * (1.0 - (1.0 + rate)**(-nper)) / rate
            end
            FinancialVerbs.safe_result(result)
          }

          registry["npv"] = ->(args, _ctx) {
            rate = NumericVerbs.to_double(args[0])
            return dv.of_null if rate.nil?
            cashflows = CollectionVerbs.extract_items(args[1])
            return dv.of_null if cashflows.empty?

            total = 0.0
            cashflows.each_with_index do |cf, i|
              v = NumericVerbs.to_double(cf) || 0.0
              total += v / (1.0 + rate)**i
            end
            FinancialVerbs.safe_result(total)
          }

          registry["irr"] = ->(args, _ctx) {
            cashflows = CollectionVerbs.extract_items(args[0])
            return dv.of_null if cashflows.empty?
            guess = args[1] ? (NumericVerbs.to_double(args[1]) || 0.1) : 0.1

            cfs = cashflows.map { |cf| NumericVerbs.to_double(cf) || 0.0 }

            rate = guess
            100.times do
              npv = 0.0
              dnpv = 0.0
              cfs.each_with_index do |cf, i|
                npv += cf / (1.0 + rate)**i
                dnpv += -i * cf / (1.0 + rate)**(i + 1)
              end
              return dv.of_null if dnpv.abs < 1e-15
              new_rate = rate - npv / dnpv
              if (new_rate - rate).abs < 1e-10
                return FinancialVerbs.safe_result(new_rate)
              end
              rate = new_rate
            end
            dv.of_null
          }

          registry["rate"] = ->(args, _ctx) {
            nper = NumericVerbs.to_double(args[0])
            pmt_val = NumericVerbs.to_double(args[1])
            pv_val = NumericVerbs.to_double(args[2])
            fv_val = NumericVerbs.to_double(args[3]) || 0.0
            return dv.of_null if nper.nil? || pmt_val.nil? || pv_val.nil?

            rate = 0.1
            100.times do
              pwr = (1.0 + rate)**nper
              f = pv_val * pwr + pmt_val * (pwr - 1.0) / rate + fv_val
              df = pv_val * nper * (1.0 + rate)**(nper - 1) +
                   pmt_val * (nper * (1.0 + rate)**(nper - 1) * rate - (pwr - 1.0)) / (rate * rate)
              return dv.of_null if df.abs < 1e-15
              new_rate = rate - f / df
              if (new_rate - rate).abs < 1e-10
                return FinancialVerbs.safe_result(new_rate)
              end
              rate = new_rate
            end
            dv.of_null
          }

          registry["nper"] = ->(args, _ctx) {
            rate = NumericVerbs.to_double(args[0])
            pmt_val = NumericVerbs.to_double(args[1])
            pv_val = NumericVerbs.to_double(args[2])
            return dv.of_null if rate.nil? || pmt_val.nil? || pv_val.nil?

            if rate == 0.0
              return dv.of_null if pmt_val == 0.0
              return FinancialVerbs.safe_result(-pv_val / pmt_val)
            end

            denom_inner = pmt_val + rate * pv_val
            return dv.of_null if denom_inner == 0.0
            log_arg = pmt_val / denom_inner
            return dv.of_null if log_arg <= 0.0
            numerator = Math.log(log_arg)
            denominator = Math.log(1.0 + rate)
            return dv.of_null if denominator == 0.0
            FinancialVerbs.safe_result(numerator / denominator)
          }

          registry["depreciation"] = ->(args, _ctx) {
            cost = NumericVerbs.to_double(args[0])
            salvage = NumericVerbs.to_double(args[1])
            life = NumericVerbs.to_double(args[2])
            return dv.of_null if cost.nil? || salvage.nil? || life.nil? || life == 0
            FinancialVerbs.safe_result((cost - salvage) / life)
          }

          registry["variance"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            nums = items.filter_map { |item| NumericVerbs.to_double(item) }
            return dv.of_null if nums.empty?
            mean = nums.sum / nums.length.to_f
            var = nums.sum { |n| (n - mean)**2 } / nums.length.to_f
            dv.of_float(var)
          }

          registry["varianceSample"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            nums = items.filter_map { |item| NumericVerbs.to_double(item) }
            return dv.of_null if nums.length < 2
            mean = nums.sum / nums.length.to_f
            var = nums.sum { |n| (n - mean)**2 } / (nums.length - 1).to_f
            dv.of_float(var)
          }

          registry["std"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            nums = items.filter_map { |item| NumericVerbs.to_double(item) }
            return dv.of_null if nums.empty?
            mean = nums.sum / nums.length.to_f
            var = nums.sum { |n| (n - mean)**2 } / nums.length.to_f
            dv.of_float(Math.sqrt(var))
          }

          registry["stdSample"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            nums = items.filter_map { |item| NumericVerbs.to_double(item) }
            return dv.of_null if nums.length < 2
            mean = nums.sum / nums.length.to_f
            var = nums.sum { |n| (n - mean)**2 } / (nums.length - 1).to_f
            dv.of_float(Math.sqrt(var))
          }

          registry["median"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            nums = items.filter_map { |item| NumericVerbs.to_double(item) }
            return dv.of_null if nums.empty?
            sorted = nums.sort
            mid = sorted.length / 2
            if sorted.length.odd?
              NumericVerbs.numeric_result(sorted[mid])
            else
              NumericVerbs.numeric_result((sorted[mid - 1] + sorted[mid]) / 2.0)
            end
          }

          registry["mode"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            return dv.of_null if items.empty?
            freq = {}
            items.each do |item|
              key = item.to_string
              freq[key] ||= { count: 0, value: item }
              freq[key][:count] += 1
            end
            max_count = freq.values.max_by { |v| v[:count] }
            max_count ? max_count[:value] : dv.of_null
          }

          registry["percentile"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            p = NumericVerbs.to_double(args[1])
            return dv.of_null if p.nil?
            nums = items.filter_map { |item| NumericVerbs.to_double(item) }
            return dv.of_null if nums.empty?
            sorted = nums.sort
            # Linear interpolation
            rank = (p / 100.0) * (sorted.length - 1)
            lower = rank.floor
            upper = rank.ceil
            if lower == upper
              NumericVerbs.numeric_result(sorted[lower])
            else
              frac = rank - lower
              NumericVerbs.numeric_result(sorted[lower] + frac * (sorted[upper] - sorted[lower]))
            end
          }

          registry["quantile"] = ->(args, _ctx) {
            items = CollectionVerbs.extract_items(args[0])
            q = NumericVerbs.to_double(args[1])
            return dv.of_null if q.nil?
            nums = items.filter_map { |item| NumericVerbs.to_double(item) }
            return dv.of_null if nums.empty?
            sorted = nums.sort
            rank = q * (sorted.length - 1)
            lower = rank.floor
            upper = rank.ceil
            if lower == upper
              NumericVerbs.numeric_result(sorted[lower])
            else
              frac = rank - lower
              NumericVerbs.numeric_result(sorted[lower] + frac * (sorted[upper] - sorted[lower]))
            end
          }

          registry["covariance"] = ->(args, _ctx) {
            items_x = CollectionVerbs.extract_items(args[0])
            items_y = CollectionVerbs.extract_items(args[1])
            xs = items_x.filter_map { |item| NumericVerbs.to_double(item) }
            ys = items_y.filter_map { |item| NumericVerbs.to_double(item) }
            n = [xs.length, ys.length].min
            return dv.of_null if n == 0
            mean_x = xs[0...n].sum / n.to_f
            mean_y = ys[0...n].sum / n.to_f
            cov = (0...n).sum { |i| (xs[i] - mean_x) * (ys[i] - mean_y) } / n.to_f
            dv.of_float(cov)
          }

          registry["correlation"] = ->(args, _ctx) {
            items_x = CollectionVerbs.extract_items(args[0])
            items_y = CollectionVerbs.extract_items(args[1])
            xs = items_x.filter_map { |item| NumericVerbs.to_double(item) }
            ys = items_y.filter_map { |item| NumericVerbs.to_double(item) }
            n = [xs.length, ys.length].min
            return dv.of_null if n == 0
            mean_x = xs[0...n].sum / n.to_f
            mean_y = ys[0...n].sum / n.to_f
            cov = (0...n).sum { |i| (xs[i] - mean_x) * (ys[i] - mean_y) }
            var_x = (0...n).sum { |i| (xs[i] - mean_x)**2 }
            var_y = (0...n).sum { |i| (ys[i] - mean_y)**2 }
            denom = Math.sqrt(var_x * var_y)
            return dv.of_null if denom < 1e-15
            dv.of_float(cov / denom)
          }

          registry["zscore"] = ->(args, _ctx) {
            value = NumericVerbs.to_double(args[0])
            mean = NumericVerbs.to_double(args[1])
            stddev = NumericVerbs.to_double(args[2])
            return dv.of_null if value.nil? || mean.nil? || stddev.nil? || stddev == 0
            dv.of_float((value - mean) / stddev)
          }

          registry["interpolate"] = ->(args, _ctx) {
            a = NumericVerbs.to_double(args[0])
            b = NumericVerbs.to_double(args[1])
            t = NumericVerbs.to_double(args[2])
            return dv.of_null if a.nil? || b.nil? || t.nil?
            result = a + (b - a) * t
            FinancialVerbs.safe_result(result)
          }

          registry["weightedAvg"] = ->(args, _ctx) {
            values = CollectionVerbs.extract_items(args[0])
            weights = CollectionVerbs.extract_items(args[1])
            return dv.of_null if values.empty? || weights.empty?

            n = [values.length, weights.length].min
            sum_vw = 0.0
            sum_w = 0.0
            (0...n).each do |i|
              v = NumericVerbs.to_double(values[i]) || 0.0
              w = NumericVerbs.to_double(weights[i]) || 0.0
              sum_vw += v * w
              sum_w += w
            end
            return dv.of_null if sum_w == 0.0
            dv.of_float(sum_vw / sum_w)
          }

          registry["movingAvg"] = ->(args, _ctx) {
            return dv.of_null if args.length < 2
            arr = args[0]
            return dv.of_null unless arr&.array?
            window = NumericVerbs.to_double(args[1])&.to_i
            return dv.of_null if window.nil? || window < 1
            items = arr.as_array
            values = items.map { |item| NumericVerbs.to_double(item) || 0.0 }
            result = values.each_with_index.map do |_v, i|
              start = [0, i - window + 1].max
              window_vals = values[start..i]
              avg = window_vals.sum / window_vals.length.to_f
              NumericVerbs.numeric_result(avg)
            end
            dv.of_array(result)
          }
        end
      end
    end
  end
end
