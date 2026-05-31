# frozen_string_literal: true

require "base64"

module Odin
  module Utils
    module FormatUtils
      # ─────────────────────────────────────────────────────────────────────
      # String Escaping
      # ─────────────────────────────────────────────────────────────────────

      # Escape special characters in an ODIN string.
      # Handles: \\, \", \n, \r, \t and control chars as \uXXXX.
      ESCAPE_MAP = { "\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n", "\r" => "\\r", "\t" => "\\t" }.freeze
      RE_ESCAPE = /[\\"\n\r\t\x00-\x1f]/.freeze

      def self.escape_string(value)
        value.gsub(RE_ESCAPE) do |ch|
          ESCAPE_MAP[ch] || format("\\u%04X", ch.ord)
        end
      end

      # Format a string value as quoted ODIN string.
      def self.format_quoted_string(value)
        "\"#{escape_string(value)}\""
      end

      # ─────────────────────────────────────────────────────────────────────
      # Modifier Formatting
      # ─────────────────────────────────────────────────────────────────────

      # Pre-computed modifier prefix lookup table (indexed by bit flags)
      # Bit 2 = required, bit 1 = deprecated, bit 0 = confidential
      MODIFIER_PREFIXES = ["", "*", "-", "-*", "!", "!*", "!-", "!-*"].freeze

      # Format modifier prefix in canonical order: ! (required), - (deprecated), * (confidential)
      def self.format_modifier_prefix(modifiers)
        return "" unless modifiers
        idx = 0
        idx |= 4 if modifiers.required
        idx |= 2 if modifiers.deprecated
        idx |= 1 if modifiers.confidential
        MODIFIER_PREFIXES[idx]
      end

      # ─────────────────────────────────────────────────────────────────────
      # Value Formatting (Stringify — preserves raw values)
      # ─────────────────────────────────────────────────────────────────────

      STRINGIFY_FORMATTERS = {
        Types::OdinNull => ->(v) { "~" },
        Types::OdinBoolean => ->(v) { v.value ? "?true" : "?false" },
        Types::OdinString => ->(v) { format_quoted_string(v.value) },
        Types::OdinNumber => ->(v) { v.raw ? "##{v.raw}" : "##{v.value}" },
        Types::OdinInteger => ->(v) { v.raw ? "###{v.raw}" : "###{v.value}" },
        Types::OdinCurrency => ->(v) { format_stringify_currency(v) },
        Types::OdinPercent => ->(v) { v.raw ? "#%#{v.raw}" : "#%#{v.value}" },
        Types::OdinDate => ->(v) { v.raw },
        Types::OdinTimestamp => ->(v) { v.raw },
        Types::OdinTime => ->(v) { v.value },
        Types::OdinDuration => ->(v) { v.value },
        Types::OdinReference => ->(v) { "@#{v.path}" },
        Types::OdinBinary => ->(v) { format_binary(v) },
        Types::OdinVerbExpression => ->(v) { format_verb(v) },
        Types::OdinArray => ->(_v) { "[]" },
        Types::OdinObject => ->(_v) { "{}" },
      }.freeze

      def self.format_value(value)
        formatter = STRINGIFY_FORMATTERS[value.class]
        formatter ? formatter.call(value) : value.to_s
      end

      # ─────────────────────────────────────────────────────────────────────
      # Value Formatting (Canonical — deterministic, no raw)
      # ─────────────────────────────────────────────────────────────────────

      CANONICAL_FORMATTERS = {
        Types::OdinNull => ->(v) { "~" },
        Types::OdinBoolean => ->(v) { v.value ? "true" : "false" },
        Types::OdinString => ->(v) { format_quoted_string(v.value) },
        Types::OdinNumber => ->(v) { "##{format_canonical_number(v.raw || v.value)}" },
        Types::OdinInteger => ->(v) { "###{v.raw || v.value}" },
        Types::OdinCurrency => ->(v) { format_canonical_currency(v) },
        Types::OdinPercent => ->(v) { v.raw ? "#%#{v.raw}" : "#%#{v.value}" },
        Types::OdinDate => ->(v) { v.raw },
        Types::OdinTimestamp => ->(v) { v.raw },
        Types::OdinTime => ->(v) { v.value },
        Types::OdinDuration => ->(v) { v.value },
        Types::OdinReference => ->(v) { "@#{v.path}" },
        Types::OdinBinary => ->(v) { format_binary(v) },
        Types::OdinVerbExpression => ->(v) { format_canonical_verb(v) },
        Types::OdinArray => ->(_v) { "[]" },
        Types::OdinObject => ->(_v) { "{}" },
      }.freeze

      def self.format_canonical_value(value)
        formatter = CANONICAL_FORMATTERS[value.class]
        formatter ? formatter.call(value) : value.to_s
      end

      # ─────────────────────────────────────────────────────────────────────
      # Number Formatting
      # ─────────────────────────────────────────────────────────────────────

      # Format number in canonical form: strip trailing zeros.
      # Prefers the raw string (when passed) to preserve precision beyond Float range.
      def self.format_canonical_number(value)
        s = value.is_a?(String) ? value : value.to_s
        if s.include?(".") && !s.include?("e") && !s.include?("E")
          s = s.sub(/\.?0+\z/, "")
        end
        s
      end

      # ─────────────────────────────────────────────────────────────────────
      # Currency Formatting
      # ─────────────────────────────────────────────────────────────────────

      # Stringify currency: use raw if available, else format with stored decimal places
      def self.format_stringify_currency(value)
        if value.raw
          result = +"#$#{value.raw}"
          if value.currency_code && !value.raw.include?(":")
            result << ":#{value.currency_code}"
          end
          result
        else
          dp = value.decimal_places
          formatted = format("%.#{dp}f", value.value.to_f)
          result = +"#$#{formatted}"
          result << ":#{value.currency_code}" if value.currency_code
          result
        end
      end

      # Canonical currency: always min 2 decimal places, code uppercase.
      # Prefers raw to preserve precision and integer parts beyond Float range.
      def self.format_canonical_currency(value)
        result = +"#$#{format_canonical_currency_number(value)}"
        result << ":#{value.currency_code.upcase}" if value.currency_code
        result
      end

      # Build the numeric portion of a canonical currency, at least 2 decimal places.
      def self.format_canonical_currency_number(value)
        if value.raw
          raw = value.raw
          # Defensive: drop any code suffix that leaked into raw
          raw = raw.split(":", 2)[0] if raw.include?(":")
          negative = raw.start_with?("-")
          unsigned = negative ? raw[1..] : raw
          dot = unsigned.index(".")
          int_part = dot ? unsigned[0...dot] : unsigned
          frac_part = dot ? unsigned[(dot + 1)..] : ""
          frac_part = frac_part.ljust(2, "0") if frac_part.length < 2
          "#{negative ? '-' : ''}#{int_part}.#{frac_part}"
        else
          dp = [value.decimal_places, 2].max
          format("%.#{dp}f", value.value.to_f)
        end
      end

      # ─────────────────────────────────────────────────────────────────────
      # Binary Formatting
      # ─────────────────────────────────────────────────────────────────────

      def self.format_binary(value)
        # data is stored as base64 string already
        if value.algorithm
          "^#{value.algorithm}:#{value.data}"
        else
          "^#{value.data}"
        end
      end

      # ─────────────────────────────────────────────────────────────────────
      # Verb Formatting
      # ─────────────────────────────────────────────────────────────────────

      def self.format_verb(value)
        prefix = value.is_custom ? "%&" : "%"
        result = +"#{prefix}#{value.verb}"
        value.args.each do |arg|
          result << " "
          result << format_value(arg)
        end
        result
      end

      def self.format_canonical_verb(value)
        prefix = value.is_custom ? "%&" : "%"
        result = +"#{prefix}#{value.verb}"
        value.args.each do |arg|
          result << " "
          result << format_canonical_value(arg)
        end
        result
      end
    end
  end
end
