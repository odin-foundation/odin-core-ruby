# frozen_string_literal: true

module Odin
  module Errors
    module ParseErrorCode
      UNEXPECTED_CHARACTER           = -"P001"
      BARE_STRING_NOT_ALLOWED        = -"P002"
      INVALID_ARRAY_INDEX            = -"P003"
      UNTERMINATED_STRING            = -"P004"
      INVALID_ESCAPE_SEQUENCE        = -"P005"
      INVALID_TYPE_PREFIX            = -"P006"
      DUPLICATE_PATH_ASSIGNMENT      = -"P007"
      INVALID_HEADER_SYNTAX          = -"P008"
      INVALID_DIRECTIVE              = -"P009"
      MAXIMUM_DEPTH_EXCEEDED         = -"P010"
      MAXIMUM_DOCUMENT_SIZE_EXCEEDED = -"P011"
      INVALID_UTF8_SEQUENCE          = -"P012"
      NON_CONTIGUOUS_ARRAY_INDICES   = -"P013"
      EMPTY_DOCUMENT                 = -"P014"
      ARRAY_INDEX_OUT_OF_RANGE       = -"P015"

      ALL = {
        "P001" => "Unexpected character",
        "P002" => "Strings must be quoted",
        "P003" => "Invalid array index",
        "P004" => "Unterminated string",
        "P005" => "Invalid escape sequence",
        "P006" => "Invalid type prefix",
        "P007" => "Duplicate path assignment",
        "P008" => "Invalid header syntax",
        "P009" => "Invalid directive",
        "P010" => "Maximum depth exceeded",
        "P011" => "Maximum document size exceeded",
        "P012" => "Invalid UTF-8 sequence",
        "P013" => "Non-contiguous array indices",
        "P014" => "Empty document",
        "P015" => "Array index out of range"
      }.freeze

      def self.message(code)
        ALL[code] || "Unknown error"
      end
    end

    module ValidationErrorCode
      REQUIRED_FIELD_MISSING           = -"V001"
      TYPE_MISMATCH                    = -"V002"
      VALUE_OUT_OF_BOUNDS              = -"V003"
      PATTERN_MISMATCH                 = -"V004"
      INVALID_ENUM_VALUE               = -"V005"
      ARRAY_LENGTH_VIOLATION           = -"V006"
      UNIQUE_CONSTRAINT_VIOLATION      = -"V007"
      INVARIANT_VIOLATION              = -"V008"
      CARDINALITY_CONSTRAINT_VIOLATION = -"V009"
      CONDITIONAL_REQUIREMENT_NOT_MET  = -"V010"
      UNKNOWN_FIELD                    = -"V011"
      CIRCULAR_REFERENCE               = -"V012"
      UNRESOLVED_REFERENCE             = -"V013"

      ALL = {
        "V001" => "Required field missing",
        "V002" => "Type mismatch",
        "V003" => "Value out of bounds",
        "V004" => "Pattern mismatch",
        "V005" => "Invalid enum value",
        "V006" => "Array length violation",
        "V007" => "Unique constraint violation",
        "V008" => "Invariant violation",
        "V009" => "Cardinality constraint violation",
        "V010" => "Conditional requirement not met",
        "V011" => "Unknown field",
        "V012" => "Circular reference",
        "V013" => "Unresolved reference"
      }.freeze

      def self.message(code)
        ALL[code] || "Unknown error"
      end
    end

    class OdinError < StandardError
      attr_reader :code

      def initialize(code, message)
        @code = code
        super("[#{code}] #{message}")
      end
    end

    class ParseError < OdinError
      attr_reader :line, :column

      def initialize(code, line, column, detail = nil)
        @line = line
        @column = column
        msg = ParseErrorCode.message(code)
        msg = "#{msg}: #{detail}" if detail
        msg = "#{msg} at line #{line}, column #{column}"
        super(code, msg)
      end
    end

    class ValidationError
      attr_reader :path, :code, :message, :expected, :actual, :schema_path

      def initialize(code:, path:, message:, expected: nil, actual: nil, schema_path: nil)
        @code = code
        @path = path
        @message = message
        @expected = expected
        @actual = actual
        @schema_path = schema_path
      end

      def to_s
        "[#{code}] #{message} at '#{path}'"
      end
    end

    class ValidationResult
      attr_reader :errors

      def initialize(errors = [])
        @errors = errors.freeze
      end

      def valid?
        errors.empty?
      end

      def self.valid
        new([])
      end

      def self.with_errors(errors)
        new(errors)
      end
    end

    class PatchError < OdinError
      attr_reader :path

      def initialize(message, path)
        @path = path
        super("PATCH", "#{message} at '#{path}'")
      end
    end
  end
end
