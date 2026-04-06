# frozen_string_literal: true

module Odin
  module Parsing
    class Token
      attr_reader :type, :value, :line, :column, :raw

      def initialize(type, value, line, column, raw: nil)
        @type = type
        @value = value
        @line = line
        @column = column
        @raw = raw
        freeze
      end

      def to_s
        "Token(#{type}, #{value.inspect}, L#{line}:#{column})"
      end

      def error?
        type == TokenType::ERROR
      end
    end
  end
end
