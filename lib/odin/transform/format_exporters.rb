# frozen_string_literal: true

require "json"
require "bigdecimal"
require "set"

module Odin
  module Transform
    module FormatExporters
      # ── JSON Export ──

      def self.to_json(value, pretty: true, indent: 2, nulls: nil, empty_arrays: nil)
        ruby_obj = dynvalue_to_json_obj(value)
        ruby_obj = omit_nulls(ruby_obj) if nulls == "omit"
        ruby_obj = omit_empty_arrays(ruby_obj) if empty_arrays == "omit"
        if indent == 0
          JSON.generate(ruby_obj)
        elsif pretty
          JSON.pretty_generate(ruby_obj, indent: " " * indent)
        else
          JSON.generate(ruby_obj)
        end
      end

      def self.omit_nulls(obj)
        case obj
        when Hash
          obj.each_with_object({}) do |(k, v), h|
            next if v.nil?
            h[k] = omit_nulls(v)
          end
        when Array
          obj.map { |item| omit_nulls(item) }
        else
          obj
        end
      end

      def self.omit_empty_arrays(obj)
        case obj
        when Hash
          obj.each_with_object({}) do |(k, v), h|
            next if v.is_a?(Array) && v.empty?
            h[k] = omit_empty_arrays(v)
          end
        when Array
          obj.map { |item| omit_empty_arrays(item) }
        else
          obj
        end
      end

      # ── XML Export ──

      def self.to_xml(value, root: "root", declaration: true, indent: 2)
        xml = +""
        xml << %{<?xml version="1.0" encoding="UTF-8"?>\n} if declaration
        indent_str = " " * indent
        include_ns = needs_odin_namespace?(value)
        ns_attr = include_ns ? ' xmlns:odin="https://odin.foundation/ns"' : ""
        if value.object?
          # If the object has exactly one key, use that as root
          keys = value.value.keys
          if keys.size == 1 && value.value[keys[0]].object?
            xml << render_xml_element(keys[0], value.value[keys[0]], 0, indent_str: indent_str, include_ns: include_ns, is_root: true)
          else
            xml << "<#{root}#{ns_attr}>\n"
            value.value.each do |k, v|
              xml << render_xml_element(k, v, 1, indent_str: indent_str, include_ns: include_ns)
            end
            xml << "</#{root}>\n"
          end
        elsif value.array?
          xml << "<#{root}#{ns_attr}>\n"
          value.value.each do |item|
            xml << render_xml_element("item", item, 1, indent_str: indent_str, include_ns: include_ns)
          end
          xml << "</#{root}>\n"
        else
          type_attr = include_ns ? dv_xml_type_attr(value) : ""
          xml << "<#{root}#{ns_attr}#{type_attr}>#{xml_escape(dynvalue_to_string(value))}</#{root}>\n"
        end
        xml
      end

      # ── CSV Export ──

      def self.to_csv(value, delimiter: ",", header: true)
        return "" unless value.array?

        items = value.value
        return "" if items.empty?

        # Collect all column names from all rows
        columns = []
        items.each do |item|
          next unless item.object?

          item.value.each_key do |k|
            columns << k unless columns.include?(k)
          end
        end

        return "" if columns.empty?

        lines = []
        # Header row (unless suppressed)
        if header
          lines << columns.map { |c| csv_escape(c, delimiter) }.join(delimiter)
        end

        # Data rows
        items.each do |item|
          next unless item.object?

          row = columns.map do |col|
            v = item.value[col]
            v ? csv_escape(dynvalue_to_string(v), delimiter) : ""
          end
          lines << row.join(delimiter)
        end

        lines.join("\n") + "\n"
      end

      # ── Fixed-Width Export ──

      def self.to_fixed_width(value, columns:, line_width: nil)
        rows = if value.array?
                 value.value
               else
                 [value]
               end

        total_width = line_width || columns.map { |c| (c[:pos] || 0) + (c[:len] || 0) }.max || 80

        lines = rows.map do |row|
          line = " " * total_width
          columns.each do |col|
            pos = col[:pos] || 0
            len = col[:len] || 0
            pad_char = col[:pad] || " "
            align = col[:align] || :left
            name = col[:name]

            raw_val = if row.object?
                        v = row.value[name]
                        v ? dynvalue_to_string(v) : ""
                      else
                        ""
                      end

            # Truncate if needed
            raw_val = raw_val[0...len] if raw_val.length > len

            padded = if align == :right
                       raw_val.rjust(len, pad_char)
                     else
                       raw_val.ljust(len, pad_char)
                     end

            # Write into line at position
            padded.chars.each_with_index do |ch, i|
              line[pos + i] = ch if pos + i < total_width
            end
          end
          line.rstrip
        end

        lines.join("\n") + "\n"
      end

      # ── ODIN Export ──

      def self.to_odin(value, header: true, modifiers: {})
        sb = +""

        if header
          sb << "{$}\n"
          sb << "odin = \"1.0.0\"\n"
        end

        if value.object?
          entries = value.value
          has_sections = entries.any? { |_k, v| v.object? || v.array? }

          if has_sections
            # Check if there are any top-level fields (non-section entries or leaf chains)
            has_top_level = entries.any? { |_k, v| !v.object? && !v.array? } ||
                           entries.any? { |_k, v| v.object? && pure_leaf_chain?(v) }

            # Emit {} root section marker when header is present and there are top-level fields
            sb << "{}\n" if header && has_top_level

            # First pass: flat top-level fields and leaf chains
            entries.each do |key, val|
              if val.object?
                collect_leaf_paths(sb, key, val, key, modifiers)
              elsif !val.array?
                write_assignment(sb, key, val, key, modifiers)
              end
            end

            # Second pass: sections and arrays
            last_ctx = +""
            entries.each do |key, val|
              if val.object? && !pure_leaf_chain?(val)
                write_section(sb, key, key, nil, val, modifiers, last_ctx_holder = [last_ctx])
                last_ctx = last_ctx_holder[0]
              elsif val.array?
                write_array_section(sb, key, nil, val.value, modifiers)
                last_ctx = ""
              end
            end
          else
            entries.each do |key, val|
              write_assignment(sb, key, val, key, modifiers)
            end
          end
        elsif value.array?
          sb << "items = #{format_odin_value(value)}\n"
        else
          sb << "value = #{format_odin_value(value)}\n"
        end

        sb
      end

      # ── Flat KVP Export ──

      def self.to_flat_kvp(value)
        return "" unless value.object?

        lines = []
        flatten_for_kvp(value.value, "", lines)
        lines.sort!
        lines.join("\n") + "\n"
      end

      # ── Flat YAML Export ──

      def self.to_flat_yaml(value)
        return "" unless value.object?

        sb = +""
        # Sort top-level keys alphabetically
        sorted_keys = value.value.keys.sort
        sorted_keys.each do |key|
          val = value.value[key]
          write_yaml_value(sb, key, val, 0)
        end
        sb
      end

      def self.write_yaml_value(sb, key, val, indent)
        prefix = "  " * indent
        case val.type
        when :object
          sb << "#{prefix}#{key}:\n"
          val.value.keys.sort.each do |k|
            write_yaml_value(sb, k, val.value[k], indent + 1)
          end
        when :array
          sb << "#{prefix}#{key}:\n"
          val.value.each do |item|
            if item.object?
              first = true
              item.value.keys.sort.each do |k|
                if first
                  sb << "#{prefix}  - #{k}: #{format_yaml_scalar(item.value[k])}\n"
                  first = false
                else
                  sb << "#{prefix}    #{k}: #{format_yaml_scalar(item.value[k])}\n"
                end
              end
            else
              sb << "#{prefix}  - #{format_yaml_scalar(item)}\n"
            end
          end
        else
          sb << "#{prefix}#{key}: #{format_yaml_scalar(val)}\n"
        end
      end

      def self.format_yaml_scalar(dv)
        case dv.type
        when :null then "~"
        when :bool then "\"#{dv.value}\""
        when :integer then dv.value.to_s
        when :float
          v = dv.value
          v == v.to_i.to_f && v.abs < 1e15 ? v.to_i.to_s : v.to_s
        when :currency
          v = dv.value.is_a?(BigDecimal) ? dv.value.to_f : dv.value.to_f
          v == v.to_i && v.abs < 1e15 ? v.to_i.to_s : v.to_s
        when :string
          yaml_needs_quoting?(dv.value) ? "\"#{dv.value}\"" : dv.value
        when :date, :timestamp, :time, :duration
          dv.value.to_s
        else
          dv.value.to_s
        end
      end

      def self.yaml_needs_quoting?(s)
        return true if s =~ /\A(true|false|yes|no|on|off|null|~)\z/i
        return true if s.include?(":") || s.include?("#") || s.include?("&")
        return true if s.include?("'") || s.include?("\"")
        return true if s.include?("[") || s.include?("]") || s.include?("{") || s.include?("}")
        return true if s.start_with?(" ") || s.end_with?(" ")
        return true if s.empty?
        false
      end

      # ── Private Helpers ──

      def self.dynvalue_to_json_obj(dv)
        case dv.type
        when :null then nil
        when :bool then dv.value
        when :integer then dv.value
        when :float then dv.value
        when :float_raw then dv.value.to_f
        when :string then dv.value
        when :currency
          f = dv.value.is_a?(BigDecimal) ? dv.value.to_f : dv.value.to_f
          f == f.to_i && f.abs < 1e15 ? f.to_i : f
        when :currency_raw then dv.value.to_f
        when :percent then dv.value
        when :date, :timestamp, :time, :duration then dv.value.to_s
        when :reference then "@#{dv.value}"
        when :binary then "^#{dv.value}"
        when :array then dv.value.map { |item| dynvalue_to_json_obj(item) }
        when :object then dv.value.transform_values { |v| dynvalue_to_json_obj(v) }
        else dv.value
        end
      end

      def self.dynvalue_to_string(dv)
        case dv.type
        when :null then ""
        when :bool then dv.value.to_s
        when :integer then dv.value.to_s
        when :float then format_number(dv.value)
        when :float_raw then dv.value.to_s
        when :string then dv.value
        when :currency
          v = dv.value.is_a?(BigDecimal) ? dv.value.to_f : dv.value.to_f
          v == v.to_i && v.abs < 1e15 ? v.to_i.to_s : v.to_s
        when :currency_raw then dv.value.to_s
        when :percent then format_number(dv.value)
        when :date, :timestamp, :time, :duration then dv.value.to_s
        when :reference then dv.value.to_s
        when :binary then dv.value.to_s
        else dv.value.to_s
        end
      end

      def self.format_number(v)
        return v.to_i.to_s if v == v.to_i && v.abs < 1e15

        s = v.to_s
        # Normalize scientific notation
        if s.include?("e") || s.include?("E")
          s.downcase.sub(/\+/, "")
        else
          s
        end
      end

      # ── ODIN formatting helpers ──

      # Section writing (matches Java OdinFormatter.writeSection)
      def self.write_section(sb, full_path, display_path, parent_section, val, modifiers, last_ctx, inside_relative: false)
        entries = val.value
        return unless entries.is_a?(Hash)

        is_relative = display_path.start_with?(".")
        sb << "{#{display_path}}\n"
        last_ctx[0] = full_path

        # First: scalar fields and leaf chains
        entries.each do |key, child|
          child_full = "#{full_path}.#{key}"
          if child.object? && pure_leaf_chain?(child)
            collect_leaf_paths_inner(sb, key, child, child_full, modifiers)
          elsif !child.object? && !child.array?
            write_assignment(sb, key, child, child_full, modifiers)
          end
        end

        # Second: arrays
        entries.each do |key, child|
          if child.array?
            write_array_section(sb, key, full_path, child.value, modifiers)
            last_ctx[0] = full_path
          end
        end

        # Third: nested objects (non-leaf-chain)
        entries.each do |key, child|
          if child.object? && !pure_leaf_chain?(child)
            child_full = "#{full_path}.#{key}"
            # Only use relative path when NOT inside a relative context AND lastCtx matches
            child_display = if !is_relative && !inside_relative && last_ctx[0] == full_path
                              ".#{key}"
                            else
                              child_full
                            end
            write_section(sb, child_full, child_display, full_path, child, modifiers, last_ctx,
                          inside_relative: is_relative || inside_relative)
            last_ctx[0] = full_path
          end
        end
      end

      # Array section writing (matches Java OdinFormatter.writeArraySection)
      def self.write_array_section(sb, name, parent_section, items, modifiers)
        prefix = parent_section ? "." : ""

        if items.empty?
          sb << "{#{prefix}#{name}[] : ~}\n~\n"
          return
        end

        all_scalar = items.all? { |item| !item.object? && !item.array? }

        if all_scalar
          sb << "{#{prefix}#{name}[] : ~}\n"
          items.each { |item| sb << "#{format_odin_value(item)}\n" }
          return
        end

        # Check for consistent columns (tabular)
        columns = get_consistent_columns(items)
        if columns && !columns.empty?
          display_cols = abbreviate_column_names(columns)
          sb << "{#{prefix}#{name}[] : #{display_cols.join(', ')}}\n"
          items.each do |item|
            next unless item.object?
            row = columns.map { |col| resolve_column_value(item, col) }
            sb << "#{row.join(', ')}\n"
          end
          return
        end

        # Fallback: indexed notation
        sb << "{#{name}[]}\n"
        items.each_with_index do |item, i|
          sb << "{---}\n" if i > 0
          if item.object?
            item.value.each { |k, v| sb << "#{k} = #{format_odin_value(v)}\n" }
          end
        end
      end

      # Check if all array items are objects with same scalar fields
      def self.get_consistent_columns(items)
        all_columns = []
        column_set = Set.new

        items.each do |item|
          return nil unless item.object?
          item_cols = []
          return nil unless collect_flat_columns(item.value, "", item_cols)
          item_cols.each do |col|
            if column_set.add?(col)
              all_columns << col
            end
          end
        end

        all_columns.empty? ? nil : all_columns
      end

      # Recursively collect flat column names from an object, handling one level of nesting
      def self.collect_flat_columns(obj, prefix, columns)
        obj.each do |key, val|
          col_name = prefix.empty? ? key : "#{prefix}.#{key}"
          if val.object?
            return false if val.array?
            return false unless prefix.empty? # No multi-level nesting in tabular
            return false unless collect_flat_columns(val.value, key, columns)
          elsif val.array?
            return false
          else
            columns << col_name
          end
        end
        true
      end

      # Resolve a column value from an item, handling dot-paths for nested objects
      def self.resolve_column_value(item, col)
        if col.include?(".")
          parts = col.split(".")
          current = item
          parts.each do |part|
            return "" unless current&.object?
            current = current.get(part)
          end
          current ? format_odin_value(current) : ""
        else
          val = item.value[col]
          val ? format_odin_value(val) : ""
        end
      end

      # Abbreviate column names: name.first, name.last -> name.first, .last
      def self.abbreviate_column_names(columns)
        result = []
        prev_prefix = nil
        columns.each do |col|
          if col.include?(".")
            parts = col.rpartition(".")
            prefix = parts[0]  # everything before last dot
            suffix = parts[2]  # everything after last dot
            if prefix == prev_prefix
              result << ".#{suffix}"
            else
              result << col
              prev_prefix = prefix
            end
          else
            result << col
            prev_prefix = nil
          end
        end
        result
      end

      # Leaf chain detection (matches Java isPureLeafChain)
      def self.pure_leaf_chain?(val)
        return false unless val.object?
        entries = val.value
        return false unless entries.size == 1
        child = entries.values.first
        return pure_leaf_chain?(child) if child.object?
        return false if child.array?
        true
      end

      # Collect leaf paths for flat nested objects (matches Java collectLeafPaths)
      def self.collect_leaf_paths(sb, prefix, val, mod_path, modifiers)
        return unless pure_leaf_chain?(val)
        collect_leaf_paths_inner(sb, prefix, val, mod_path, modifiers)
      end

      def self.collect_leaf_paths_inner(sb, prefix, val, mod_path, modifiers)
        if val.object?
          val.value.each do |key, child|
            path = "#{prefix}.#{key}"
            mp = "#{mod_path}.#{key}"
            if child.object?
              collect_leaf_paths_inner(sb, path, child, mp, modifiers)
            else
              write_assignment(sb, path, child, mp, modifiers)
            end
          end
        else
          write_assignment(sb, prefix, val, mod_path, modifiers)
        end
      end

      # Write an assignment line with modifier prefix
      def self.write_assignment(sb, key, value, full_path, modifiers)
        mod_prefix = modifier_prefix_for_path(full_path, modifiers)
        sb << "#{key} = #{mod_prefix}#{format_odin_value(value)}\n"
      end

      def self.modifier_prefix_for_path(path, modifiers)
        return "" if modifiers.nil? || !modifiers.key?(path)
        mods = modifiers[path]
        return "" if mods.nil? || mods.empty?
        prefix = +""
        if mods.is_a?(Array)
          prefix << "!" if mods.include?(:required) || mods.include?(Odin::Transform::FieldModifier::REQUIRED)
          prefix << "-" if mods.include?(:deprecated) || mods.include?(Odin::Transform::FieldModifier::DEPRECATED)
          prefix << "*" if mods.include?(:confidential) || mods.include?(Odin::Transform::FieldModifier::CONFIDENTIAL)
        elsif mods.is_a?(Hash)
          prefix << "!" if mods[:required]
          prefix << "-" if mods[:deprecated]
          prefix << "*" if mods[:confidential]
        end
        prefix
      end

      def self.format_odin_value(dv)
        case dv.type
        when :null then "~"
        when :bool then "?#{dv.value}"
        when :integer then "###{dv.value}"
        when :float
          v = dv.value
          if v == v.to_i.to_f && v.abs < 1e15
            "##{v.to_i}"
          else
            "##{format_double(v)}"
          end
        when :float_raw then "##{dv.value}"
        when :string then "\"#{escape_odin_string(dv.value)}\""
        when :currency
          v = dv.value.to_f
          dp = dv.decimal_places || 2
          formatted = format("%.#{dp}f", v)
          code = dv.currency_code
          code ? "#$#{formatted}:#{code}" : "#$#{formatted}"
        when :currency_raw
          code = dv.currency_code
          code ? "#$#{dv.value}:#{code}" : "#$#{dv.value}"
        when :percent
          v = dv.value
          if v == v.to_i.to_f && v.abs < 1e15
            "#%#{v.to_i}.0"
          else
            "#%#{v}"
          end
        when :date then dv.value.to_s
        when :timestamp then dv.value.to_s
        when :time
          t = dv.value.to_s
          t.start_with?("T") ? t : "T#{t}"
        when :duration then dv.value.to_s
        when :reference then "@#{dv.value}"
        when :binary then "^#{dv.value}"
        when :array
          "[#{dv.value.map { |item| format_odin_value(item) }.join(', ')}]"
        when :object then "{object}"
        else "\"#{dv.value}\""
        end
      end

      def self.format_double(v)
        s = v.to_s
        # Normalize scientific notation: 6.022e+23
        if s.include?("e") || s.include?("E")
          s.downcase.gsub(/e(\d)/, 'e+\1')
        else
          s
        end
      end

      def self.format_modifier_prefix(mods)
        return "" if mods.nil? || mods.empty?

        prefix = +""
        prefix << "!" if mods[:required]
        prefix << "-" if mods[:deprecated]
        prefix << "*" if mods[:confidential]
        prefix
      end

      def self.escape_odin_string(s)
        s.gsub("\\", "\\\\\\\\")
         .gsub('"', '\\"')
         .gsub("\n", "\\n")
         .gsub("\r", "\\r")
         .gsub("\t", "\\t")
      end

      # ── XML helpers ──

      def self.render_xml_element(name, dv, depth, indent_str: "  ", include_ns: false, is_root: false)
        indent = indent_str * depth
        safe_name = sanitize_xml_name(name)
        ns_attr = is_root && include_ns ? ' xmlns:odin="https://odin.foundation/ns"' : ""

        case dv.type
        when :null
          type_attr = include_ns ? ' odin:type="null"' : ""
          "#{indent}<#{safe_name}#{ns_attr}#{type_attr}></#{safe_name}>\n"
        when :array
          dv.value.map { |item| render_xml_element(safe_name, item, depth, indent_str: indent_str, include_ns: include_ns) }.join
        when :object
          # Collect :attr children (children whose DynValue has attr modifier info)
          attr_parts = []
          child_entries = []
          dv.value.each do |k, v|
            child_entries << [k, v]
          end

          inner = +""
          child_entries.each do |k, v|
            inner << render_xml_element(k, v, depth + 1, indent_str: indent_str, include_ns: include_ns)
          end
          "#{indent}<#{safe_name}#{ns_attr}>\n#{inner}#{indent}</#{safe_name}>\n"
        else
          type_attr = include_ns ? dv_xml_type_attr(dv) : ""
          "#{indent}<#{safe_name}#{ns_attr}#{type_attr}>#{xml_escape(dynvalue_to_string(dv))}</#{safe_name}>\n"
        end
      end

      # Check if a DynValue tree contains any typed (non-string) values
      def self.needs_odin_namespace?(dv)
        case dv.type
        when :string then false
        when :null then false
        when :object
          dv.value.any? { |_k, v| needs_odin_namespace_inner?(v) }
        when :array
          dv.value.any? { |v| needs_odin_namespace_inner?(v) }
        else
          true # non-string scalar types need namespace
        end
      end

      # Inner recursive check for namespace need
      def self.needs_odin_namespace_inner?(dv)
        case dv.type
        when :string then false
        when :null then true
        when :object
          dv.value.any? { |_k, v| needs_odin_namespace_inner?(v) }
        when :array
          dv.value.any? { |v| needs_odin_namespace_inner?(v) }
        else
          true # bool, integer, float, currency, etc.
        end
      end

      # Return odin:type attribute string for a DynValue
      def self.dv_xml_type_attr(dv)
        case dv.type
        when :null then ' odin:type="null"'
        when :bool then ' odin:type="boolean"'
        when :integer then ' odin:type="integer"'
        when :float, :float_raw then ' odin:type="number"'
        when :currency, :currency_raw then ' odin:type="currency"'
        when :percent then ' odin:type="percent"'
        when :date then ' odin:type="date"'
        when :timestamp then ' odin:type="timestamp"'
        when :time then ' odin:type="time"'
        when :duration then ' odin:type="duration"'
        when :reference then ' odin:type="reference"'
        when :binary then ' odin:type="binary"'
        else ""
        end
      end

      def self.sanitize_xml_name(name)
        name = name.gsub(/[^a-zA-Z0-9._-]/, "_")
        name = "_#{name}" if name.match?(/\A\d/)
        name = "element" if name.empty?
        name
      end

      def self.xml_escape(s)
        s.gsub("&", "&amp;")
         .gsub("<", "&lt;")
         .gsub(">", "&gt;")
         .gsub('"', "&quot;")
         .gsub("'", "&apos;")
      end

      # ── CSV helpers ──

      def self.csv_escape(s, delimiter = ",")
        if s.include?(delimiter) || s.include?('"') || s.include?("\n") || s.include?("\r")
          '"' + s.gsub('"', '""') + '"'
        else
          s
        end
      end

      # ── Flat KVP helpers ──

      def self.flatten_for_kvp(fields, prefix, lines)
        fields.each do |key, val|
          full_key = prefix.empty? ? key : "#{prefix}.#{key}"
          case val.type
          when :object
            flatten_for_kvp(val.value, full_key, lines)
          when :array
            val.value.each_with_index do |item, i|
              item_key = "#{full_key}[#{i}]"
              if item.object?
                flatten_for_kvp(item.value, item_key, lines)
              else
                lines << "#{item_key}=#{format_flat_value(item)}"
              end
            end
          else
            lines << "#{full_key}=#{format_flat_value(val)}"
          end
        end
      end

      def self.format_flat_value(dv)
        case dv.type
        when :null then ""
        when :bool then dv.value.to_s
        when :string then dv.value
        when :integer then dv.value.to_s
        when :float
          v = dv.value
          v == v.to_i.to_f && v.abs < 1e15 ? v.to_i.to_s : v.to_s
        when :currency
          v = dv.value.is_a?(BigDecimal) ? dv.value.to_f : dv.value.to_f
          v == v.to_i && v.abs < 1e15 ? v.to_i.to_s : v.to_s
        else dynvalue_to_string(dv)
        end
      end

      private_class_method :dynvalue_to_json_obj, :dynvalue_to_string, :format_number,
                           :format_odin_value, :format_double,
                           :write_section, :write_array_section, :write_assignment,
                           :pure_leaf_chain?, :collect_leaf_paths, :collect_leaf_paths_inner,
                           :get_consistent_columns, :collect_flat_columns,
                           :resolve_column_value, :modifier_prefix_for_path,
                           :escape_odin_string, :render_xml_element, :sanitize_xml_name,
                           :xml_escape, :csv_escape, :flatten_for_kvp, :format_flat_value,
                           :abbreviate_column_names,
                           :write_yaml_value, :format_yaml_scalar, :yaml_needs_quoting?,
                           :omit_nulls, :omit_empty_arrays,
                           :needs_odin_namespace?, :needs_odin_namespace_inner?,
                           :dv_xml_type_attr
    end
  end
end
