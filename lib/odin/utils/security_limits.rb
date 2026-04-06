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
    end
  end
end
