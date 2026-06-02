# frozen_string_literal: true

module Odin
  module Forms
    # Measurement-unit conversion between page units and CSS pixels.
    module Units
      DPI = 96.0

      CONVERSIONS = {
        "inch" => DPI,
        "cm" => DPI / 2.54,
        "mm" => DPI / 25.4,
        "pt" => DPI / 72.0,
      }.freeze

      module_function

      # Convert a value in the given unit to pixels, rounded to 3 decimals.
      def to_pixels(value, unit)
        factor = CONVERSIONS[unit.to_s]
        raise ArgumentError, "Unknown unit: #{unit}" unless factor

        round3(value * factor)
      end

      # Convert pixels back to the given unit, rounded to 3 decimals.
      def from_pixels(px, unit)
        factor = CONVERSIONS[unit.to_s]
        raise ArgumentError, "Unknown unit: #{unit}" unless factor

        round3(px / factor)
      end

      # Round to 3 decimal places, returning an integer when whole.
      def round3(n)
        r = (n * 1000).round / 1000.0
        r == r.to_i ? r.to_i : r
      end
    end
  end
end
