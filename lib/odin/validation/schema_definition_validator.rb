# frozen_string_literal: true

require "set"

module Odin
  module Validation
    # Validates that the schema itself is well-formed, independent of any document:
    # override restrictiveness, intersection field conflicts, tabular column rules,
    # and default-value rules. Violations are reported as V017.
    class SchemaDefinitionValidator
      PRIMITIVE_TYPES = Set.new(
        %i[string boolean number integer currency percent date timestamp
           time duration binary null]
      ).freeze

      def initialize(schema, registry = nil)
        @schema = schema
        @registry = registry
        @errors = []
      end

      def validate
        validate_type_definitions
        validate_path_compositions
        validate_tabular_columns
        validate_defaults
        @errors
      end

      private

      def add_error(path, message, expected = nil, actual = nil)
        @errors << Errors::ValidationError.new(
          code: Errors::ValidationErrorCode::SCHEMA_DEFINITION_INVALID,
          path: path,
          message: message,
          expected: expected,
          actual: actual
        )
      end

      def lookup_type(name)
        type = @registry&.lookup(name)
        return type if type

        @schema.types[name]
      end

      def member_names(type_ref)
        type_ref.to_s.sub(/\A@+/, "").split("&").map(&:strip).reject(&:empty?)
      end

      # ── Override and intersection (type definitions) ──

      def validate_type_definitions
        @schema.types.each do |type_name, type|
          composition = type.fields["_composition"]
          next unless composition&.type_ref

          members = member_names(composition.type_ref)

          if composition.immutable
            validate_override(type_name, type, members)
          elsif members.length > 1
            validate_intersection_conflicts(type_name, members)
          end
        end
      end

      def validate_override(type_name, type, base_names)
        base_fields = {}
        base_names.each do |base_name|
          base = lookup_type(base_name)
          next unless base

          base.fields.each do |fn, ff|
            base_fields[fn] = ff unless fn == "_composition"
          end
        end

        type.fields.each do |fn, override|
          next if fn == "_composition"

          base = base_fields[fn]
          next unless base

          check_override_field("@#{type_name}.#{fn}", base, override)
        end
      end

      def check_override_field(label, base, override)
        unless same_base_type?(base, override)
          add_error(label, "Override changes field type",
                    base.field_type.to_s, override.field_type.to_s)
        end

        if base.required && !override.required
          add_error(label, "Override relaxes required field to optional", "required", "optional")
        end

        if !base.nullable && override.nullable
          add_error(label, "Override adds nullability", "non-nullable", "nullable")
        end

        base_bounds = find_bounds(base)
        override_bounds = find_bounds(override)
        if base_bounds && override_bounds && widens_bounds?(base_bounds, override_bounds)
          add_error(label, "Override widens constraint bounds",
                    bounds_label(base_bounds), bounds_label(override_bounds))
        end
      end

      def validate_intersection_conflicts(type_name, member_names_list)
        seen = {}
        member_names_list.each do |member_name|
          member = lookup_type(member_name)
          next unless member

          member.fields.each do |fn, ff|
            next if fn == "_composition"

            prior = seen[fn]
            if prior && !same_field_definition?(prior[:field], ff)
              add_error(
                "@#{type_name}.#{fn}",
                "Intersection field conflict: '#{fn}' differs between @#{prior[:member]} and @#{member_name}",
                "identical field definitions",
                "conflicting definitions"
              )
            elsif prior.nil?
              seen[fn] = { member: member_name, field: ff }
            end
          end
        end
      end

      # ── Path-level compositions ({path} = @base :override) ──

      def validate_path_compositions
        @schema.fields.each do |path, field|
          next unless path.end_with?("._composition")
          next unless field.type_ref

          parent_path = path[0...-("._composition".length)]
          members = member_names(field.type_ref)

          if field.immutable
            base_fields = {}
            members.each do |base_name|
              base = lookup_type(base_name)
              next unless base

              base.fields.each do |fn, ff|
                base_fields[fn] = ff unless fn == "_composition"
              end
            end

            @schema.fields.each do |field_path, override|
              next unless field_path.start_with?("#{parent_path}.")
              next if field_path.end_with?("._composition")

              local_name = field_path[(parent_path.length + 1)..]
              next if local_name.include?(".")

              base = base_fields[local_name]
              next unless base

              check_override_field(field_path, base, override)
            end
          elsif members.length > 1
            validate_intersection_conflicts(parent_path, members)
          end
        end
      end

      # ── Tabular column rules ──

      def validate_tabular_columns
        @schema.arrays.each do |array_path, array|
          next unless array.columns

          array.columns.each do |column|
            label = "#{array_path}[].#{column}"

            if multi_level_column?(column)
              add_error(label, "Tabular column uses multi-level path", "single-level column", column)
              next
            end

            item_name = column.sub(/\[\d+\]\z/, "")
            field = array.item_fields[item_name] || array.item_fields[column]
            next unless field

            unless primitive_column_type?(field)
              add_error(label, "Tabular column must be a primitive type",
                        "primitive", column_type_label(field))
            end
          end
        end
      end

      def multi_level_column?(column)
        dot_count = column.count(".")
        index_count = column.scan(/\[\d+\]/).length
        return true if dot_count > 1 || index_count > 1
        return true if dot_count == 1 && index_count == 1

        false
      end

      def primitive_column_type?(field)
        return false if field.type_ref
        return false if field.field_type == Types::SchemaFieldType::REFERENCE

        if field.union?
          return field.union_members.all? { |m| PRIMITIVE_TYPES.include?(m) }
        end

        PRIMITIVE_TYPES.include?(field.field_type)
      end

      def column_type_label(field)
        return field.type_ref if field.type_ref

        field.field_type.to_s
      end

      # ── Default value rules ──

      def validate_defaults
        @schema.fields.each do |path, field|
          next if path.end_with?("._composition")

          check_default(path, field)
        end

        @schema.types.each do |type_name, type|
          type.fields.each do |fn, field|
            next if fn == "_composition"

            check_default("@#{type_name}.#{fn}", field)
          end
        end

        @schema.arrays.each do |array_path, array|
          array.item_fields.each do |fn, field|
            check_default("#{array_path}[].#{fn}", field)
          end
        end
      end

      def check_default(label, field)
        return if field.default_value.nil?

        if field.required
          add_error(label, "Required field cannot have a default value",
                    "no default", "default present")
          return
        end

        unless default_satisfies_constraints?(field, field.default_value)
          add_error(label, "Default value violates field constraints",
                    "value within constraints", describe_value(field.default_value))
        end
      end

      def default_satisfies_constraints?(field, value)
        field.constraints.each do |constraint|
          case constraint.kind
          when :bounds
            return false unless bounds_satisfied?(constraint, value)
          when :enum
            return false unless value.string? && constraint.values.include?(value.value)
          when :pattern
            if value.string?
              begin
                return false unless Regexp.new(constraint.pattern).match?(value.value)
              rescue RegexpError
                # invalid pattern handled elsewhere
              end
            end
          end
        end
        true
      end

      def bounds_satisfied?(constraint, value)
        target =
          if value.numeric?
            value.value.to_f
          elsif value.string?
            value.value.length
          end
        return true if target.nil?

        return false if constraint.min && target < constraint.min.to_f
        return false if constraint.max && target > constraint.max.to_f

        true
      end

      # ── Helpers ──

      def same_base_type?(base, override)
        base.field_type == override.field_type
      end

      def find_bounds(field)
        field.constraints.find { |c| c.kind == :bounds }
      end

      def bounds_label(bounds)
        "(#{bounds.min}..#{bounds.max})"
      end

      # A bounds override widens if it loosens either end relative to the base.
      def widens_bounds?(base, override)
        if base.min
          return true if override.min.nil? || override.min.to_f < base.min.to_f
        end
        if base.max
          return true if override.max.nil? || override.max.to_f > base.max.to_f
        end
        false
      end

      def same_field_definition?(a, b)
        return false if a.field_type != b.field_type
        return false if a.required != b.required
        return false if a.nullable != b.nullable

        constraint_signature(a) == constraint_signature(b)
      end

      def constraint_signature(field)
        field.constraints.map do |c|
          case c.kind
          when :bounds then [:bounds, c.min, c.max, c.exclusive_min, c.exclusive_max]
          when :enum then [:enum, c.values]
          when :pattern then [:pattern, c.pattern]
          when :format then [:format, c.format_name]
          when :decimal_places then [:decimal_places, c.places]
          else [c.kind]
          end
        end
      end

      def describe_value(value)
        if value.numeric? || value.string? || value.boolean?
          value.value
        else
          value.type.to_s
        end
      end
    end
  end
end
