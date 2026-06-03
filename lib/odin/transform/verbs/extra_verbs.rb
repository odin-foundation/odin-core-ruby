# frozen_string_literal: true

require "digest"
require "openssl"
require "uri"

module Odin
  module Transform
    module Verbs
      # Object/array set operations, encoding, string and numeric helpers.
      module ExtraVerbs
        module_function

        DANGEROUS_KEYS = %w[__proto__ constructor prototype].freeze

        def safe_key?(key)
          !DANGEROUS_KEYS.include?(key.to_s.downcase)
        end

        def safe_keys(entries)
          entries.keys.select { |k| safe_key?(k) }
        end

        # Items of an array-like value, or nil when not array-like. A plain
        # (non-JSON) string is not array-like.
        def array_items(v)
          return nil unless v.is_a?(Types::DynValue)
          return v.value if v.array?
          if v.string?
            s = v.value.strip
            if s.start_with?("[")
              begin
                return Types::DynValue.extract_array(v.value).value
              rescue StandardError
                return nil
              end
            end
          end
          nil
        end

        # Read a named field from an array item (DynValue object), else null.
        def field_value(item, field)
          return Types::DynValue.of_null unless item.is_a?(Types::DynValue) && item.object?
          item.value[field] || Types::DynValue.of_null
        end

        # Canonical equality key for set operations: stable JSON of the value.
        def value_key(item)
          stable_json(to_plain(item))
        end

        # Convert a DynValue to a plain Ruby value (for JSON serialization).
        def to_plain(v)
          return nil unless v.is_a?(Types::DynValue)
          v.to_ruby
        end

        # Recursively serialize a plain Ruby value to JSON with object keys sorted.
        def stable_json(value)
          case value
          when nil then "null"
          when Array then "[" + value.map { |e| stable_json(e) }.join(",") + "]"
          when Hash
            parts = value.keys.sort.map { |k| "#{k.to_s.inspect}:#{stable_json(value[k])}" }
            "{" + parts.join(",") + "}"
          when String then value.inspect
          when true, false then value.to_s
          else value.to_s
          end
        end

        def matches_op?(item_val, op, cmp)
          case op
          when "=", "==" then item_val.to_string == cmp.to_string
          when "!=", "<>" then item_val.to_string != cmp.to_string
          when "<" then (NumericVerbs.to_double(item_val) || 0) < (NumericVerbs.to_double(cmp) || 0)
          when "<=" then (NumericVerbs.to_double(item_val) || 0) <= (NumericVerbs.to_double(cmp) || 0)
          when ">" then (NumericVerbs.to_double(item_val) || 0) > (NumericVerbs.to_double(cmp) || 0)
          when ">=" then (NumericVerbs.to_double(item_val) || 0) >= (NumericVerbs.to_double(cmp) || 0)
          when "contains" then item_val.to_string.include?(cmp.to_string)
          when "startsWith" then item_val.to_string.start_with?(cmp.to_string)
          when "endsWith" then item_val.to_string.end_with?(cmp.to_string)
          else false
          end
        end

        def register(registry)
          dv = Types::DynValue
          ex = ExtraVerbs

          register_object(registry, dv, ex)
          register_array(registry, dv, ex)
          register_encoding(registry, dv, ex)
          register_string(registry, dv, ex)
          register_numeric(registry, dv, ex)
        end

        # ── Object verbs ──

        def register_object(registry, dv, ex)
          registry["pick"] = ->(args, _ctx) {
            return dv.of_null if args.empty?
            val = args[0]
            return dv.of_null unless val&.object?
            src = val.value
            result = {}
            args[1..].each do |a|
              key = a&.to_string || ""
              result[key] = src[key] if ex.safe_key?(key) && src.key?(key)
            end
            dv.of_object(result)
          }

          registry["omit"] = ->(args, _ctx) {
            return dv.of_null if args.empty?
            val = args[0]
            return dv.of_null unless val&.object?
            src = val.value
            drop = args[1..].map { |a| a&.to_string || "" }
            result = {}
            ex.safe_keys(src).each { |k| result[k] = src[k] unless drop.include?(k) }
            dv.of_object(result)
          }

          registry["fromEntries"] = ->(args, _ctx) {
            return dv.of_null if args.empty?
            pairs = args[0]
            return dv.of_null unless pairs&.array?
            result = {}
            pairs.value.each do |entry|
              next unless entry.is_a?(Types::DynValue) && entry.array? && entry.value.length >= 2
              key = entry.value[0].to_string
              result[key] = entry.value[1] if ex.safe_key?(key)
            end
            dv.of_object(result)
          }

          registry["invert"] = ->(args, _ctx) {
            return dv.of_null if args.empty?
            val = args[0]
            return dv.of_null unless val&.object?
            src = val.value
            result = {}
            ex.safe_keys(src).each do |k|
              new_key = src[k].to_string
              result[new_key] = dv.of_string(k) if ex.safe_key?(new_key)
            end
            dv.of_object(result)
          }

          registry["defaults"] = ->(args, _ctx) {
            return dv.of_null if args.length < 2
            a = args[0]
            d = args[1]
            return (d&.object? ? d : dv.of_null) unless a&.object?
            return a unless d&.object?
            result = {}
            ex.safe_keys(a.value).each { |k| result[k] = a.value[k] }
            ex.safe_keys(d.value).each { |k| result[k] = d.value[k] unless result.key?(k) }
            dv.of_object(result)
          }

          registry["renameKeys"] = ->(args, _ctx) {
            return dv.of_null if args.length < 2
            val = args[0]
            map = args[1]
            return dv.of_null unless val&.object?
            return val unless map&.object?
            src = val.value
            rename = map.value
            result = {}
            ex.safe_keys(src).each do |k|
              new_key = rename.key?(k) ? rename[k].to_string : k
              result[new_key] = src[k] if ex.safe_key?(new_key)
            end
            dv.of_object(result)
          }

          registry["compactObject"] = ->(args, _ctx) {
            return dv.of_null if args.empty?
            val = args[0]
            return dv.of_null unless val&.object?
            src = val.value
            result = {}
            ex.safe_keys(src).each do |k|
              v = src[k]
              next if v.nil? || v.null?
              next if v.string? && v.value.empty?
              next if v.array? && v.value.empty?
              next if v.object? && v.value.empty?
              result[k] = v
            end
            dv.of_object(result)
          }
        end

        # ── Array verbs ──

        def register_array(registry, dv, ex)
          registry["intersection"] = ->(args, _ctx) {
            return dv.of_array([]) if args.length < 2
            a = ex.array_items(args[0])
            b = ex.array_items(args[1])
            return dv.of_array([]) if a.nil? || b.nil?
            b_keys = b.map { |i| ex.value_key(i) }.to_set
            seen = {}
            result = []
            a.each do |item|
              k = ex.value_key(item)
              if b_keys.include?(k) && !seen[k]
                seen[k] = true
                result << item
              end
            end
            dv.of_array(result)
          }

          registry["union"] = ->(args, _ctx) {
            return dv.of_array([]) if args.length < 2
            a = ex.array_items(args[0]) || []
            b = ex.array_items(args[1]) || []
            seen = {}
            result = []
            (a + b).each do |item|
              k = ex.value_key(item)
              unless seen[k]
                seen[k] = true
                result << item
              end
            end
            dv.of_array(result)
          }

          registry["difference"] = ->(args, _ctx) {
            return dv.of_array([]) if args.length < 2
            a = ex.array_items(args[0])
            return dv.of_array([]) if a.nil?
            b_keys = (ex.array_items(args[1]) || []).map { |i| ex.value_key(i) }.to_set
            seen = {}
            result = []
            a.each do |item|
              k = ex.value_key(item)
              if !b_keys.include?(k) && !seen[k]
                seen[k] = true
                result << item
              end
            end
            dv.of_array(result)
          }

          registry["symmetricDifference"] = ->(args, _ctx) {
            return dv.of_array([]) if args.length < 2
            a = ex.array_items(args[0]) || []
            b = ex.array_items(args[1]) || []
            a_keys = a.map { |i| ex.value_key(i) }.to_set
            b_keys = b.map { |i| ex.value_key(i) }.to_set
            seen = {}
            result = []
            a.each do |item|
              k = ex.value_key(item)
              if !b_keys.include?(k) && !seen[k]
                seen[k] = true
                result << item
              end
            end
            b.each do |item|
              k = ex.value_key(item)
              if !a_keys.include?(k) && !seen[k]
                seen[k] = true
                result << item
              end
            end
            dv.of_array(result)
          }

          registry["countBy"] = ->(args, _ctx) {
            return dv.of_null if args.empty?
            items = ex.array_items(args[0])
            return dv.of_null if items.nil?
            field = args.length > 1 ? args[1]&.to_string : nil
            counts = Hash.new(0)
            items.each do |item|
              v = field ? ex.field_value(item, field) : item
              counts[v.to_string] += 1
            end
            result = {}
            counts.keys.sort.each { |k| result[k] = dv.of_integer(counts[k]) if ex.safe_key?(k) }
            dv.of_object(result)
          }

          registry["keyBy"] = ->(args, _ctx) {
            return dv.of_null if args.length < 2
            items = ex.array_items(args[0])
            return dv.of_null if items.nil?
            field = args[1]&.to_string || ""
            result = {}
            items.each do |item|
              key = ex.field_value(item, field).to_string
              result[key] = item if ex.safe_key?(key)
            end
            dv.of_object(result)
          }

          registry["explode"] = ->(args, _ctx) {
            return dv.of_array([]) if args.length < 2
            items = ex.array_items(args[0])
            return dv.of_array([]) if items.nil?
            field = args[1]&.to_string || ""
            result = []
            items.each do |item|
              unless item.is_a?(Types::DynValue) && item.object?
                result << item
                next
              end
              base = item.value
              field_val = base[field]
              elements = field_val&.array? ? field_val.value : nil
              if elements.nil? || elements.empty?
                result << dv.of_object(base.dup)
                next
              end
              elements.each do |el|
                result << dv.of_object(base.merge(field => el))
              end
            end
            dv.of_array(result)
          }

          registry["window"] = ->(args, _ctx) {
            return dv.of_array([]) if args.length < 2
            items = ex.array_items(args[0])
            return dv.of_array([]) if items.nil?
            n = (NumericVerbs.to_double(args[1]) || 0).floor
            return dv.of_array([]) if n <= 0 || items.length < n
            result = []
            (0..(items.length - n)).each do |i|
              result << dv.of_array(items[i, n])
            end
            dv.of_array(result)
          }

          registry["countIf"] = ->(args, _ctx) {
            return dv.of_integer(0) if args.length < 4
            items = CollectionVerbs.extract_items(args[0])
            field = args[1]&.to_string || ""
            op = args[2]&.to_string || "="
            cmp = args[3]
            count = items.count { |item| ex.matches_op?(ex.field_value(item, field), op, cmp) }
            dv.of_integer(count)
          }

          registry["sumIf"] = ->(args, _ctx) {
            return dv.of_integer(0) if args.length < 4
            items = CollectionVerbs.extract_items(args[0])
            field = args[1]&.to_string || ""
            op = args[2]&.to_string || "="
            cmp = args[3]
            sum_field = args.length >= 5 ? args[4]&.to_string : field
            total = 0.0
            items.each do |item|
              total += (NumericVerbs.to_double(ex.field_value(item, sum_field)) || 0) if ex.matches_op?(ex.field_value(item, field), op, cmp)
            end
            NumericVerbs.numeric_result(total)
          }

          registry["avgIf"] = ->(args, _ctx) {
            return dv.of_null if args.length < 4
            items = CollectionVerbs.extract_items(args[0])
            field = args[1]&.to_string || ""
            op = args[2]&.to_string || "="
            cmp = args[3]
            avg_field = args.length >= 5 ? args[4]&.to_string : field
            total = 0.0
            count = 0
            items.each do |item|
              if ex.matches_op?(ex.field_value(item, field), op, cmp)
                total += (NumericVerbs.to_double(ex.field_value(item, avg_field)) || 0)
                count += 1
              end
            end
            return dv.of_null if count.zero?
            NumericVerbs.numeric_result(total / count)
          }
        end

        # ── Encoding verbs ──

        def register_encoding(registry, dv, ex)
          require "base64"

          registry["base64urlEncode"] = ->(args, _ctx) {
            return dv.of_null if args.empty?
            value = args[0]&.to_string || ""
            dv.of_string(Base64.urlsafe_encode64(value, padding: false))
          }

          registry["base64urlDecode"] = ->(args, _ctx) {
            return dv.of_null if args.empty?
            value = args[0]&.to_string || ""
            padded = value.tr("-_", "+/")
            padded += "=" * ((4 - padded.length % 4) % 4)
            begin
              dv.of_string(Base64.decode64(padded).force_encoding("UTF-8"))
            rescue StandardError
              dv.of_null
            end
          }

          registry["hmac"] = ->(args, _ctx) {
            return dv.of_null if args.length < 2
            message = args[0]&.to_string || ""
            key = args[1]&.to_string || ""
            alg = args.length >= 3 ? (args[2]&.to_string || "sha256").downcase : "sha256"
            begin
              dv.of_string(OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new(alg), key, message).downcase)
            rescue StandardError
              dv.of_null
            end
          }

          registry["parseUrl"] = ->(args, _ctx) {
            return dv.of_null if args.empty?
            ExtraVerbs.parse_url(args[0]&.to_string || "")
          }

          registry["buildUrl"] = ->(args, ctx) {
            return dv.of_null if args.empty?
            ExtraVerbs.build_url(args[0], registry, ctx)
          }

          registry["parseQuery"] = ->(args, _ctx) {
            return dv.of_null if args.empty?
            raw = (args[0]&.to_string || "").sub(/\A\?/, "")
            dv.of_object(ExtraVerbs.sorted_query(raw))
          }

          registry["buildQuery"] = ->(args, _ctx) {
            return dv.of_null if args.empty?
            val = args[0]
            return dv.of_null unless val&.object?
            dv.of_string(ExtraVerbs.build_query(val.value))
          }

          registry["stableStringify"] = ->(args, _ctx) {
            return dv.of_null if args.empty?
            dv.of_string(ex.stable_json(ex.to_plain(args[0])))
          }

          registry["canonicalHash"] = ->(args, _ctx) {
            return dv.of_null if args.empty?
            canonical = ex.stable_json(ex.to_plain(args[0]))
            dv.of_string(Digest::SHA256.hexdigest(canonical).downcase)
          }
        end

        # Build a sorted query object from a raw query string.
        def sorted_query(raw)
          pairs = {}
          raw.split("&").each do |pair|
            next if pair.empty?
            k, v = pair.split("=", 2)
            key = URI.decode_www_form_component(k || "")
            val = v.nil? ? "" : URI.decode_www_form_component(v)
            pairs[key] = val
          end
          result = {}
          pairs.keys.sort.each { |k| result[k] = Types::DynValue.of_string(pairs[k]) }
          result
        end

        def build_query(entries)
          parts = []
          entries.keys.sort.each do |k|
            v = entries[k]
            next if v.nil? || v.null?
            parts << "#{URI.encode_www_form_component(k)}=#{URI.encode_www_form_component(v.to_string)}"
          end
          parts.join("&")
        end

        def parse_url(text)
          dv = Types::DynValue
          begin
            u = URI.parse(text)
            return dv.of_null if u.scheme.nil? || u.host.nil? || u.host.empty?
            query = u.query ? sorted_query(u.query) : {}
            dv.of_object(
              "scheme" => dv.of_string(u.scheme),
              "host" => dv.of_string(u.host),
              "port" => u.port && !default_port?(u) ? dv.of_integer(u.port) : dv.of_null,
              "path" => dv.of_string(u.path || ""),
              "query" => dv.of_object(query),
              "fragment" => dv.of_string(u.fragment || "")
            )
          rescue StandardError
            dv.of_null
          end
        end

        # Port is explicit only when present in the raw URL string.
        def default_port?(uri)
          uri.default_port == uri.port && !uri.to_s.match?(/:\d+/)
        end

        def build_url(val, registry, _ctx)
          dv = Types::DynValue
          return dv.of_null unless val&.object?
          o = val.value
          get = ->(k) { o[k].nil? || o[k].null? ? "" : o[k].to_string }
          scheme = get.call("scheme")
          host = get.call("host")
          return dv.of_null if scheme.empty? || host.empty?
          port = get.call("port")
          path = get.call("path")
          fragment = get.call("fragment")
          url = +"#{scheme}://#{host}"
          url << ":#{port}" unless port.empty?
          url << (path.start_with?("/") ? path : (path.empty? ? "" : "/#{path}"))
          q = o["query"]
          if q&.object? && !q.value.empty?
            qs = build_query(q.value)
            url << "?#{qs}" unless qs.empty?
          end
          url << "##{fragment}" unless fragment.empty?
          dv.of_string(url)
        end

        # ── String verbs ──

        HTML_ESCAPES = { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", '"' => "&quot;", "'" => "&#39;" }.freeze

        def register_string(registry, dv, ex)
          registry["escapeHtml"] = ->(args, _ctx) {
            return dv.of_null if args.empty?
            dv.of_string((args[0]&.to_string || "").gsub(/[&<>"']/) { |c| HTML_ESCAPES[c] })
          }

          registry["unescapeHtml"] = ->(args, _ctx) {
            return dv.of_null if args.empty?
            s = (args[0]&.to_string || "").gsub(/&(?:amp|lt|gt|quot|apos|#39);/) do |m|
              { "&amp;" => "&", "&lt;" => "<", "&gt;" => ">", "&quot;" => '"', "&apos;" => "'", "&#39;" => "'" }[m]
            end
            s = s.gsub(/&#(\d+);/) { [$1.to_i].pack("U") }
                 .gsub(/&#x([0-9a-fA-F]+);/) { [$1.to_i(16)].pack("U") }
            dv.of_string(s)
          }

          registry["escapeXml"] = ->(args, _ctx) {
            return dv.of_null if args.empty?
            dv.of_string((args[0]&.to_string || "").gsub(/[&<>"']/) { |c| c == "'" ? "&apos;" : HTML_ESCAPES[c] })
          }

          registry["stripTags"] = ->(args, _ctx) {
            return dv.of_null if args.empty?
            dv.of_string((args[0]&.to_string || "").gsub(/<[^>]*>/, ""))
          }

          registry["template"] = ->(args, _ctx) {
            return dv.of_null if args.length < 2
            tpl = args[0]&.to_string || ""
            src = args[1]
            fields = src&.object? ? src.value : {}
            result = tpl.gsub(/\{([^{}]+)\}/) do
              k = $1.strip
              if fields.key?(k)
                v = fields[k]
                v.nil? || v.null? ? "" : v.to_string
              else
                ""
              end
            end
            dv.of_string(result)
          }
        end

        # ── Numeric verbs ──

        def register_numeric(registry, dv, _ex)
          registry["gcd"] = ->(args, _ctx) {
            return dv.of_null if args.length < 2
            a = (NumericVerbs.to_double(args[0]) || 0).truncate.abs
            b = (NumericVerbs.to_double(args[1]) || 0).truncate.abs
            a, b = b, a % b while b != 0
            dv.of_integer(a)
          }

          registry["lcm"] = ->(args, _ctx) {
            return dv.of_null if args.length < 2
            a = (NumericVerbs.to_double(args[0]) || 0).truncate.abs
            b = (NumericVerbs.to_double(args[1]) || 0).truncate.abs
            return dv.of_integer(0) if a.zero? || b.zero?
            x = a
            y = b
            x, y = y, x % y while y != 0
            result = (a / x) * b
            return dv.of_null if result.abs > 2**53
            dv.of_integer(result)
          }

          registry["factorial"] = ->(args, _ctx) {
            return dv.of_null if args.empty?
            n = NumericVerbs.to_double(args[0])
            return dv.of_null if n.nil? || n != n.floor || n < 0 || n > 18
            result = 1
            (2..n.to_i).each { |i| result *= i }
            dv.of_integer(result)
          }
        end
      end
    end
  end
end
