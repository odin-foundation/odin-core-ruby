# frozen_string_literal: true

require "bigdecimal"
require "date"
require "base64"

module Odin
  module Parsing
    module ValueParser
      module_function

      def parse_value(token)
        case token.type
        when TokenType::STRING    then Types::OdinString.new(token.value)
        when TokenType::NUMBER    then parse_number(token)
        when TokenType::INTEGER   then parse_integer(token)
        when TokenType::CURRENCY  then parse_currency(token)
        when TokenType::PERCENT   then parse_percent(token)
        when TokenType::BOOLEAN   then parse_boolean(token)
        when TokenType::NULL      then Types::NULL
        when TokenType::DATE      then parse_date(token)
        when TokenType::TIMESTAMP then parse_timestamp(token)
        when TokenType::TIME      then parse_time(token)
        when TokenType::DURATION  then parse_duration(token)
        when TokenType::REFERENCE then Types::OdinReference.new(token.value)
        when TokenType::BINARY    then parse_binary(token)
        when TokenType::VERB      then parse_verb_name(token)
        else
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::UNEXPECTED_CHARACTER,
            token.line, token.column,
            "Unexpected token type: #{token.type}"
          )
        end
      end

      def parse_number(token)
        raw = token.value
        if raw.nil? || raw.empty?
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::INVALID_TYPE_PREFIX,
            token.line, token.column,
            "Invalid numeric format"
          )
        end
        val = Float(raw)
        # Store raw if high precision (> 15 significant digits)
        store_raw = raw.length > 15 || needs_raw?(raw, val)
        Types::OdinNumber.new(val, raw: store_raw ? raw : nil)
      rescue ArgumentError
        raise Errors::ParseError.new(
          Errors::ParseErrorCode::INVALID_TYPE_PREFIX,
          token.line, token.column,
          "Invalid numeric format: #{raw}"
        )
      end

      def parse_integer(token)
        raw = token.value
        if raw.nil? || raw.empty?
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::INVALID_TYPE_PREFIX,
            token.line, token.column,
            "Invalid numeric format"
          )
        end
        val = Integer(Float(raw))
        # Beyond JS safe integer range, store raw
        safe = val.abs <= 9_007_199_254_740_991
        Types::OdinInteger.new(val, raw: safe && raw.length <= 15 ? nil : raw)
      rescue ArgumentError
        raise Errors::ParseError.new(
          Errors::ParseErrorCode::INVALID_TYPE_PREFIX,
          token.line, token.column,
          "Invalid integer format: #{raw}"
        )
      end

      def parse_currency(token)
        raw = token.value
        if raw.nil? || raw.empty?
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::INVALID_TYPE_PREFIX,
            token.line, token.column,
            "Invalid numeric format"
          )
        end

        currency_code = nil
        numeric_part = raw

        if raw.include?(":")
          parts = raw.split(":", 2)
          numeric_part = parts[0]
          currency_code = parts[1].upcase unless parts[1].empty?
        end

        bd = BigDecimal(numeric_part)
        # Count decimal places
        if numeric_part.include?(".")
          e_pos = numeric_part.downcase.index("e")
          check_part = e_pos ? numeric_part[0...e_pos] : numeric_part
          decimal_str = check_part.split(".")[1] || ""
          dp = [decimal_str.length, 2].max
        else
          dp = 2
        end

        Types::OdinCurrency.new(bd, currency_code: currency_code, decimal_places: dp, raw: numeric_part)
      rescue ArgumentError
        raise Errors::ParseError.new(
          Errors::ParseErrorCode::INVALID_TYPE_PREFIX,
          token.line, token.column,
          "Invalid currency format: #{raw}"
        )
      end

      def parse_percent(token)
        raw = token.value
        if raw.nil? || raw.empty?
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::INVALID_TYPE_PREFIX,
            token.line, token.column,
            "Invalid numeric format"
          )
        end
        val = Float(raw)
        Types::OdinPercent.new(val, raw: raw)
      rescue ArgumentError
        raise Errors::ParseError.new(
          Errors::ParseErrorCode::INVALID_TYPE_PREFIX,
          token.line, token.column,
          "Invalid percent format: #{raw}"
        )
      end

      def parse_boolean(token)
        case token.value
        when "true"  then Types::TRUE_VAL
        when "false" then Types::FALSE_VAL
        else
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::INVALID_TYPE_PREFIX,
            token.line, token.column,
            "Invalid boolean: #{token.value}"
          )
        end
      end

      RE_DATE = /\A(\d{4})-(\d{2})-(\d{2})\z/.freeze
      RE_TIMESTAMP_DATE = /\A(\d{4})-(\d{2})-(\d{2})T/.freeze

      def parse_date(token)
        raw = token.value
        validate_date!(raw, token)
        m = RE_DATE.match(raw)
        if m
          d = Date.new(m[1].to_i, m[2].to_i, m[3].to_i)
        else
          d = Date.parse(raw)
        end
        Types::OdinDate.new(d, raw: raw)
      rescue Date::Error, ArgumentError => e
        raise Errors::ParseError.new(
          Errors::ParseErrorCode::UNEXPECTED_CHARACTER,
          token.line, token.column,
          "Invalid date: #{raw}"
        )
      end

      def parse_timestamp(token)
        raw = token.value
        # Validate the date part
        m = RE_TIMESTAMP_DATE.match(raw)
        if m
          validate_date!("#{m[1]}-#{m[2]}-#{m[3]}", token)
        end
        # DateTime.new is much faster than DateTime.parse
        # Try fast path for ISO 8601 timestamps
        dt = fast_parse_timestamp(raw) || DateTime.parse(raw)
        Types::OdinTimestamp.new(dt, raw: raw)
      rescue Date::Error, ArgumentError
        raise Errors::ParseError.new(
          Errors::ParseErrorCode::UNEXPECTED_CHARACTER,
          token.line, token.column,
          "Invalid timestamp: #{raw}"
        )
      end

      def parse_time(token)
        Types::OdinTime.new(token.value)
      end

      def parse_duration(token)
        raw = token.value
        # Basic validation: must start with P
        unless raw.start_with?("P")
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::BARE_STRING_NOT_ALLOWED,
            token.line, token.column,
            "Invalid duration format: #{raw}"
          )
        end
        Types::OdinDuration.new(raw)
      end

      def parse_binary(token)
        raw = token.value

        # Handle empty binary
        if raw.nil? || raw.empty?
          return Types::OdinBinary.new("", algorithm: nil)
        end

        algorithm = nil
        base64_data = raw

        # Check for algorithm prefix (identifier:base64)
        if raw =~ /\A([a-zA-Z][a-zA-Z0-9]*):(.*)$/
          algorithm = $1
          base64_data = $2
        end

        # Validate base64 characters
        validate_base64!(base64_data, token) unless base64_data.empty?

        # Decode
        begin
          decoded = Base64.strict_decode64(base64_data) unless base64_data.empty?
        rescue ArgumentError
          # Try lenient decode
          decoded = Base64.decode64(base64_data)
        end

        Types::OdinBinary.new(base64_data, algorithm: algorithm)
      end

      def parse_verb_name(token)
        name = token.value
        is_custom = name.start_with?("&")
        verb_name = is_custom ? name[1..] : name
        # Args will be filled in by the parser
        Types::OdinVerbExpression.new(verb_name, is_custom: is_custom, args: [])
      end

      # --- helpers ---

      def validate_date!(date_str, token)
        return unless date_str =~ /\A(\d{4})-(\d{2})-(\d{2})\z/
        year, month, day = $1.to_i, $2.to_i, $3.to_i
        return if month < 1 || month > 12

        max_days = case month
                   when 1, 3, 5, 7, 8, 10, 12 then 31
                   when 4, 6, 9, 11 then 30
                   when 2 then leap_year?(year) ? 29 : 28
                   end

        if day > max_days || day < 1
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::UNEXPECTED_CHARACTER,
            token.line, token.column,
            "Invalid date: #{date_str}"
          )
        end
      end

      def leap_year?(year)
        (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
      end

      def validate_base64!(data, token)
        # Check for invalid characters
        unless data.match?(/\A[A-Za-z0-9+\/]*=*\z/)
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::UNEXPECTED_CHARACTER,
            token.line, token.column,
            "Invalid Base64 character"
          )
        end

        # Check padding position - padding only at end
        if data =~ /=/ && data !~ /\A[A-Za-z0-9+\/]*={0,2}\z/
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::UNEXPECTED_CHARACTER,
            token.line, token.column,
            "Invalid Base64 padding"
          )
        end
      end

      # Fast ISO 8601 timestamp parser: 2024-01-15T10:30:00Z or with offset
      RE_ISO_TS = /\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|([+-]\d{2}):?(\d{2}))?\z/.freeze

      def fast_parse_timestamp(raw)
        m = RE_ISO_TS.match(raw)
        return nil unless m
        y, mo, d = m[1].to_i, m[2].to_i, m[3].to_i
        h, mi, s = m[4].to_i, m[5].to_i, m[6].to_i
        frac = m[7]
        if m[8] == "Z" || m[8].nil?
          offset = "+00:00"
        else
          offset = "#{m[9]}:#{m[10]}"
        end
        sec = frac ? Rational("#{s}.#{frac}".to_r) : s
        DateTime.new(y, mo, d, h, mi, sec, offset)
      rescue
        nil
      end

      def needs_raw?(raw, val)
        # Store raw when float representation differs significantly
        formatted = val == val.to_i && !raw.include?(".") && !raw.include?("e") && !raw.include?("E") ? val.to_i.to_s : val.to_s
        # If the raw string has more precision info than the float
        raw.gsub(/\.?0+\z/, "") != formatted.gsub(/\.?0+\z/, "")
      rescue
        true
      end
    end
  end
end
