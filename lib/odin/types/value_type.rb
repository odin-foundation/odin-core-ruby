# frozen_string_literal: true

module Odin
  module Types
    module ValueType
      NULL      = :null
      BOOLEAN   = :boolean
      STRING    = :string
      NUMBER    = :number
      INTEGER   = :integer
      CURRENCY  = :currency
      PERCENT   = :percent
      DATE      = :date
      TIMESTAMP = :timestamp
      TIME      = :time
      DURATION  = :duration
      REFERENCE = :reference
      BINARY    = :binary
      VERB      = :verb
      ARRAY     = :array
      OBJECT    = :object

      ALL = [NULL, BOOLEAN, STRING, NUMBER, INTEGER, CURRENCY, PERCENT,
             DATE, TIMESTAMP, TIME, DURATION, REFERENCE, BINARY, VERB,
             ARRAY, OBJECT].freeze
    end
  end
end
