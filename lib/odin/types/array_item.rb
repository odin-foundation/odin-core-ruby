# frozen_string_literal: true

module Odin
  module Types
    class OdinArrayItem
      attr_reader :kind, :value, :fields

      def self.from_value(value)
        new(kind: :value, value: value)
      end

      def self.record(fields)
        new(kind: :record, fields: fields)
      end

      def initialize(kind:, value: nil, fields: nil)
        @kind = kind
        @value = value
        @fields = fields&.freeze
        freeze
      end

      def record?
        kind == :record
      end

      def value?
        kind == :value
      end

      def ==(other)
        other.is_a?(OdinArrayItem) && kind == other.kind &&
          value == other.value && fields == other.fields
      end
      alias eql? ==

      def hash
        [kind, value, fields].hash
      end
    end
  end
end
