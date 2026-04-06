# frozen_string_literal: true

module Odin
  module Serialization
    class Canonicalize
      # Pre-compiled regex for splitting paths into segments
      RE_PATH_SPLIT = /(\[[^\]]*\])|\./.freeze
      # Matches a pure-integer bracket segment like [0], [12]
      RE_ARRAY_INDEX = /\A\[(\d+)\]\z/.freeze

      def canonicalize(doc)
        entries = []

        # Collect metadata as $.key entries
        doc.each_metadata do |key, value|
          entries << ["$.#{key}", value, nil]
        end

        # Collect all assignments (skip $.xxx already added from metadata)
        doc.each_assignment do |path, value|
          next if path.start_with?("$.")

          mods = doc.modifiers_for(path)
          entries << [path, value, mods]
        end

        return "" if entries.empty?

        # Pre-compute sort keys once, then sort by key (avoids repeated parsing)
        keyed = entries.map { |e| [canonical_sort_key(e[0]), e] }
        keyed.sort_by! { |k, _| k }

        # Build output
        output = +""
        keyed.each do |_, (path, value, mods)|
          output << path
          output << " = "
          output << Utils::FormatUtils.format_modifier_prefix(mods) if mods
          output << Utils::FormatUtils.format_canonical_value(value)
          output << "\n"
        end

        output
      end

      private

      # Build a sort key as an Array that Ruby's <=> can compare directly.
      # [priority, seg1, seg2, ...]
      # priority: 0 = $ metadata, 1 = normal, 2 = & extension
      # Each segment is either [0, integer] for array indices or [1, string] for names.
      def canonical_sort_key(path)
        first_byte = path.getbyte(0)
        priority = case first_byte
                   when 36 then 0  # $
                   when 38 then 2  # &
                   else 1
                   end

        key = [priority]

        # Fast path: no brackets — single string segment per dot-separated part
        unless path.include?("[")
          path.split(".").each { |s| key << [1, s] unless s.empty? }
          return key
        end

        # Split by dots, keeping bracket segments intact
        pos = 0
        len = path.length
        while pos < len
          byte = path.getbyte(pos)
          if byte == 46 # .
            pos += 1
            next
          end

          if byte == 91 # [
            close = path.index("]", pos)
            if close
              seg = path[pos..close]
              m = RE_ARRAY_INDEX.match(seg)
              if m
                key << [0, m[1].to_i]
              else
                key << [1, seg]
              end
              pos = close + 1
            else
              key << [1, path[pos..]]
              break
            end
          else
            # Find next . or [
            next_dot = path.index(".", pos)
            next_bracket = path.index("[", pos)
            end_pos = if next_dot && next_bracket
                        [next_dot, next_bracket].min
                      else
                        next_dot || next_bracket || len
                      end
            seg = path[pos...end_pos]
            key << [1, seg] unless seg.empty?
            pos = end_pos
          end
        end

        key
      end
    end
  end
end
