# frozen_string_literal: true

module Odin
  module Utils
    module SecurityLimits
      MAX_DOCUMENT_SIZE       = 10 * 1024 * 1024  # 10 MB
      MAX_DEPTH               = 64
      MAX_PATH_SEGMENTS       = 32
      MAX_STRING_LENGTH       = 1_000_000          # 1 MB
      MAX_ARRAY_INDEX         = 10_000
      MAX_BINARY_SIZE         = 10_000_000         # 10 MB
      MAX_RECORDS             = 100_000
      MAX_ASSIGNMENTS         = 100_000
      MAX_REGEX_PATTERN_LENGTH = 500
      MAX_EXPRESSION_DEPTH    = 32

      # Read an integer limit from ODIN_<name>, falling back to default.
      def self.env_int(name, default)
        raw = ENV["ODIN_#{name}"]
        return default if raw.nil? || raw.strip.empty?

        Integer(raw)
      rescue ArgumentError
        default
      end

      # Transform fuel budget; 0 = unbounded.
      def self.max_transform_fuel
        env_int("MAX_TRANSFORM_FUEL", 0)
      end

      # Transform wall-clock timeout in milliseconds; 0 = unbounded.
      def self.transform_timeout_ms
        env_int("TRANSFORM_TIMEOUT_MS", 0)
      end

      # Expression evaluation depth cap; standing default when unset.
      def self.max_expression_depth
        env_int("MAX_EXPRESSION_DEPTH", MAX_EXPRESSION_DEPTH)
      end
    end
  end
end
