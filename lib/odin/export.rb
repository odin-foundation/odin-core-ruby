# frozen_string_literal: true

require "json"
require "bigdecimal"

module Odin
  module Export
    # Convert OdinDocument to JSON string
    def self.to_json(doc, pretty: true)
      obj = doc_to_json_obj(doc)
      if pretty
        JSON.pretty_generate(obj)
      else
        JSON.generate(obj)
      end
    end

    # Convert OdinDocument to XML string
    def self.to_xml(doc, root: "root", preserve_types: false, preserve_modifiers: false)
      # When preserving modifiers, always preserve types too (matches Java behavior)
      preserve_types = true if preserve_modifiers

      xml = +%{<?xml version="1.0" encoding="UTF-8"?>\n}

      ns = ""
      if preserve_types || preserve_modifiers
        ns = ' xmlns:odin="https://odin.foundation/ns"'
      end

      xml << "<#{root}#{ns}>\n"
      emit_xml_assignments(doc, xml, 1, preserve_types, preserve_modifiers)
      xml << "</#{root}>\n"
      xml
    end

    # Convert OdinDocument to CSV string
    def self.to_csv(doc)
      # Find array pattern: path[index].field
      array_pattern = /\A(.+?)\[(\d+)\]\.(.+)\z/
      rows = {}
      columns = []

      doc.each_assignment do |path, value|
        m = array_pattern.match(path)
        next unless m

        idx = m[2].to_i
        field = m[3]
        rows[idx] ||= {}
        rows[idx][field] = value
        columns << field unless columns.include?(field)
      end

      return "" if rows.empty? || columns.empty?

      lines = []
      lines << columns.map { |c| csv_escape(c) }.join(",")

      rows.keys.sort.each do |idx|
        row = rows[idx]
        cells = columns.map do |col|
          val = row[col]
          val ? csv_escape(odin_value_to_string(val)) : ""
        end
        lines << cells.join(",")
      end

      lines.join("\n") + "\n"
    end

    # Convert OdinDocument to fixed-width string
    def self.to_fixed_width(doc, columns:, line_width: nil)
      total_width = line_width || columns.map { |c| (c[:pos] || 0) + (c[:len] || 0) }.max || 80

      line = " " * total_width
      columns.each do |col|
        pos = col[:pos] || 0
        len = col[:len] || 0
        pad_char = col[:pad] || " "
        align = col[:align] || :left
        field_path = col[:path] || col[:name]

        val = doc.get(field_path)
        raw = val ? odin_value_to_string(val) : ""
        raw = raw[0...len] if raw.length > len

        padded = if align == :right
                   raw.rjust(len, pad_char)
                 else
                   raw.ljust(len, pad_char)
                 end

        padded.chars.each_with_index do |ch, i|
          line[pos + i] = ch if pos + i < total_width
        end
      end

      line.rstrip + "\n"
    end

    # ── Private Helpers ──

    def self.doc_to_json_obj(doc)
      result = {}
      # Build nested structure from flat path assignments
      doc.each_assignment do |path, value|
        set_nested_json(result, path, odin_value_to_json(value))
      end

      # Include metadata header as "$" key
      meta = {}
      doc.each_metadata do |key, value|
        meta[key] = odin_value_to_json(value)
      end
      result["$"] = meta unless meta.empty?

      result
    end

    def self.set_nested_json(root, path, value)
      segments = parse_path(path)
      current = root

      segments[0...-1].each_with_index do |seg, idx|
        next_seg = segments[idx + 1]
        if seg.is_a?(Integer)
          current[seg] ||= next_seg.is_a?(Integer) ? [] : {}
          current = current[seg]
        else
          if next_seg.is_a?(Integer)
            current[seg] ||= []
          else
            current[seg] ||= {}
          end
          current = current[seg]
        end
      end

      last = segments.last
      current[last] = value
    end

    def self.parse_path(path)
      segments = []
      # Split on dots but handle bracket notation
      parts = path.split(".")
      parts.each do |part|
        if part.include?("[")
          # e.g., "items[0]" -> "items", 0
          part.scan(/([^\[\]]+)|\[(\d+)\]/) do |name, index|
            if index
              segments << index.to_i
            else
              segments << name
            end
          end
        else
          segments << part
        end
      end
      segments
    end

    def self.odin_value_to_json(val)
      case val
      when Types::OdinNull then nil
      when Types::OdinBoolean then val.value
      when Types::OdinString then val.value
      when Types::OdinInteger then val.value
      when Types::OdinNumber then val.value
      when Types::OdinCurrency
        f = val.value.to_f
        f == f.to_i && f.abs < 1e15 ? f.to_i : f
      when Types::OdinPercent then val.value
      when Types::OdinDate then val.raw || val.value.to_s
      when Types::OdinTimestamp then val.raw || val.value.to_s
      when Types::OdinTime then val.value
      when Types::OdinDuration then val.value
      when Types::OdinReference then "@#{val.path}"
      when Types::OdinBinary
        val.algorithm ? "^#{val.algorithm}:#{val.data}" : "^#{val.data}"
      when Types::OdinArray
        val.items.map { |item|
          item.is_a?(Types::ArrayItem) ? odin_value_to_json(item.value) : odin_value_to_json(item)
        }
      when Types::OdinObject
        val.entries.transform_values { |v| odin_value_to_json(v) }
      else
        val.respond_to?(:value) ? val.value : nil
      end
    end

    def self.odin_value_to_string(val)
      case val
      when Types::OdinNull then ""
      when Types::OdinBoolean then val.value.to_s
      when Types::OdinString then val.value
      when Types::OdinInteger then (val.raw || val.value.to_s)
      when Types::OdinNumber then (val.raw || format_num(val.value))
      when Types::OdinCurrency
        val.raw || val.value.to_s("F")
      when Types::OdinPercent then (val.raw || format_num(val.value))
      when Types::OdinDate then val.raw || val.value.to_s
      when Types::OdinTimestamp then val.raw || val.value.to_s
      when Types::OdinTime then val.value
      when Types::OdinDuration then val.value
      when Types::OdinReference then "@#{val.path}"
      when Types::OdinBinary
        val.algorithm ? "^#{val.algorithm}:#{val.data}" : "^#{val.data}"
      else
        val.respond_to?(:value) ? val.value.to_s : ""
      end
    end

    def self.format_num(v)
      v == v.to_i && v.abs < 1e15 ? v.to_i.to_s : v.to_s
    end

    def self.emit_xml_assignments(doc, xml, depth, preserve_types, preserve_modifiers)
      indent = "  " * depth

      # Group assignments by top-level section
      sections = {}
      doc.each_assignment do |path, value|
        parts = path.split(".", 2)
        section = parts[0]
        remainder = parts[1]

        sections[section] ||= []
        sections[section] << [remainder, value, path]
      end

      sections.each do |section, entries|
        if entries.size == 1 && entries[0][0].nil?
          # Simple field
          _, value, full_path = entries[0]
          emit_xml_value(xml, section, value, full_path, doc, indent, depth,
                         preserve_types, preserve_modifiers)
        else
          # Nested section
          xml << "#{indent}<#{sanitize_xml_name(section)}>\n"
          entries.each do |remainder, value, full_path|
            if remainder
              emit_xml_value(xml, remainder.split(".").last, value, full_path, doc,
                             "  " * (depth + 1), depth + 1, preserve_types, preserve_modifiers)
            else
              emit_xml_value(xml, section, value, full_path, doc, "  " * (depth + 1),
                             depth + 1, preserve_types, preserve_modifiers)
            end
          end
          xml << "#{indent}</#{sanitize_xml_name(section)}>\n"
        end
      end
    end

    def self.emit_xml_value(xml, name, value, full_path, doc, indent, _depth,
                            preserve_types, preserve_modifiers)
      safe_name = sanitize_xml_name(name)
      attrs = +""

      if preserve_types
        type_name = xml_type_name(value)
        attrs << " odin:type=\"#{type_name}\"" if type_name
        if value.is_a?(Types::OdinCurrency) && value.currency_code
          attrs << " odin:currencyCode=\"#{value.currency_code}\""
        end
      end

      if preserve_modifiers
        mods = value.modifiers || doc.modifiers_for(full_path)
        if mods
          attrs << ' odin:required="true"' if mods.required
          attrs << ' odin:confidential="true"' if mods.confidential
          attrs << ' odin:deprecated="true"' if mods.deprecated
        end
      end

      # Skip null values in XML output (omit them entirely)
      return if value.is_a?(Types::OdinNull)

      text = xml_escape(odin_value_to_string(value))
      xml << "#{indent}<#{safe_name}#{attrs}>#{text}</#{safe_name}>\n"
    end

    def self.xml_type_name(value)
      case value
      when Types::OdinInteger then "integer"
      when Types::OdinNumber then "number"
      when Types::OdinCurrency then "currency"
      when Types::OdinPercent then "percent"
      when Types::OdinBoolean then "boolean"
      when Types::OdinDate then "date"
      when Types::OdinTimestamp then "timestamp"
      when Types::OdinTime then "time"
      when Types::OdinDuration then "duration"
      when Types::OdinReference then "reference"
      when Types::OdinBinary then "binary"
      else nil # string and null don't need type attr
      end
    end

    def self.sanitize_xml_name(name)
      name = name.to_s.gsub(/[^a-zA-Z0-9._-]/, "_")
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

    def self.csv_escape(s)
      if s.include?(",") || s.include?('"') || s.include?("\n") || s.include?("\r")
        '"' + s.gsub('"', '""') + '"'
      else
        s
      end
    end

    private_class_method :doc_to_json_obj, :set_nested_json, :parse_path,
                         :odin_value_to_json, :odin_value_to_string, :format_num,
                         :emit_xml_assignments, :emit_xml_value, :xml_type_name,
                         :sanitize_xml_name, :xml_escape, :csv_escape
  end
end
