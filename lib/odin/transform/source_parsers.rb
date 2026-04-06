# frozen_string_literal: true

require "json"
require "csv"
require "rexml/document"
require "yaml"

module Odin
  module Transform
    module SourceParsers
      # Parse JSON string into DynValue
      def self.parse_json(input)
        raise ArgumentError, "Input cannot be nil or empty" if input.nil? || input.strip.empty?

        parsed = JSON.parse(input)
        Types::DynValue.from_json_value(parsed)
      rescue JSON::ParserError => e
        raise FormatError, "Invalid JSON: #{e.message}"
      end

      # Parse CSV string into DynValue (array of objects)
      def self.parse_csv(input, headers: true, delimiter: ",")
        return Types::DynValue.of_array([]) if input.nil? || input.strip.empty?

        # Strip BOM
        cleaned = input.sub(/\A\xEF\xBB\xBF/n, "")
        cleaned = cleaned.encode("UTF-8", "UTF-8", invalid: :replace, undef: :replace)

        rows = parse_csv_rows(cleaned, delimiter)
        return Types::DynValue.of_array([]) if rows.empty?

        if headers && rows.size > 1
          header_row = rows[0]
          data_rows = rows[1..]
          items = data_rows.map do |row|
            fields = {}
            header_row.each_with_index do |col, i|
              val = i < row.size ? row[i] : ""
              fields[col] = infer_type(val)
            end
            Types::DynValue.of_object(fields)
          end
          Types::DynValue.of_array(items)
        elsif headers
          # Only header, no data
          Types::DynValue.of_array([])
        else
          items = rows.map do |row|
            Types::DynValue.of_array(row.map { |cell| infer_type(cell) })
          end
          Types::DynValue.of_array(items)
        end
      end

      # Parse XML string into DynValue
      def self.parse_xml(input)
        raise ArgumentError, "Input cannot be nil or empty" if input.nil? || input.strip.empty?

        # Pre-process: mark self-closing elements with a synthetic attribute
        # REXML doesn't distinguish <tag/> from <tag></tag>, so we inject a marker
        marked = input.gsub(/<([a-zA-Z_][\w:.-]*)\s*(\s[^>]*)?\/>/) do |_match|
          tag_name = $1
          attrs = $2 || ""
          "<#{tag_name}#{attrs} __odin_sc=\"1\"/>"
        end

        doc = REXML::Document.new(marked)
        root = doc.root
        raise FormatError, "No root element found" unless root

        root_name = qualified_name(root)
        content = parse_xml_element(root, 0)
        Types::DynValue.of_object({ root_name => content })
      rescue REXML::ParseException => e
        raise FormatError, "Invalid XML: #{e.message}"
      end

      # Parse fixed-width text into DynValue
      # columns: [{name:, pos:, len:, trim: true}]
      def self.parse_fixed_width(input, columns:)
        return Types::DynValue.of_array([]) if input.nil? || input.strip.empty?
        raise ArgumentError, "Columns specification required" if columns.nil? || columns.empty?

        lines = input.lines.map(&:chomp).reject(&:empty?)
        rows = lines.map do |line|
          fields = {}
          columns.each do |col|
            start_pos = col[:pos] || 0
            len = col[:len] || 0
            name = col[:name]
            trim = col.fetch(:trim, true)

            raw = if start_pos < line.length
                    end_pos = [start_pos + len, line.length].min
                    line[start_pos...end_pos] || ""
                  else
                    ""
                  end
            raw = raw.strip if trim
            fields[name] = Types::DynValue.of_string(raw)
          end
          Types::DynValue.of_object(fields)
        end

        rows.size == 1 ? rows[0] : Types::DynValue.of_array(rows)
      end

      # Parse flat key=value pairs into DynValue
      def self.parse_flat_kvp(input)
        return Types::DynValue.of_object({}) if input.nil? || input.strip.empty?

        result = {}
        input.each_line do |line|
          line = line.chomp.sub(/\r$/, "")
          next if line.strip.empty?
          next if line.strip.start_with?("#", ";")

          eq_pos = line.index("=")
          next unless eq_pos

          key = line[0...eq_pos].strip
          val_str = line[(eq_pos + 1)..].strip

          value = parse_flat_value(val_str)
          set_nested(result, key, value)
        end

        Types::DynValue.of_object(result.transform_values { |v| wrap_nested(v) })
      end

      # Parse YAML string into DynValue
      def self.parse_yaml(input)
        return Types::DynValue.of_object({}) if input.nil? || input.strip.empty?

        parsed = YAML.safe_load(input, permitted_classes: [Date, Time, BigDecimal])
        Types::DynValue.from_ruby(parsed)
      rescue Psych::SyntaxError => e
        raise FormatError, "Invalid YAML: #{e.message}"
      end

      # ── Private Helpers ──

      # CSV row parser handling quoted fields, embedded commas, embedded newlines
      def self.parse_csv_rows(input, delimiter)
        rows = []
        current_row = []
        current_field = +""
        in_quotes = false
        i = 0
        chars = input.chars

        while i < chars.length
          ch = chars[i]

          if in_quotes
            if ch == '"'
              if i + 1 < chars.length && chars[i + 1] == '"'
                current_field << '"'
                i += 2
              else
                in_quotes = false
                i += 1
              end
            else
              current_field << ch
              i += 1
            end
          elsif ch == '"'
            in_quotes = true
            i += 1
          elsif ch == delimiter
            current_row << current_field
            current_field = +""
            i += 1
          elsif ch == "\r"
            if i + 1 < chars.length && chars[i + 1] == "\n"
              i += 2
            else
              i += 1
            end
            current_row << current_field
            rows << current_row unless current_row.all?(&:empty?) && rows.empty? && current_row.size <= 1
            current_row = []
            current_field = +""
          elsif ch == "\n"
            current_row << current_field
            rows << current_row
            current_row = []
            current_field = +""
            i += 1
          else
            current_field << ch
            i += 1
          end
        end

        # Final field/row
        unless current_field.empty? && current_row.empty?
          current_row << current_field
          rows << current_row
        end

        rows
      end

      # Type inference for CSV/flat values
      def self.infer_type(val)
        return Types::DynValue.of_null if val.nil? || val == "null"
        return Types::DynValue.of_bool(true) if val == "true"
        return Types::DynValue.of_bool(false) if val == "false"

        if val.match?(/\A-?\d+\z/)
          Types::DynValue.of_integer(val.to_i)
        elsif val.match?(/\A-?\d+(\.\d+)?([eE][+-]?\d+)?\z/)
          Types::DynValue.of_float(val.to_f)
        else
          Types::DynValue.of_string(val)
        end
      end

      # Parse flat value (quoted string, null, bool, number, or plain string)
      def self.parse_flat_value(val_str)
        return Types::DynValue.of_null if val_str.empty? || val_str == "~"

        if val_str.start_with?('"') && val_str.end_with?('"') && val_str.length >= 2
          return Types::DynValue.of_string(val_str[1...-1])
        end

        infer_type(val_str)
      end

      # Set nested value using dotted/bracket path
      def self.set_nested(root, path, value)
        segments = parse_path_segments(path)
        current = root

        segments[0...-1].each_with_index do |seg, idx|
          next_seg = segments[idx + 1]
          if seg.is_a?(Integer)
            current[seg] ||= next_seg.is_a?(Integer) ? [] : {}
            current = current[seg]
          else
            current[seg] ||= next_seg.is_a?(Integer) ? [] : {}
            current = current[seg]
          end
        end

        last = segments.last
        current[last] = value
      end

      # Parse path into segments: "a.b[0].c" -> ["a", "b", 0, "c"]
      def self.parse_path_segments(path)
        segments = []
        path.scan(/([^.\[\]]+)|\[(\d+)\]/) do |name, index|
          if index
            segments << index.to_i
          else
            segments << name
          end
        end
        segments
      end

      # Wrap nested Hash/Array into DynValue
      def self.wrap_nested(obj)
        case obj
        when Types::DynValue then obj
        when Hash
          Types::DynValue.of_object(obj.transform_values { |v| wrap_nested(v) })
        when Array
          Types::DynValue.of_array(obj.map { |v| wrap_nested(v) })
        else
          obj
        end
      end

      # Parse XML element recursively
      def self.parse_xml_element(element, depth)
        raise FormatError, "XML nesting depth exceeded (max 100)" if depth > 100

        # Check xsi:nil
        nil_attr = element.attributes["xsi:nil"] || element.attributes["nil"]
        return Types::DynValue.of_null if nil_attr == "true" || nil_attr == "1"

        # Check for self-closing marker (injected during pre-processing)
        is_self_closing = element.attributes["__odin_sc"] == "1"
        element.attributes.delete("__odin_sc") if is_self_closing

        children = element.elements.to_a
        has_text = element.texts.any? { |t| !t.value.strip.empty? }

        # Count real attributes (excluding our synthetic marker, already removed)
        real_attrs_empty = element.attributes.size == 0

        if children.empty? && real_attrs_empty
          # Self-closing <tag/> becomes null; empty <tag></tag> becomes empty string
          if is_self_closing
            return Types::DynValue.of_null
          end
          # Leaf element with only text
          text = element.text || ""
          text = text.strip
          return Types::DynValue.of_string(text)
        end

        if children.empty? && !element.attributes.empty? && !has_text
          # Only attributes, no children or text — self-closing with attrs
          fields = {}
          element.attributes.each do |name, val|
            next if name.start_with?("xmlns") || name == "xsi:nil" || name == "nil" || name == "nillable"

            fields["@#{strip_ns(name)}"] = Types::DynValue.of_string(val.to_s)
          end
          return Types::DynValue.of_object(fields) unless fields.empty?

          return Types::DynValue.of_null
        end

        # Complex element: build object
        fields = {}

        # Attributes
        element.attributes.each do |name, val|
          next if name.start_with?("xmlns") || name == "xsi:nil" || name == "nil" || name == "nillable"

          fields["@#{strip_ns(name)}"] = Types::DynValue.of_string(val.to_s)
        end

        # Text content
        if has_text && !children.empty?
          text = element.texts.map { |t| t.value }.join.strip
          fields["_text"] = Types::DynValue.of_string(text) unless text.empty?
        elsif has_text && children.empty?
          text = element.text&.strip || ""
          fields["_text"] = Types::DynValue.of_string(text) unless text.empty?
        end

        # Child elements — use qualified names (with namespace prefix) to match Java behavior
        child_counts = Hash.new(0)
        children.each { |c| child_counts[qualified_name(c)] += 1 }

        child_arrays = {}
        children.each do |child|
          name = qualified_name(child)
          child_val = parse_xml_element(child, depth + 1)

          # Elements named 'item' are always treated as arrays (matches TypeScript)
          if child_counts[name] > 1 || name == "item"
            child_arrays[name] ||= []
            child_arrays[name] << child_val
          else
            fields[name] = child_val
          end
        end

        child_arrays.each do |name, items|
          fields[name] = Types::DynValue.of_array(items)
        end

        Types::DynValue.of_object(fields)
      end

      # Get the full qualified name of an element (prefix:localName or just localName)
      def self.qualified_name(element)
        if element.prefix && !element.prefix.empty?
          "#{element.prefix}:#{element.name}"
        else
          element.name
        end
      end

      # Strip namespace prefix from element/attribute name
      def self.strip_ns(name)
        name.include?(":") ? name.split(":", 2).last : name
      end

      private_class_method :parse_csv_rows, :infer_type, :parse_flat_value,
                           :set_nested, :parse_path_segments, :wrap_nested,
                           :parse_xml_element, :strip_ns

      class FormatError < StandardError; end
    end
  end
end
