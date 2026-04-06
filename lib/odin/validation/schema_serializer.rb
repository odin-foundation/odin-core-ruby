# frozen_string_literal: true

require "set"

module Odin
  module Validation
    class SchemaSerializer
      # Serialize an OdinSchema back to ODIN text
      def serialize(schema)
        lines = []

        # 1. Metadata header
        unless schema.metadata.empty?
          lines << "{$}"
          schema.metadata.each do |key, value|
            lines << "#{key} = \"#{escape_string(value.to_s)}\""
          end
          lines << ""
        end

        # 2. Import directives
        schema.imports.each do |imp|
          if imp.alias_name
            lines << "@import \"#{imp.path}\" as #{imp.alias_name}"
          else
            lines << "@import \"#{imp.path}\""
          end
        end
        lines << "" unless schema.imports.empty?

        # 3. Type definitions
        schema.types.each do |type_name, schema_type|
          lines << "{@#{type_name}}"

          # Composition
          if schema_type.composition
            lines << "= #{schema_type.composition}"
          end

          schema_type.fields.each do |field_name, field|
            lines << serialize_field(field_name, field)
          end

          # Object constraints for this type
          if schema.object_constraints[type_name]
            schema.object_constraints[type_name].each do |constraint|
              lines << serialize_object_constraint(constraint)
            end
          end

          lines << ""
        end

        # 4. Root fields
        unless schema.fields.empty?
          # Group by section
          root_fields = {}
          sectioned_fields = Hash.new { |h, k| h[k] = {} }

          schema.fields.each do |path, field|
            parts = path.split(".", 2)
            if parts.length > 1
              sectioned_fields[parts[0]][parts[1]] = field
            else
              root_fields[path] = field
            end
          end

          root_fields.each do |name, field|
            lines << serialize_field(name, field)
          end
          lines << "" unless root_fields.empty?

          sectioned_fields.each do |section, fields|
            lines << "{#{section}}"
            fields.each do |name, field|
              lines << serialize_field(name, field)
            end

            if schema.object_constraints[section]
              schema.object_constraints[section].each do |constraint|
                lines << serialize_object_constraint(constraint)
              end
            end

            lines << ""
          end
        end

        # 5. Array definitions
        schema.arrays.each do |array_path, schema_array|
          header = "{#{array_path}[]"
          if schema_array.columns && !schema_array.columns.empty?
            header += " : #{schema_array.columns.join(', ')}"
          end
          header += "}"
          lines << header

          # Array-level constraints
          bounds_parts = []
          if schema_array.min_items || schema_array.max_items
            min_str = schema_array.min_items&.to_s || ""
            max_str = schema_array.max_items&.to_s || ""
            bounds_parts << ":(#{min_str}..#{max_str})"
          end
          bounds_parts << ":unique" if schema_array.unique
          lines << bounds_parts.join("") unless bounds_parts.empty?

          schema_array.item_fields.each do |field_name, field|
            lines << serialize_field(field_name, field)
          end

          if schema.object_constraints[array_path]
            schema.object_constraints[array_path].each do |constraint|
              lines << serialize_object_constraint(constraint)
            end
          end

          lines << ""
        end

        # 6. Orphan object constraints (not already output with types/fields/arrays)
        outputted_scopes = Set.new
        schema.types.each_key { |k| outputted_scopes.add(k) }
        schema.arrays.each_key { |k| outputted_scopes.add(k) }
        # Sectioned fields
        schema.fields.each_key do |path|
          parts = path.split(".", 2)
          outputted_scopes.add(parts[0]) if parts.length > 1
        end
        outputted_scopes.add("") # root constraints handled inline

        schema.object_constraints.each do |scope, constraints|
          next if outputted_scopes.include?(scope)
          lines << "{#{scope}}" unless scope.empty?
          constraints.each do |constraint|
            lines << serialize_object_constraint(constraint)
          end
          lines << ""
        end

        lines.join("\n").rstrip + "\n"
      end

      private

      def serialize_field(name, field)
        parts = [name, "="]
        spec = []

        # Modifiers
        spec << "!" if field.required
        spec << "~" if field.nullable
        spec << "*" if field.redacted
        spec << "-" if field.deprecated

        # Type
        type_str = serialize_type(field.field_type, field.type_ref)
        spec << type_str unless type_str.empty?

        # Constraints
        field.constraints.each do |constraint|
          spec << serialize_constraint(constraint)
        end

        # Directives
        spec << ":computed" if field.computed
        spec << ":immutable" if field.immutable

        # Conditionals
        field.conditionals.each do |cond|
          prefix = cond.unless ? ":unless" : ":if"
          if cond.value == "true" && cond.operator == "="
            spec << "#{prefix} #{cond.field}"
          else
            spec << "#{prefix} #{cond.field} #{cond.operator} #{cond.value}"
          end
        end

        # Default value
        spec << field.default_value.to_s if field.default_value

        spec_str = spec.join("")
        # Schema field values must be quoted strings for ODIN parsing
        "#{name} = \"#{escape_string(spec_str)}\"".rstrip
      end

      def serialize_type(field_type, type_ref)
        case field_type
        when Types::SchemaFieldType::STRING    then ""
        when Types::SchemaFieldType::INTEGER   then "##"
        when Types::SchemaFieldType::NUMBER    then "#"
        when Types::SchemaFieldType::BOOLEAN   then "?"
        when Types::SchemaFieldType::CURRENCY  then "#$"
        when Types::SchemaFieldType::PERCENT   then "#%"
        when Types::SchemaFieldType::DATE      then "date"
        when Types::SchemaFieldType::TIMESTAMP then "timestamp"
        when Types::SchemaFieldType::TIME      then "time"
        when Types::SchemaFieldType::DURATION  then "duration"
        when Types::SchemaFieldType::REFERENCE then type_ref ? "@#{type_ref}" : "@"
        when Types::SchemaFieldType::BINARY    then "^"
        when Types::SchemaFieldType::NULL      then "~"
        when Types::SchemaFieldType::ANY       then ""
        else ""
        end
      end

      def serialize_constraint(constraint)
        case constraint
        when Types::BoundsConstraint
          min_str = constraint.min&.to_s || ""
          max_str = constraint.max&.to_s || ""
          if constraint.min == constraint.max && constraint.min
            ":(#{min_str})"
          else
            ":(#{min_str}..#{max_str})"
          end
        when Types::PatternConstraint
          ":/#{constraint.pattern}/"
        when Types::EnumConstraint
          "(#{constraint.values.join(', ')})"
        when Types::SizeConstraint
          min_str = constraint.min_length&.to_s || ""
          max_str = constraint.max_length&.to_s || ""
          ":(#{min_str}..#{max_str})"
        when Types::FormatConstraint
          ":format #{constraint.format_name}"
        when Types::UniqueConstraint
          ":unique"
        else
          ""
        end
      end

      def serialize_object_constraint(constraint)
        case constraint
        when Types::SchemaInvariant
          ":invariant #{constraint.expression}"
        when Types::SchemaCardinality
          case constraint.cardinality_type
          when "of"
            min_str = constraint.min&.to_s || ""
            max_str = constraint.max&.to_s || ""
            ":of (#{min_str}..#{max_str}) #{constraint.fields.join(', ')}"
          when "one_of"
            ":one_of #{constraint.fields.join(', ')}"
          when "exactly_one"
            ":exactly_one #{constraint.fields.join(', ')}"
          when "at_most_one"
            ":at_most_one #{constraint.fields.join(', ')}"
          end
        else
          ""
        end
      end

      def escape_string(str)
        str.gsub("\\", "\\\\").gsub('"', '\\"').gsub("\n", "\\n").gsub("\t", "\\t")
      end
    end
  end
end
