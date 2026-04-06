# frozen_string_literal: true

module Odin
  module Types
    class OdinDirective
      attr_reader :name, :value

      def initialize(name, value = nil)
        @name = -name.to_s
        @value = value&.freeze
        freeze
      end

      def ==(other)
        other.is_a?(OdinDirective) && name == other.name && value == other.value
      end
      alias eql? ==

      def hash
        [name, value].hash
      end

      def to_s
        value ? "#{name}(#{value})" : name
      end
    end
  end
end
