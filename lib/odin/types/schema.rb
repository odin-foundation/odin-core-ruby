# frozen_string_literal: true

module Odin
  module Types
    # Schema field type identifiers matching TS/Java SchemaFieldType
    module SchemaFieldType
      STRING    = :string
      INTEGER   = :integer
      NUMBER    = :number
      BOOLEAN   = :boolean
      DATE      = :date
      TIMESTAMP = :timestamp
      TIME      = :time
      DURATION  = :duration
      CURRENCY  = :currency
      PERCENT   = :percent
      BINARY    = :binary
      REFERENCE = :reference
      NULL      = :null
      ANY       = :any

      ALL = [STRING, INTEGER, NUMBER, BOOLEAN, DATE, TIMESTAMP, TIME,
             DURATION, CURRENCY, PERCENT, BINARY, REFERENCE, NULL, ANY].freeze

      # Map from ODIN ValueType to SchemaFieldType
      FROM_VALUE_TYPE = {
        ValueType::STRING    => STRING,
        ValueType::INTEGER   => INTEGER,
        ValueType::NUMBER    => NUMBER,
        ValueType::BOOLEAN   => BOOLEAN,
        ValueType::DATE      => DATE,
        ValueType::TIMESTAMP => TIMESTAMP,
        ValueType::TIME      => TIME,
        ValueType::DURATION  => DURATION,
        ValueType::CURRENCY  => CURRENCY,
        ValueType::PERCENT   => PERCENT,
        ValueType::BINARY    => BINARY,
        ValueType::REFERENCE => REFERENCE,
        ValueType::NULL      => NULL,
      }.freeze
    end

    # Constraint types
    class BoundsConstraint
      attr_reader :min, :max, :exclusive_min, :exclusive_max, :kind

      def initialize(min: nil, max: nil, exclusive_min: nil, exclusive_max: nil)
        @kind = :bounds
        @min = min
        @max = max
        @exclusive_min = exclusive_min
        @exclusive_max = exclusive_max
        freeze
      end
    end

    class PatternConstraint
      attr_reader :pattern, :message, :kind

      def initialize(pattern:, message: nil)
        @kind = :pattern
        @pattern = pattern.freeze
        @message = message&.freeze
        freeze
      end
    end

    class EnumConstraint
      attr_reader :values, :message, :kind

      def initialize(values:, message: nil)
        @kind = :enum
        @values = values.freeze
        @message = message&.freeze
        freeze
      end
    end

    class SizeConstraint
      attr_reader :min_length, :max_length, :kind

      def initialize(min_length: nil, max_length: nil)
        @kind = :size
        @min_length = min_length
        @max_length = max_length
        freeze
      end
    end

    class FormatConstraint
      attr_reader :format_name, :kind

      def initialize(format_name:)
        @kind = :format
        @format_name = format_name.freeze
        freeze
      end
    end

    class UniqueConstraint
      attr_reader :field_name, :kind

      def initialize(field_name: nil)
        @kind = :unique
        @field_name = field_name&.freeze
        freeze
      end
    end

    # Schema field definition
    class SchemaField
      attr_reader :name, :field_type, :required, :nullable, :redacted, :deprecated,
                  :constraints, :conditionals, :default_value, :description,
                  :computed, :immutable, :type_ref

      def initialize(name:, field_type:, required: false, nullable: false,
                     redacted: false, deprecated: false, constraints: [],
                     conditionals: [], default_value: nil, description: nil,
                     computed: false, immutable: false, type_ref: nil)
        @name = name.freeze
        @field_type = field_type
        @required = required
        @nullable = nullable
        @redacted = redacted
        @deprecated = deprecated
        @constraints = constraints.freeze
        @conditionals = conditionals.freeze
        @default_value = default_value
        @description = description&.freeze
        @computed = computed
        @immutable = immutable
        @type_ref = type_ref&.freeze
        freeze
      end
    end

    # Schema type definition (named object structure)
    class SchemaType
      attr_reader :name, :fields, :namespace, :composition,
                  :base_type, :constraints, :intersection_types, :parent_types

      def initialize(name:, fields: {}, namespace: nil, composition: nil,
                     base_type: nil, constraints: nil, intersection_types: nil,
                     parent_types: nil)
        @name = name.freeze
        @fields = fields.freeze
        @namespace = namespace&.freeze
        @composition = composition
        @base_type = base_type
        @constraints = (constraints || {}).freeze
        @intersection_types = intersection_types&.freeze
        @parent_types = parent_types&.freeze
        freeze
      end
    end

    # Schema array definition
    class SchemaArray
      attr_reader :path, :item_fields, :min_items, :max_items, :unique, :columns

      def initialize(path:, item_fields: {}, min_items: nil, max_items: nil,
                     unique: false, columns: nil)
        @path = path.freeze
        @item_fields = item_fields.freeze
        @min_items = min_items
        @max_items = max_items
        @unique = unique
        @columns = columns&.freeze
        freeze
      end
    end

    # Conditional constraint (when/unless guard)
    class SchemaConditional
      attr_reader :field, :operator, :value, :unless

      def initialize(field:, operator: "=", value: nil, unless_cond: false)
        @field = field.freeze
        @operator = operator.freeze
        @value = value
        @unless = unless_cond
        freeze
      end

      def evaluate(doc_value)
        result = case @operator
                 when "="  then doc_value.to_s == @value.to_s
                 when "!=" then doc_value.to_s != @value.to_s
                 when ">"  then numeric_compare(doc_value, @value) { |a, b| a > b }
                 when "<"  then numeric_compare(doc_value, @value) { |a, b| a < b }
                 when ">=" then numeric_compare(doc_value, @value) { |a, b| a >= b }
                 when "<=" then numeric_compare(doc_value, @value) { |a, b| a <= b }
                 else false
                 end
        @unless ? !result : result
      end

      private

      def numeric_compare(a, b)
        af = Float(a.to_s) rescue nil
        bf = Float(b.to_s) rescue nil
        return false unless af && bf
        yield af, bf
      end
    end

    # Cardinality constraint (:of, :one_of, :exactly_one, :at_most_one)
    class SchemaCardinality
      attr_reader :kind, :cardinality_type, :min, :max, :fields

      def initialize(cardinality_type:, fields:, min: nil, max: nil)
        @kind = :cardinality
        @cardinality_type = cardinality_type.freeze
        @fields = fields.freeze
        @min = min
        @max = max
        freeze
      end
    end

    # Invariant constraint (cross-field validation)
    class SchemaInvariant
      attr_reader :kind, :expression

      def initialize(expression:)
        @kind = :invariant
        @expression = expression.freeze
        freeze
      end
    end

    # Schema import directive
    class SchemaImport
      attr_reader :path, :alias_name, :line

      def initialize(path:, alias_name: nil, line: 0)
        @path = path.freeze
        @alias_name = alias_name&.freeze
        @line = line
        freeze
      end
    end

    # Complete schema definition
    class OdinSchema
      attr_reader :metadata, :types, :fields, :arrays,
                  :imports, :object_constraints

      def initialize(metadata: {}, types: {}, fields: {}, arrays: {},
                     imports: [], object_constraints: {})
        @metadata = metadata.freeze
        @types = types.freeze
        @fields = fields.freeze
        @arrays = arrays.freeze
        @imports = imports.freeze
        @object_constraints = object_constraints.freeze
        freeze
      end
    end
  end
end
