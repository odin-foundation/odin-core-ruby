# frozen_string_literal: true

module Odin
  module Parsing
    module TokenType
      # Structure
      HEADER_OPEN   = :header_open
      HEADER_CLOSE  = :header_close
      EQUALS        = :equals
      NEWLINE       = :newline
      PIPE          = :pipe

      # Values
      STRING        = :string
      NUMBER        = :number
      INTEGER       = :integer
      CURRENCY      = :currency
      PERCENT       = :percent
      BOOLEAN       = :boolean
      NULL          = :null
      REFERENCE     = :reference
      BINARY        = :binary
      DATE          = :date
      TIMESTAMP     = :timestamp
      TIME          = :time
      DURATION      = :duration
      VERB          = :verb

      # Metadata
      PATH          = :path
      COMMENT       = :comment
      DIRECTIVE     = :directive
      MODIFIER      = :modifier

      # Control
      EOF           = :eof
      ERROR         = :error
    end
  end
end
