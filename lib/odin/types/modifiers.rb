# frozen_string_literal: true

module Odin
  module Types
    class OdinModifiers
      attr_reader :required, :confidential, :deprecated, :attr

      def initialize(required: false, confidential: false, deprecated: false, attr: nil)
        @required = required
        @confidential = confidential
        @deprecated = deprecated
        @attr = attr
        freeze
      end

      NONE = new

      def any?
        required || confidential || deprecated
      end

      def ==(other)
        other.is_a?(OdinModifiers) &&
          required == other.required &&
          confidential == other.confidential &&
          deprecated == other.deprecated &&
          self.attr == other.attr
      end
      alias eql? ==

      def hash
        [required, confidential, deprecated, self.attr].hash
      end

      def to_s
        parts = []
        parts << "required" if required
        parts << "confidential" if confidential
        parts << "deprecated" if deprecated
        parts << "attr=#{self.attr}" if self.attr
        parts.empty? ? "OdinModifiers(none)" : "OdinModifiers(#{parts.join(', ')})"
      end
    end
  end
end
