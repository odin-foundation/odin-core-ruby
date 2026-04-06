# frozen_string_literal: true

module Odin
  module Transform
    # Direction constants
    module Direction
      JSON_TO_JSON   = "json->json"
      JSON_TO_ODIN   = "json->odin"
      ODIN_TO_JSON   = "odin->json"
      ODIN_TO_ODIN   = "odin->odin"
      XML_TO_ODIN    = "xml->odin"
      ODIN_TO_XML    = "odin->xml"
      CSV_TO_ODIN    = "csv->odin"
      ODIN_TO_CSV    = "odin->csv"
      FIXED_TO_ODIN  = "fixed-width->odin"
      ODIN_TO_FIXED  = "odin->fixed-width"
      JSON_TO_XML    = "json->xml"
      XML_TO_JSON    = "xml->json"
      CSV_TO_JSON    = "csv->json"
      JSON_TO_CSV    = "json->csv"

      ALL = [
        JSON_TO_JSON, JSON_TO_ODIN, ODIN_TO_JSON, ODIN_TO_ODIN,
        XML_TO_ODIN, ODIN_TO_XML, CSV_TO_ODIN, ODIN_TO_CSV,
        FIXED_TO_ODIN, ODIN_TO_FIXED, JSON_TO_XML, XML_TO_JSON,
        CSV_TO_JSON, JSON_TO_CSV
      ].freeze

      def self.parse(str)
        return nil unless str.is_a?(String)

        normalized = str.strip.downcase
        ALL.find { |d| d == normalized }
      end

      def self.source_format(direction)
        direction&.split("->")&.first
      end

      def self.target_format(direction)
        direction&.split("->")&.last
      end
    end

    # Confidential enforcement modes
    module ConfidentialMode
      NONE   = :none
      REDACT = :redact
      MASK   = :mask
    end

    # Field modifiers
    module FieldModifier
      REQUIRED     = :required
      CONFIDENTIAL = :confidential
      DEPRECATED   = :deprecated
    end

    # Transform definition — top-level AST node
    class TransformDef
      attr_reader :header, :segments, :constants, :tables, :accumulators, :passes

      def initialize(header:, segments: [], constants: {}, tables: {}, accumulators: {}, passes: [])
        @header = header
        @segments = segments
        @constants = constants
        @tables = tables
        @accumulators = accumulators
        @passes = passes
      end

      def direction
        header&.direction
      end

      def source_format
        # Prefer explicit source.format from {$source} section
        sf = header&.source_options&.dig("format")
        sf && !sf.empty? ? sf : Direction.source_format(direction)
      end

      def target_format
        header&.target_format || Direction.target_format(direction)
      end

      def discriminator_config
        header&.source_options&.dig("discriminator")
      end
    end

    # Transform header — the {$} section
    class TransformHeader
      attr_reader :odin_version, :transform_version, :direction,
                  :target_format, :enforce_confidential,
                  :source_options, :target_options,
                  :strict_types, :id, :name

      def initialize(
        odin_version: "1.0.0",
        transform_version: "1.0.0",
        direction: nil,
        target_format: nil,
        enforce_confidential: ConfidentialMode::NONE,
        source_options: {},
        target_options: {},
        strict_types: false,
        id: nil,
        name: nil
      )
        @odin_version = odin_version
        @transform_version = transform_version
        @direction = direction
        @target_format = target_format
        @enforce_confidential = enforce_confidential
        @source_options = source_options
        @target_options = target_options
        @strict_types = strict_types
        @id = id
        @name = name
      end
    end

    # Segment definition — a named section with field mappings
    class SegmentDef
      attr_reader :name, :path, :array_index,
                  :field_mappings, :discriminator, :discriminator_value,
                  :when_condition, :each_source, :if_condition,
                  :children, :pass, :counter_name, :is_array

      def initialize(
        name:,
        path: nil,
        array_index: nil,
        field_mappings: [],
        discriminator: nil,
        discriminator_value: nil,
        when_condition: nil,
        each_source: nil,
        if_condition: nil,
        children: [],
        pass: nil,
        counter_name: nil,
        is_array: false
      )
        @name = name
        @path = path
        @array_index = array_index
        @field_mappings = field_mappings
        @discriminator = discriminator
        @discriminator_value = discriminator_value
        @when_condition = when_condition
        @each_source = each_source
        @if_condition = if_condition
        @children = children
        @pass = pass
        @counter_name = counter_name
        @is_array = is_array
      end
    end

    # Field mapping — a single assignment within a segment
    class FieldMapping
      attr_reader :target_field, :expression, :modifiers, :directives

      def initialize(target_field:, expression:, modifiers: [], directives: [])
        @target_field = target_field
        @expression = expression
        @modifiers = modifiers
        @directives = directives
      end
    end

    # ── Field Expressions (AST for RHS of mappings) ──

    class FieldExpression
    end

    class LiteralExpr < FieldExpression
      attr_reader :value # DynValue

      def initialize(value)
        @value = value
      end

      def ==(other)
        other.is_a?(LiteralExpr) && value == other.value
      end
    end

    class CopyExpr < FieldExpression
      attr_reader :source_path, :directives # String like ".name" or ".items[0].id" or "" for bare @

      def initialize(source_path, directives: [])
        @source_path = source_path
        @directives = directives
      end

      def ==(other)
        other.is_a?(CopyExpr) && source_path == other.source_path
      end
    end

    class VerbExpr < FieldExpression
      attr_reader :verb_name, :arguments # arguments: Array<FieldExpression>
      attr_reader :custom # boolean — true for %&customVerb

      def initialize(verb_name, arguments = [], custom: false)
        @verb_name = verb_name
        @arguments = arguments
        @custom = custom
      end

      def ==(other)
        other.is_a?(VerbExpr) && verb_name == other.verb_name &&
          arguments == other.arguments && custom == other.custom
      end
    end

    class ObjectExpr < FieldExpression
      attr_reader :field_mappings # Array<FieldMapping>

      def initialize(field_mappings)
        @field_mappings = field_mappings
      end
    end

    # Directive attached to a field mapping
    class OdinDirective
      attr_reader :name, :value

      def initialize(name, value = nil)
        @name = name
        @value = value
      end

      def ==(other)
        other.is_a?(OdinDirective) && name == other.name && value == other.value
      end
    end

    # Lookup table
    class LookupTable
      attr_reader :rows, :columns, :default_value

      def initialize(rows: [], columns: [], default_value: nil)
        @rows = rows
        @columns = columns
        @default_value = default_value
      end
    end

    # Accumulator definition
    class AccumulatorDef
      attr_reader :initial_value, :persist

      def initialize(initial_value:, persist: false)
        @initial_value = initial_value
        @persist = persist
      end
    end

    # Transform result
    class TransformResult
      attr_reader :output, :formatted, :errors, :output_dv

      def initialize(output:, formatted: nil, errors: [], output_dv: nil)
        @output = output
        @formatted = formatted
        @errors = errors
        @output_dv = output_dv
      end

      def success?
        errors.empty?
      end
    end
  end
end
