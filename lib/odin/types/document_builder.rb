# frozen_string_literal: true

module Odin
  module Types
    class OdinDocumentBuilder
      def initialize
        @assignments = {}
        @metadata = {}
        @modifiers = {}
        @comments = {}
      end

      def set(path, value, modifiers: nil, comment: nil)
        @assignments[path] = value
        @modifiers[path] = modifiers if modifiers
        @comments[path] = comment if comment
        self
      end

      def set_metadata(key, value)
        @metadata[key] = value
        self
      end

      def set_string(path, value, modifiers: nil)
        set(path, OdinString.new(value), modifiers: modifiers)
      end

      def set_integer(path, value, modifiers: nil)
        set(path, OdinInteger.new(value), modifiers: modifiers)
      end

      def set_number(path, value, modifiers: nil)
        set(path, OdinNumber.new(value), modifiers: modifiers)
      end

      def set_boolean(path, value, modifiers: nil)
        set(path, value ? TRUE_VAL : FALSE_VAL, modifiers: modifiers)
      end

      def set_null(path, modifiers: nil)
        set(path, NULL, modifiers: modifiers)
      end

      def set_currency(path, value, currency_code: nil, decimal_places: 2, modifiers: nil)
        set(path, OdinCurrency.new(value, currency_code: currency_code,
                                          decimal_places: decimal_places), modifiers: modifiers)
      end

      def remove(path)
        @assignments.delete(path)
        @modifiers.delete(path)
        @comments.delete(path)
        self
      end

      def build
        OdinDocument.new(
          assignments: @assignments.dup,
          metadata: @metadata.dup,
          modifiers: @modifiers.dup,
          comments: @comments.dup
        )
      end
    end
  end
end
