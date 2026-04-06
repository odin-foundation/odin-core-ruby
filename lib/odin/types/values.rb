# frozen_string_literal: true

require "bigdecimal"
require "date"

module Odin
  module Types
    class OdinValue
      attr_reader :modifiers, :directives

      def initialize(modifiers: nil, directives: [])
        @modifiers = modifiers
        @directives = directives.freeze
      end

      def required?;     modifiers&.required || false; end
      def confidential?; modifiers&.confidential || false; end
      def deprecated?;   modifiers&.deprecated || false; end

      def null?;      type == ValueType::NULL; end
      def boolean?;   type == ValueType::BOOLEAN; end
      def string?;    type == ValueType::STRING; end
      def integer?;   type == ValueType::INTEGER; end
      def number?;    type == ValueType::NUMBER; end
      def currency?;  type == ValueType::CURRENCY; end
      def percent?;   type == ValueType::PERCENT; end
      def numeric?;   %i[integer number currency percent].include?(type); end
      def temporal?;  %i[date timestamp time duration].include?(type); end
      def date?;      type == ValueType::DATE; end
      def timestamp?; type == ValueType::TIMESTAMP; end
      def time?;      type == ValueType::TIME; end
      def duration?;  type == ValueType::DURATION; end
      def reference?; type == ValueType::REFERENCE; end
      def binary?;    type == ValueType::BINARY; end
      def verb?;      type == ValueType::VERB; end
      def array?;     type == ValueType::ARRAY; end
      def object?;    type == ValueType::OBJECT; end

      def with_modifiers(mods)
        raise NotImplementedError, "Subclass must implement #with_modifiers"
      end

      def with_directives(dirs)
        raise NotImplementedError, "Subclass must implement #with_directives"
      end
    end

    class OdinNull < OdinValue
      def initialize(**kwargs)
        super(**kwargs)
        freeze
      end

      def type; ValueType::NULL; end
      def value; nil; end

      def ==(other)
        other.is_a?(OdinNull)
      end
      alias eql? ==

      def hash
        ValueType::NULL.hash
      end

      def to_s
        "~"
      end

      def with_modifiers(mods)
        OdinNull.new(modifiers: mods, directives: directives)
      end

      def with_directives(dirs)
        OdinNull.new(modifiers: modifiers, directives: dirs)
      end
    end

    NULL = OdinNull.new

    class OdinBoolean < OdinValue
      attr_reader :value

      def initialize(value, **kwargs)
        super(**kwargs)
        @value = value
        freeze
      end

      def type; ValueType::BOOLEAN; end

      def ==(other)
        other.is_a?(OdinBoolean) && value == other.value
      end
      alias eql? ==

      def hash
        [ValueType::BOOLEAN, value].hash
      end

      def to_s
        value.to_s
      end

      def with_modifiers(mods)
        OdinBoolean.new(value, modifiers: mods, directives: directives)
      end

      def with_directives(dirs)
        OdinBoolean.new(value, modifiers: modifiers, directives: dirs)
      end
    end

    TRUE_VAL = OdinBoolean.new(true)
    FALSE_VAL = OdinBoolean.new(false)

    class OdinString < OdinValue
      attr_reader :value

      def initialize(value, **kwargs)
        super(**kwargs)
        @value = -value.to_s
        freeze
      end

      def type; ValueType::STRING; end

      def ==(other)
        other.is_a?(OdinString) && value == other.value
      end
      alias eql? ==

      def hash
        [ValueType::STRING, value].hash
      end

      def to_s
        "\"#{value}\""
      end

      def with_modifiers(mods)
        OdinString.new(value, modifiers: mods, directives: directives)
      end

      def with_directives(dirs)
        OdinString.new(value, modifiers: modifiers, directives: dirs)
      end
    end

    class OdinNumber < OdinValue
      attr_reader :value, :raw

      def initialize(value, raw: nil, **kwargs)
        super(**kwargs)
        @value = value.to_f
        @raw = raw&.freeze
        freeze
      end

      def type; ValueType::NUMBER; end

      def ==(other)
        other.is_a?(OdinNumber) && value == other.value
      end
      alias eql? ==

      def hash
        [ValueType::NUMBER, value].hash
      end

      def to_s
        raw || value.to_s
      end

      def with_modifiers(mods)
        OdinNumber.new(value, raw: raw, modifiers: mods, directives: directives)
      end

      def with_directives(dirs)
        OdinNumber.new(value, raw: raw, modifiers: modifiers, directives: dirs)
      end
    end

    class OdinInteger < OdinValue
      attr_reader :value, :raw

      def initialize(value, raw: nil, **kwargs)
        super(**kwargs)
        @value = value.to_i
        @raw = raw&.freeze
        freeze
      end

      def type; ValueType::INTEGER; end

      def ==(other)
        other.is_a?(OdinInteger) && value == other.value
      end
      alias eql? ==

      def hash
        [ValueType::INTEGER, value].hash
      end

      def to_s
        raw || value.to_s
      end

      def with_modifiers(mods)
        OdinInteger.new(value, raw: raw, modifiers: mods, directives: directives)
      end

      def with_directives(dirs)
        OdinInteger.new(value, raw: raw, modifiers: modifiers, directives: dirs)
      end
    end

    class OdinCurrency < OdinValue
      attr_reader :value, :currency_code, :decimal_places, :raw

      def initialize(value, currency_code: nil, decimal_places: 2, raw: nil, **kwargs)
        super(**kwargs)
        @value = value.is_a?(BigDecimal) ? value : BigDecimal(value.to_s)
        @currency_code = currency_code&.freeze
        @decimal_places = decimal_places
        @raw = raw&.freeze
        freeze
      end

      def type; ValueType::CURRENCY; end

      def ==(other)
        other.is_a?(OdinCurrency) && value == other.value &&
          currency_code == other.currency_code
      end
      alias eql? ==

      def hash
        [ValueType::CURRENCY, value, currency_code].hash
      end

      def to_s
        s = raw || value.to_s("F")
        currency_code ? "#{s}:#{currency_code}" : s
      end

      def with_modifiers(mods)
        OdinCurrency.new(value, currency_code: currency_code, decimal_places: decimal_places,
                                raw: raw, modifiers: mods, directives: directives)
      end

      def with_directives(dirs)
        OdinCurrency.new(value, currency_code: currency_code, decimal_places: decimal_places,
                                raw: raw, modifiers: modifiers, directives: dirs)
      end
    end

    class OdinPercent < OdinValue
      attr_reader :value, :raw

      def initialize(value, raw: nil, **kwargs)
        super(**kwargs)
        @value = value.to_f
        @raw = raw&.freeze
        freeze
      end

      def type; ValueType::PERCENT; end

      def ==(other)
        other.is_a?(OdinPercent) && value == other.value
      end
      alias eql? ==

      def hash
        [ValueType::PERCENT, value].hash
      end

      def to_s
        raw || value.to_s
      end

      def with_modifiers(mods)
        OdinPercent.new(value, raw: raw, modifiers: mods, directives: directives)
      end

      def with_directives(dirs)
        OdinPercent.new(value, raw: raw, modifiers: modifiers, directives: dirs)
      end
    end

    class OdinDate < OdinValue
      attr_reader :value, :raw

      def initialize(value, raw: nil, **kwargs)
        super(**kwargs)
        @value = value
        @raw = (raw || value.to_s).freeze
        freeze
      end

      def type; ValueType::DATE; end

      def ==(other)
        other.is_a?(OdinDate) && value == other.value
      end
      alias eql? ==

      def hash
        [ValueType::DATE, value].hash
      end

      def to_s
        raw
      end

      def with_modifiers(mods)
        OdinDate.new(value, raw: raw, modifiers: mods, directives: directives)
      end

      def with_directives(dirs)
        OdinDate.new(value, raw: raw, modifiers: modifiers, directives: dirs)
      end
    end

    class OdinTimestamp < OdinValue
      attr_reader :value, :raw

      def initialize(value, raw: nil, **kwargs)
        super(**kwargs)
        @value = value
        @raw = (raw || value.iso8601).freeze
        freeze
      end

      def type; ValueType::TIMESTAMP; end

      def ==(other)
        other.is_a?(OdinTimestamp) && value == other.value
      end
      alias eql? ==

      def hash
        [ValueType::TIMESTAMP, value].hash
      end

      def to_s
        raw
      end

      def with_modifiers(mods)
        OdinTimestamp.new(value, raw: raw, modifiers: mods, directives: directives)
      end

      def with_directives(dirs)
        OdinTimestamp.new(value, raw: raw, modifiers: modifiers, directives: dirs)
      end
    end

    class OdinTime < OdinValue
      attr_reader :value

      def initialize(value, **kwargs)
        super(**kwargs)
        @value = -value.to_s
        freeze
      end

      def type; ValueType::TIME; end

      def ==(other)
        other.is_a?(OdinTime) && value == other.value
      end
      alias eql? ==

      def hash
        [ValueType::TIME, value].hash
      end

      def to_s
        value
      end

      def with_modifiers(mods)
        OdinTime.new(value, modifiers: mods, directives: directives)
      end

      def with_directives(dirs)
        OdinTime.new(value, modifiers: modifiers, directives: dirs)
      end
    end

    class OdinDuration < OdinValue
      attr_reader :value

      def initialize(value, **kwargs)
        super(**kwargs)
        @value = -value.to_s
        freeze
      end

      def type; ValueType::DURATION; end

      def ==(other)
        other.is_a?(OdinDuration) && value == other.value
      end
      alias eql? ==

      def hash
        [ValueType::DURATION, value].hash
      end

      def to_s
        value
      end

      def with_modifiers(mods)
        OdinDuration.new(value, modifiers: mods, directives: directives)
      end

      def with_directives(dirs)
        OdinDuration.new(value, modifiers: modifiers, directives: dirs)
      end
    end

    class OdinReference < OdinValue
      attr_reader :path

      def initialize(path, **kwargs)
        super(**kwargs)
        @path = path.freeze
        freeze
      end

      def type; ValueType::REFERENCE; end
      def value; @path; end

      def ==(other)
        other.is_a?(OdinReference) && path == other.path
      end
      alias eql? ==

      def hash
        [ValueType::REFERENCE, path].hash
      end

      def to_s
        "@#{path}"
      end

      def with_modifiers(mods)
        OdinReference.new(path, modifiers: mods, directives: directives)
      end

      def with_directives(dirs)
        OdinReference.new(path, modifiers: modifiers, directives: dirs)
      end
    end

    class OdinBinary < OdinValue
      attr_reader :data, :algorithm

      def initialize(data, algorithm: nil, **kwargs)
        super(**kwargs)
        @data = data.freeze
        @algorithm = algorithm&.freeze
        freeze
      end

      def type; ValueType::BINARY; end

      def ==(other)
        other.is_a?(OdinBinary) && data == other.data && algorithm == other.algorithm
      end
      alias eql? ==

      def hash
        [ValueType::BINARY, data, algorithm].hash
      end

      def to_s
        algorithm ? "^#{algorithm}:#{data}" : "^#{data}"
      end

      def with_modifiers(mods)
        OdinBinary.new(data, algorithm: algorithm, modifiers: mods, directives: directives)
      end

      def with_directives(dirs)
        OdinBinary.new(data, algorithm: algorithm, modifiers: modifiers, directives: dirs)
      end
    end

    class OdinVerbExpression < OdinValue
      attr_reader :verb, :is_custom, :args

      def initialize(verb, is_custom: false, args: [], **kwargs)
        super(**kwargs)
        @verb = -verb.to_s
        @is_custom = is_custom
        @args = args.freeze
        freeze
      end

      def type; ValueType::VERB; end

      def custom?
        @is_custom
      end

      def ==(other)
        other.is_a?(OdinVerbExpression) && verb == other.verb &&
          is_custom == other.is_custom && args == other.args
      end
      alias eql? ==

      def hash
        [ValueType::VERB, verb, is_custom, args].hash
      end

      def to_s
        "%#{verb}(#{args.join(', ')})"
      end

      def with_modifiers(mods)
        OdinVerbExpression.new(verb, is_custom: is_custom, args: args,
                                     modifiers: mods, directives: directives)
      end

      def with_directives(dirs)
        OdinVerbExpression.new(verb, is_custom: is_custom, args: args,
                                     modifiers: modifiers, directives: dirs)
      end
    end

    class OdinArray < OdinValue
      attr_reader :items

      def initialize(items: [], **kwargs)
        super(**kwargs)
        @items = items.freeze
        freeze
      end

      def type; ValueType::ARRAY; end

      def size; items.size; end
      alias length size

      def [](index); items[index]; end

      def empty?; items.empty?; end

      def ==(other)
        other.is_a?(OdinArray) && items == other.items
      end
      alias eql? ==

      def hash
        [ValueType::ARRAY, items].hash
      end

      def to_s
        "[#{items.size} items]"
      end

      def with_modifiers(mods)
        OdinArray.new(items: items, modifiers: mods, directives: directives)
      end

      def with_directives(dirs)
        OdinArray.new(items: items, modifiers: modifiers, directives: dirs)
      end
    end

    class OdinObject < OdinValue
      attr_reader :entries

      def initialize(entries: {}, **kwargs)
        super(**kwargs)
        @entries = entries.freeze
        freeze
      end

      def type; ValueType::OBJECT; end

      def size; entries.size; end
      alias length size

      def [](key); entries[key]; end

      def keys; entries.keys; end

      def empty?; entries.empty?; end

      def ==(other)
        other.is_a?(OdinObject) && entries == other.entries
      end
      alias eql? ==

      def hash
        [ValueType::OBJECT, entries].hash
      end

      def to_s
        "{#{entries.size} entries}"
      end

      def with_modifiers(mods)
        OdinObject.new(entries: entries, modifiers: mods, directives: directives)
      end

      def with_directives(dirs)
        OdinObject.new(entries: entries, modifiers: modifiers, directives: dirs)
      end
    end
  end
end
