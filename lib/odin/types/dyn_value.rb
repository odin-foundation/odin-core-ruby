# frozen_string_literal: true

require "json"
require "bigdecimal"

module Odin
  module Types
    class DynValue
      TYPES = %i[
        null bool integer float float_raw
        currency currency_raw percent reference binary
        date timestamp time duration
        string array object
      ].freeze

      attr_reader :type, :value, :decimal_places, :currency_code

      def initialize(type:, value: nil, decimal_places: 0, currency_code: nil)
        @type = type
        @value = value
        @decimal_places = decimal_places
        @currency_code = currency_code&.freeze
        freeze
      end

      # Factory methods
      def self.of_null
        new(type: :null)
      end

      def self.of_bool(v)
        new(type: :bool, value: v)
      end

      def self.of_integer(v)
        new(type: :integer, value: v.to_i)
      end

      def self.of_float(v)
        new(type: :float, value: v.to_f)
      end

      def self.of_float_raw(raw)
        new(type: :float_raw, value: raw.to_s)
      end

      def self.of_string(v)
        new(type: :string, value: v.to_s)
      end

      def self.of_array(items)
        new(type: :array, value: items)
      end

      def self.of_object(entries)
        new(type: :object, value: entries)
      end

      def self.of_currency(v, dp = 2, code = nil)
        new(type: :currency, value: v.to_f, decimal_places: dp, currency_code: code)
      end

      def self.of_currency_raw(raw, dp = 2, code = nil)
        new(type: :currency_raw, value: raw.to_s, decimal_places: dp, currency_code: code)
      end

      def self.of_percent(v)
        new(type: :percent, value: v.to_f)
      end

      def self.of_reference(p)
        new(type: :reference, value: p.to_s)
      end

      def self.of_binary(data)
        new(type: :binary, value: data)
      end

      def self.of_date(v)
        new(type: :date, value: v)
      end

      def self.of_timestamp(v)
        new(type: :timestamp, value: v)
      end

      def self.of_time(v)
        new(type: :time, value: v.to_s)
      end

      def self.of_duration(v)
        new(type: :duration, value: v.to_s)
      end

      # Helpers: parse JSON strings into DynValue arrays/objects
      def self.extract_array(json_string)
        parsed = JSON.parse(json_string)
        raise ArgumentError, "Not a JSON array" unless parsed.is_a?(::Array)

        of_array(parsed.map { |item| from_json_value(item) })
      end

      def self.extract_object(json_string)
        parsed = JSON.parse(json_string)
        raise ArgumentError, "Not a JSON object" unless parsed.is_a?(::Hash)

        of_object(parsed.transform_values { |v| from_json_value(v) })
      end

      def self.from_json_value(val)
        case val
        when nil         then of_null
        when true, false then of_bool(val)
        when Integer     then of_integer(val)
        when Float       then of_float(val)
        when String      then of_string(val)
        when Array       then of_array(val.map { |v| from_json_value(v) })
        when Hash        then of_object(val.transform_values { |v| from_json_value(v) })
        else of_string(val.to_s)
        end
      end

      # Type predicates
      def null?;      type == :null; end
      def bool?;      type == :bool; end
      def integer?;   type == :integer; end
      def float?;     type == :float || type == :float_raw; end
      def currency?;  type == :currency || type == :currency_raw; end
      def percent?;   type == :percent; end
      def string?;    type == :string; end
      def array?;     type == :array; end
      def object?;    type == :object; end
      def reference?; type == :reference; end
      def binary?;    type == :binary; end
      def date?;      type == :date; end
      def timestamp?; type == :timestamp; end
      def time?;      type == :time; end
      def duration?;  type == :duration; end
      def numeric?;   integer? || float? || currency? || percent?; end

      def temporal?; date? || timestamp? || time? || duration?; end

      # Coercion accessors
      def as_bool;    value; end
      def as_int;     value.to_i; end
      def as_float;   value.to_f; end
      def as_string;  value.to_s; end
      def as_array;   value; end
      def as_object;  value; end

      # Coerce to numeric value
      def to_number
        case type
        when :integer then value
        when :float then value
        when :float_raw then value.to_f
        when :currency then value.to_f
        when :currency_raw then value.to_f
        when :percent then value
        when :string
          return value.to_i if value.match?(/\A-?\d+\z/)
          return value.to_f if value.match?(/\A-?\d+(\.\d+)?([eE][+-]?\d+)?\z/)

          0
        when :bool then value ? 1 : 0
        else 0
        end
      end

      # Coerce to string representation
      def to_string
        case type
        when :null then ""
        when :bool then value.to_s
        when :integer, :float, :percent then value.to_s
        when :float_raw, :currency_raw then value.to_s
        when :currency then value.is_a?(BigDecimal) ? value.to_s("F") : value.to_s
        when :string then value
        when :array then JSON.generate(to_ruby)
        when :object then JSON.generate(to_ruby)
        else value.to_s
        end
      end

      # Truthiness: null/false/0/"" are falsy
      def truthy?
        case type
        when :null then false
        when :bool then value
        when :integer then value != 0
        when :float, :float_raw then to_number != 0.0
        when :string then !value.empty?
        when :currency, :currency_raw then to_number != 0.0
        when :percent then value != 0.0
        when :array then true
        when :object then true
        else true
        end
      end

      # Object/array access helpers
      def get(key)
        return nil unless object?

        value[key]
      end

      def get_index(index)
        return nil unless array?

        value[index]
      end

      def ==(other)
        other.is_a?(DynValue) && type == other.type && value == other.value &&
          decimal_places == other.decimal_places && currency_code == other.currency_code
      end
      alias eql? ==

      def hash
        [type, value, decimal_places, currency_code].hash
      end

      # Convert Ruby native object to DynValue
      def self.from_ruby(obj)
        case obj
        when DynValue    then obj
        when nil         then of_null
        when true, false then of_bool(obj)
        when Integer     then of_integer(obj)
        when Float       then of_float(obj)
        when BigDecimal  then of_float(obj.to_f)
        when String      then of_string(obj)
        when Array       then of_array(obj.map { |v| from_ruby(v) })
        when Hash        then of_object(obj.transform_keys(&:to_s).transform_values { |v| from_ruby(v) })
        else of_string(obj.to_s)
        end
      end

      # Convert DynValue to Ruby native object
      def to_ruby
        case type
        when :null then nil
        when :bool then value
        when :integer then value
        when :float then value
        when :float_raw then value.to_f
        when :string then value
        when :currency then value.is_a?(BigDecimal) ? value.to_f : value.to_f
        when :currency_raw then value.to_f
        when :percent then value
        when :date, :timestamp, :time, :duration then value.to_s
        when :reference then value
        when :binary then value
        when :array then value.map(&:to_ruby)
        when :object then value.transform_values(&:to_ruby)
        else value
        end
      end

      def to_s
        case type
        when :null then "null"
        when :bool then value.to_s
        else value.to_s
        end
      end
    end
  end
end
