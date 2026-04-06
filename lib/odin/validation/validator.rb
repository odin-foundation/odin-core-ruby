# frozen_string_literal: true

module Odin
  module Validation
    class Validator
      # Validate an OdinDocument against an OdinSchema
      # Returns ValidationResult
      def validate(doc, schema, options = {})
        @errors = []
        @doc = doc
        @schema = schema
        @strict = options.fetch(:strict, false)

        # V001: Required fields
        check_required_fields

        # V002: Type matches
        check_type_matches

        # V003: Bounds constraints
        check_bounds_constraints

        # V004: Pattern constraints
        check_pattern_constraints

        # V004 (format): Format constraints
        check_format_constraints

        # V005: Enum constraints
        check_enum_constraints

        # V006: Array length constraints
        check_array_lengths

        # V007: Uniqueness constraints
        check_uniqueness

        # V008: Invariant validation
        check_invariants

        # V009: Cardinality constraints
        check_cardinality

        # V010: Conditional requirements
        check_conditionals

        # V011: Unknown fields (strict mode)
        check_unknown_fields if @strict

        # V012: Circular references
        check_circular_references

        # V013: Unresolved references
        check_unresolved_references

        Errors::ValidationResult.new(@errors)
      end

      private

      def add_error(code:, path:, message:, expected: nil, actual: nil)
        @errors << Errors::ValidationError.new(
          code: code,
          path: path,
          message: message,
          expected: expected,
          actual: actual
        )
      end

      # ── V001: Required field missing ──

      def check_required_fields
        # Check root-level fields
        @schema.fields.each do |path, field|
          next unless field.required
          next if field.computed
          next if has_active_conditional?(field) # handled by V010

          unless doc_has_value?(path)
            add_error(
              code: Errors::ValidationErrorCode::REQUIRED_FIELD_MISSING,
              path: path,
              message: "Required field '#{path}' is missing",
              expected: "present"
            )
          end
        end

        # Check type-level fields — only when the type is used as an inline object
        # in the document (not when it's just a type definition via {@ ...}).
        # Type definitions like {@address} define structure but don't require
        # the fields to exist at the type-name path. They are checked when
        # a field references the type (e.g., home = @address means check
        # home.street, home.city).
        @schema.types.each do |type_name, schema_type|
          # Find all fields that reference this type
          type_usage_paths = find_type_usage_paths(type_name)

          if type_usage_paths.empty?
            # Check if the type is used directly in the document at its own path
            schema_type.fields.each do |field_name, field|
              next unless field.required
              next if field.computed
              next if has_active_conditional?(field)

              full_path = "#{type_name}.#{field_name}"
              # Only check if the type section actually exists in the document
              next unless doc_section_exists?(type_name)
              unless doc_has_value?(full_path)
                add_error(
                  code: Errors::ValidationErrorCode::REQUIRED_FIELD_MISSING,
                  path: full_path,
                  message: "Required field '#{full_path}' is missing",
                  expected: "present"
                )
              end
            end
          else
            # Check required fields at each usage path
            type_usage_paths.each do |usage_path|
              schema_type.fields.each do |field_name, field|
                next unless field.required
                next if field.computed
                next if has_active_conditional?(field)

                full_path = "#{usage_path}.#{field_name}"
                unless doc_has_value?(full_path)
                  add_error(
                    code: Errors::ValidationErrorCode::REQUIRED_FIELD_MISSING,
                    path: full_path,
                    message: "Required field '#{full_path}' is missing",
                    expected: "present"
                  )
                end
              end
            end
          end
        end

        # Check array item fields
        @schema.arrays.each do |array_path, schema_array|
          check_array_item_required_fields(array_path, schema_array)
        end
      end

      def check_array_item_required_fields(array_path, schema_array)
        # Find all array items in the document
        item_count = count_array_items(array_path)
        return if item_count == 0

        schema_array.item_fields.each do |field_name, field|
          next unless field.required
          next if field.computed

          item_count.times do |i|
            # Try both path formats
            full_path = "#{array_path}[#{i}].#{field_name}"
            alt_path = "#{array_path}[].[#{i}].#{field_name}"
            unless doc_has_value?(full_path) || doc_has_value?(alt_path)
              add_error(
                code: Errors::ValidationErrorCode::REQUIRED_FIELD_MISSING,
                path: full_path,
                message: "Required field '#{field_name}' is missing in #{array_path}[#{i}]",
                expected: "present"
              )
            end
          end
        end
      end

      # ── V002: Type mismatch ──

      def check_type_matches
        each_schema_field do |path, field, value|
          next if value.nil? || value.null?
          expected_type = field.field_type
          next if expected_type == Types::SchemaFieldType::ANY

          actual_type = value_to_schema_type(value)
          next if types_compatible?(expected_type, actual_type, value)

          add_error(
            code: Errors::ValidationErrorCode::TYPE_MISMATCH,
            path: path,
            message: "Expected type '#{expected_type}' but got '#{actual_type}' at '#{path}'",
            expected: expected_type.to_s,
            actual: actual_type.to_s
          )
        end
      end

      def types_compatible?(expected, actual, value)
        return true if expected == actual
        return true if expected == Types::SchemaFieldType::ANY

        # Number accepts integer
        return true if expected == Types::SchemaFieldType::NUMBER &&
                       actual == Types::SchemaFieldType::INTEGER

        # Currency is a numeric type
        return true if expected == Types::SchemaFieldType::NUMBER &&
                       actual == Types::SchemaFieldType::CURRENCY

        # String accepts date, timestamp, time, duration (they are string subtypes)
        return true if expected == Types::SchemaFieldType::STRING &&
                       [Types::SchemaFieldType::DATE, Types::SchemaFieldType::TIMESTAMP,
                        Types::SchemaFieldType::TIME, Types::SchemaFieldType::DURATION].include?(actual)

        # Nullable fields accept null
        return true if actual == Types::SchemaFieldType::NULL

        false
      end

      def value_to_schema_type(value)
        case value
        when Types::OdinString then Types::SchemaFieldType::STRING
        when Types::OdinInteger then Types::SchemaFieldType::INTEGER
        when Types::OdinNumber then Types::SchemaFieldType::NUMBER
        when Types::OdinBoolean then Types::SchemaFieldType::BOOLEAN
        when Types::OdinCurrency then Types::SchemaFieldType::CURRENCY
        when Types::OdinPercent then Types::SchemaFieldType::PERCENT
        when Types::OdinDate then Types::SchemaFieldType::DATE
        when Types::OdinTimestamp then Types::SchemaFieldType::TIMESTAMP
        when Types::OdinTime then Types::SchemaFieldType::TIME
        when Types::OdinDuration then Types::SchemaFieldType::DURATION
        when Types::OdinReference then Types::SchemaFieldType::REFERENCE
        when Types::OdinBinary then Types::SchemaFieldType::BINARY
        when Types::OdinNull then Types::SchemaFieldType::NULL
        else Types::SchemaFieldType::STRING
        end
      end

      # ── V003: Value out of bounds ──

      def check_bounds_constraints
        each_schema_field_with_constraints(:bounds) do |path, field, value, constraint|
          next if value.nil? || value.null?
          check_single_bounds(path, field, value, constraint)
        end
      end

      def check_single_bounds(path, field, value, constraint)
        if value.numeric?
          num = value.value.to_f
          check_numeric_bounds(path, num, constraint)
        elsif value.string?
          len = value.value.length
          check_numeric_bounds(path, len, constraint, label: "length")
        elsif value.date? || value.timestamp?
          check_date_bounds(path, value, constraint)
        end
      end

      def check_numeric_bounds(path, num, constraint, label: "value")
        if constraint.min
          min_val = constraint.min.to_f
          if constraint.exclusive_min
            unless num > min_val
              add_error(
                code: Errors::ValidationErrorCode::VALUE_OUT_OF_BOUNDS,
                path: path,
                message: "#{label.capitalize} #{num} must be greater than #{constraint.min} at '#{path}'",
                expected: "> #{constraint.min}",
                actual: num.to_s
              )
            end
          else
            unless num >= min_val
              add_error(
                code: Errors::ValidationErrorCode::VALUE_OUT_OF_BOUNDS,
                path: path,
                message: "#{label.capitalize} #{num} is below minimum #{constraint.min} at '#{path}'",
                expected: ">= #{constraint.min}",
                actual: num.to_s
              )
            end
          end
        end

        if constraint.max
          max_val = constraint.max.to_f
          if constraint.exclusive_max
            unless num < max_val
              add_error(
                code: Errors::ValidationErrorCode::VALUE_OUT_OF_BOUNDS,
                path: path,
                message: "#{label.capitalize} #{num} must be less than #{constraint.max} at '#{path}'",
                expected: "< #{constraint.max}",
                actual: num.to_s
              )
            end
          else
            unless num <= max_val
              add_error(
                code: Errors::ValidationErrorCode::VALUE_OUT_OF_BOUNDS,
                path: path,
                message: "#{label.capitalize} #{num} exceeds maximum #{constraint.max} at '#{path}'",
                expected: "<= #{constraint.max}",
                actual: num.to_s
              )
            end
          end
        end
      end

      def check_date_bounds(path, value, constraint)
        val_str = value.to_s
        if constraint.min && val_str < constraint.min.to_s
          add_error(
            code: Errors::ValidationErrorCode::VALUE_OUT_OF_BOUNDS,
            path: path,
            message: "Date #{val_str} is before minimum #{constraint.min} at '#{path}'",
            expected: ">= #{constraint.min}",
            actual: val_str
          )
        end
        if constraint.max && val_str > constraint.max.to_s
          add_error(
            code: Errors::ValidationErrorCode::VALUE_OUT_OF_BOUNDS,
            path: path,
            message: "Date #{val_str} is after maximum #{constraint.max} at '#{path}'",
            expected: "<= #{constraint.max}",
            actual: val_str
          )
        end
      end

      # ── V004: Pattern mismatch ──

      def check_pattern_constraints
        each_schema_field_with_constraints(:pattern) do |path, field, value, constraint|
          next if value.nil? || value.null?
          next unless value.string?

          # ReDoS check
          unless ReDoSProtection.safe?(constraint.pattern)
            add_error(
              code: Errors::ValidationErrorCode::PATTERN_MISMATCH,
              path: path,
              message: "Unsafe regex pattern rejected at '#{path}'"
            )
            next
          end

          begin
            regex = Regexp.new(constraint.pattern)
            result = ReDoSProtection.safe_test(regex, value.value)
            if result[:reason] == :value_too_long
              add_error(
                code: Errors::ValidationErrorCode::PATTERN_MISMATCH,
                path: path,
                message: "Value too long for pattern validation at '#{path}'"
              )
            elsif result[:timed_out]
              add_error(
                code: Errors::ValidationErrorCode::PATTERN_MISMATCH,
                path: path,
                message: "Pattern validation timed out at '#{path}'"
              )
            elsif !result[:matched]
              add_error(
                code: Errors::ValidationErrorCode::PATTERN_MISMATCH,
                path: path,
                message: "Value '#{value.value}' does not match pattern /#{constraint.pattern}/ at '#{path}'",
                expected: constraint.pattern,
                actual: value.value
              )
            end
          rescue RegexpError => e
            add_error(
              code: Errors::ValidationErrorCode::PATTERN_MISMATCH,
              path: path,
              message: "Invalid regex pattern: #{e.message} at '#{path}'"
            )
          end
        end
      end

      # ── V005: Invalid enum value ──

      def check_enum_constraints
        each_schema_field_with_constraints(:enum) do |path, field, value, constraint|
          next if value.nil? || value.null?

          val_str = extract_value_for_comparison(value)
          unless constraint.values.include?(val_str)
            add_error(
              code: Errors::ValidationErrorCode::INVALID_ENUM_VALUE,
              path: path,
              message: "Value '#{val_str}' is not one of allowed values [#{constraint.values.join(', ')}] at '#{path}'",
              expected: constraint.values.join(", "),
              actual: val_str
            )
          end
        end
      end

      # ── V006: Array length violation ──

      def check_array_lengths
        @schema.arrays.each do |array_path, schema_array|
          count = count_array_items(array_path)
          # For max_items, only validate if array exists
          # For min_items, always validate (0 items < min is a violation)

          if schema_array.min_items && count < schema_array.min_items
            add_error(
              code: Errors::ValidationErrorCode::ARRAY_LENGTH_VIOLATION,
              path: array_path,
              message: "Array '#{array_path}' has #{count} items, minimum is #{schema_array.min_items}",
              expected: ">= #{schema_array.min_items}",
              actual: count.to_s
            )
          end

          if schema_array.max_items && count > schema_array.max_items
            add_error(
              code: Errors::ValidationErrorCode::ARRAY_LENGTH_VIOLATION,
              path: array_path,
              message: "Array '#{array_path}' has #{count} items, maximum is #{schema_array.max_items}",
              expected: "<= #{schema_array.max_items}",
              actual: count.to_s
            )
          end
        end
      end

      # ── V007: Uniqueness constraint violation ──

      def check_uniqueness
        @schema.arrays.each do |array_path, schema_array|
          next unless schema_array.unique

          count = count_array_items(array_path)
          next if count <= 1

          # Collect values for uniqueness check
          seen = {}
          count.times do |i|
            # Get all fields for this item
            item_key = collect_item_values(array_path, i)
            if seen.key?(item_key)
              add_error(
                code: Errors::ValidationErrorCode::UNIQUE_CONSTRAINT_VIOLATION,
                path: array_path,
                message: "Duplicate item at index #{i} in array '#{array_path}'",
                expected: "unique items",
                actual: "duplicate of index #{seen[item_key]}"
              )
            else
              seen[item_key] = i
            end
          end
        end

        # Check unique constraints on individual fields
        each_schema_field_with_constraints(:unique) do |path, field, value, constraint|
          # Unique constraint on a field within an array — check uniqueness across items
          check_field_uniqueness_in_array(path, field, constraint)
        end
      end

      def check_field_uniqueness_in_array(path, field, constraint)
        # Determine if this field is inside an array
        parts = path.split(".")
        return unless parts.length >= 2

        array_path = parts[0...-1].join(".")
        field_name = parts.last
        count = count_array_items(array_path)
        return if count <= 1

        seen = {}
        count.times do |i|
          item_path = "#{array_path}[#{i}].#{field_name}"
          value = @doc.get(item_path)
          next unless value

          val_str = extract_value_for_comparison(value)
          if seen.key?(val_str)
            add_error(
              code: Errors::ValidationErrorCode::UNIQUE_CONSTRAINT_VIOLATION,
              path: item_path,
              message: "Duplicate value '#{val_str}' for unique field '#{field_name}' at index #{i}",
              expected: "unique",
              actual: val_str
            )
          else
            seen[val_str] = i
          end
        end
      end

      # ── V008: Invariant violation ──

      def check_invariants
        @schema.object_constraints.each do |scope, constraints|
          constraints.each do |constraint|
            next unless constraint.is_a?(Types::SchemaInvariant)
            evaluate_invariant(scope, constraint)
          end
        end
      end

      def evaluate_invariant(scope, invariant)
        expr = invariant.expression
        # Parse simple binary expressions: field OPERATOR value_or_field
        match = expr.match(/\A(\S+)\s*(>=|<=|!=|==|>|<|=)\s*(.+)\z/)
        return unless match

        left_field = match[1]
        operator = match[2]
        right_expr = match[3].strip

        left_path = scope.empty? ? left_field : "#{scope}.#{left_field}"
        left_value = @doc.get(left_path)
        return unless left_value # Can't evaluate if field missing

        # Right side might be a field reference or a literal
        right_path = scope.empty? ? right_expr : "#{scope}.#{right_expr}"
        right_value = @doc.get(right_path)

        if right_value
          # Compare two field values
          result = compare_values(left_value, operator, right_value)
        else
          # Compare field to literal
          result = compare_value_to_literal(left_value, operator, right_expr)
        end

        unless result
          add_error(
            code: Errors::ValidationErrorCode::INVARIANT_VIOLATION,
            path: scope,
            message: "Invariant '#{expr}' violated at '#{scope}'",
            expected: expr
          )
        end
      end

      def compare_values(left, operator, right)
        lv = extract_numeric_value(left)
        rv = extract_numeric_value(right)

        if lv && rv
          case operator
          when ">", ">"  then lv > rv
          when "<"       then lv < rv
          when ">=", ">=" then lv >= rv
          when "<=", "<=" then lv <= rv
          when "=", "==" then lv == rv
          when "!="      then lv != rv
          else false
          end
        else
          ls = extract_value_for_comparison(left)
          rs = extract_value_for_comparison(right)
          case operator
          when "=", "==" then ls == rs
          when "!="      then ls != rs
          else false
          end
        end
      end

      def compare_value_to_literal(value, operator, literal)
        nv = extract_numeric_value(value)
        nl = Float(literal) rescue nil

        if nv && nl
          case operator
          when ">"       then nv > nl
          when "<"       then nv < nl
          when ">=", ">=" then nv >= nl
          when "<=", "<=" then nv <= nl
          when "=", "==" then nv == nl
          when "!="      then nv != nl
          else false
          end
        else
          vs = extract_value_for_comparison(value)
          case operator
          when "=", "==" then vs == literal
          when "!="      then vs != literal
          else false
          end
        end
      end

      # ── V009: Cardinality constraint violation ──

      def check_cardinality
        @schema.object_constraints.each do |scope, constraints|
          constraints.each do |constraint|
            next unless constraint.is_a?(Types::SchemaCardinality)
            evaluate_cardinality(scope, constraint)
          end
        end
      end

      def evaluate_cardinality(scope, constraint)
        # Count how many of the listed fields are present and non-null
        count = 0
        constraint.fields.each do |field_name|
          path = scope.empty? ? field_name : "#{scope}.#{field_name}"
          value = @doc.get(path)
          count += 1 if value && !value.null?
        end

        case constraint.cardinality_type
        when "of"
          if constraint.min && count < constraint.min
            add_error(
              code: Errors::ValidationErrorCode::CARDINALITY_CONSTRAINT_VIOLATION,
              path: scope,
              message: "At least #{constraint.min} of [#{constraint.fields.join(', ')}] required at '#{scope}', found #{count}",
              expected: ">= #{constraint.min}",
              actual: count.to_s
            )
          end
          if constraint.max && count > constraint.max
            add_error(
              code: Errors::ValidationErrorCode::CARDINALITY_CONSTRAINT_VIOLATION,
              path: scope,
              message: "At most #{constraint.max} of [#{constraint.fields.join(', ')}] allowed at '#{scope}', found #{count}",
              expected: "<= #{constraint.max}",
              actual: count.to_s
            )
          end
        when "one_of"
          unless count >= 1
            add_error(
              code: Errors::ValidationErrorCode::CARDINALITY_CONSTRAINT_VIOLATION,
              path: scope,
              message: "At least one of [#{constraint.fields.join(', ')}] required at '#{scope}'",
              expected: ">= 1",
              actual: count.to_s
            )
          end
        when "exactly_one"
          unless count == 1
            add_error(
              code: Errors::ValidationErrorCode::CARDINALITY_CONSTRAINT_VIOLATION,
              path: scope,
              message: "Exactly one of [#{constraint.fields.join(', ')}] required at '#{scope}', found #{count}",
              expected: "1",
              actual: count.to_s
            )
          end
        when "at_most_one"
          unless count <= 1
            add_error(
              code: Errors::ValidationErrorCode::CARDINALITY_CONSTRAINT_VIOLATION,
              path: scope,
              message: "At most one of [#{constraint.fields.join(', ')}] allowed at '#{scope}', found #{count}",
              expected: "<= 1",
              actual: count.to_s
            )
          end
        end
      end

      # ── V010: Conditional requirement not met ──

      def check_conditionals
        each_schema_field_with_conditionals do |path, field, conditionals|
          conditionals.each do |cond|
            # Resolve the condition field value from the document
            cond_field_path = resolve_conditional_field(path, cond.field)
            cond_value = @doc.get(cond_field_path)

            # If condition field doesn't exist, skip
            next unless cond_value

            # Evaluate the condition
            is_met = cond.evaluate(extract_value_for_comparison(cond_value))

            if is_met && field.required && !doc_has_value?(path)
              add_error(
                code: Errors::ValidationErrorCode::CONDITIONAL_REQUIREMENT_NOT_MET,
                path: path,
                message: "Field '#{path}' is required when #{cond.field} #{cond.operator} #{cond.value}",
                expected: "present",
                actual: "missing"
              )
            end
          end
        end
      end

      def resolve_conditional_field(field_path, cond_field)
        # If the field is in a section, resolve relative to same section
        parts = field_path.split(".")
        if parts.length > 1
          section = parts[0...-1].join(".")
          "#{section}.#{cond_field}"
        else
          cond_field
        end
      end

      # ── V011: Unknown field (strict mode) ──

      def check_unknown_fields
        known_paths = collect_known_paths
        @doc.each_assignment do |path, _value|
          unless known_paths.include?(path) || path_in_known_array?(path, known_paths)
            add_error(
              code: Errors::ValidationErrorCode::UNKNOWN_FIELD,
              path: path,
              message: "Unknown field '#{path}' (strict mode)",
              expected: "known field"
            )
          end
        end
      end

      def collect_known_paths
        paths = Set.new
        @schema.fields.each_key { |p| paths.add(p) }
        @schema.types.each do |type_name, schema_type|
          schema_type.fields.each_key { |f| paths.add("#{type_name}.#{f}") }
        end
        @schema.arrays.each do |array_path, schema_array|
          schema_array.item_fields.each_key do |f|
            # Array items match pattern: path[N].field
            paths.add("#{array_path}[].#{f}")
          end
        end
        paths
      end

      def path_in_known_array?(path, known_paths)
        # Check if path matches an array item pattern
        @schema.arrays.each do |array_path, schema_array|
          escaped = Regexp.escape(array_path)
          # Support both formats: items[0].field and items[].[0].field
          if path.start_with?("#{array_path}[")
            # Format: items[0].field
            match = path.match(/\A#{escaped}\[\d+\]\.(.+)\z/)
            if match
              field_name = match[1]
              return true if schema_array.item_fields.key?(field_name)
            end
            return true if path.match?(/\A#{escaped}\[\d+\]\z/)

            # Format: items[].[0].field
            match = path.match(/\A#{escaped}\[\]\.\[(\d+)\]\.(.+)\z/)
            if match
              field_name = match[2]
              return true if schema_array.item_fields.key?(field_name)
            end
            return true if path.match?(/\A#{escaped}\[\]\.\[\d+\]\z/)
          end
        end
        false
      end

      # ── V012: Circular reference ──

      def check_circular_references
        # Check if any reference values in the document create cycles
        @doc.each_assignment do |path, value|
          next unless value.is_a?(Types::OdinReference)
          visited = Set.new([path])
          check_ref_cycle(value.path, visited, path)
        end

        # Check schema-level type reference cycles
        check_schema_type_cycles
      end

      def check_ref_cycle(ref_path, visited, origin_path)
        return if visited.size > 100 # safety limit

        if visited.include?(ref_path)
          add_error(
            code: Errors::ValidationErrorCode::CIRCULAR_REFERENCE,
            path: origin_path,
            message: "Circular reference detected: #{origin_path} -> #{ref_path}"
          )
          return
        end

        target = @doc.get(ref_path)
        return unless target.is_a?(Types::OdinReference)

        visited.add(ref_path)
        check_ref_cycle(target.path, visited, origin_path)
      end

      def check_schema_type_cycles
        # Build a graph of type references from schema types
        type_refs = {}
        @schema.types.each do |type_name, schema_type|
          refs = []
          schema_type.fields.each do |_field_name, field|
            if field.type_ref
              clean_ref = field.type_ref.sub(/\A@+/, "")
              refs << clean_ref if @schema.types.key?(clean_ref)
            end
          end
          type_refs[type_name] = refs unless refs.empty?
        end

        # Detect cycles using DFS
        type_refs.each_key do |start_type|
          visited = Set.new
          check_type_cycle(start_type, start_type, visited, type_refs)
        end
      end

      def check_type_cycle(current, start_type, visited, type_refs)
        return if visited.include?(current)
        visited.add(current)

        (type_refs[current] || []).each do |ref|
          if ref == start_type
            add_error(
              code: Errors::ValidationErrorCode::CIRCULAR_REFERENCE,
              path: "@#{start_type}",
              message: "Circular reference detected in schema types: @#{start_type} -> @#{current} -> @#{ref}"
            )
            return
          end
          check_type_cycle(ref, start_type, visited, type_refs)
        end
      end

      # ── V013: Unresolved reference ──

      def check_unresolved_references
        @doc.each_assignment do |path, value|
          next unless value.is_a?(Types::OdinReference)

          ref_path = value.path
          unless @doc.include?(ref_path) || ref_path_matches_any?(ref_path)
            add_error(
              code: Errors::ValidationErrorCode::UNRESOLVED_REFERENCE,
              path: path,
              message: "Reference '@#{ref_path}' at '#{path}' does not resolve to any path",
              expected: "valid path",
              actual: ref_path
            )
          end
        end

        # Also check type references in schema
        @schema.fields.each do |path, field|
          next unless field.type_ref
          check_type_reference(path, field.type_ref)
        end
      end

      def check_type_reference(path, type_ref)
        # Strip leading @ or @@ from type reference for lookup
        clean_ref = type_ref.sub(/\A@+/, "")
        return if @schema.types.key?(type_ref)
        return if @schema.types.key?(clean_ref)
        # Check with namespace prefixes
        return if @schema.types.any? { |name, _| name.end_with?(clean_ref) }

        add_error(
          code: Errors::ValidationErrorCode::UNRESOLVED_REFERENCE,
          path: path,
          message: "Type reference '@@#{clean_ref}' at '#{path}' does not resolve to any type",
          expected: "valid type name",
          actual: type_ref
        )
      end

      def ref_path_matches_any?(ref_path)
        # Check if ref_path with wildcard matches any document path
        return false unless ref_path.include?("*")
        pattern = Regexp.new("\\A#{ref_path.gsub('*', '.*')}\\z")
        @doc.paths.any? { |p| pattern.match?(p) }
      end

      # ── Helpers ──

      def doc_has_value?(path)
        value = @doc.get(path)
        !value.nil? && !value.null?
      end

      def doc_section_exists?(section)
        @doc.paths.any? { |p| p == section || p.start_with?("#{section}.") || p.start_with?("#{section}[") }
      end

      # Find document paths where a type is used via type references
      def find_type_usage_paths(type_name)
        paths = []
        @schema.fields.each do |field_path, field|
          next unless field.type_ref
          clean_ref = field.type_ref.sub(/\A@+/, "")
          paths << field_path if clean_ref == type_name
        end
        paths
      end

      def array_exists?(array_path)
        @doc.paths.any? { |p| p.start_with?("#{array_path}[") || p.start_with?("#{array_path}[].") }
      end

      def count_array_items(array_path)
        max_index = -1
        # Support both path formats: "items[0].field" and "items[].[0].field"
        prefixes = ["#{array_path}[", "#{array_path}[].["]
        @doc.paths.each do |p|
          prefixes.each do |prefix|
            next unless p.start_with?(prefix)
            match = p[prefix.length..].match(/\A(\d+)/)
            if match
              idx = match[1].to_i
              max_index = idx if idx > max_index
            end
          end
        end
        max_index + 1
      end

      def collect_item_values(array_path, index)
        # Support both path formats
        prefixes = ["#{array_path}[#{index}]", "#{array_path}[].[#{index}]"]
        values = []
        @doc.each_assignment do |path, value|
          if prefixes.any? { |pfx| path.start_with?(pfx) }
            values << [path, extract_value_for_comparison(value)]
          end
        end
        values.sort_by(&:first).map { |_, v| v }.join("|")
      end

      def extract_value_for_comparison(value)
        case value
        when Types::OdinString then value.value
        when Types::OdinInteger, Types::OdinNumber, Types::OdinCurrency,
             Types::OdinPercent then value.value.to_s
        when Types::OdinBoolean then value.value.to_s
        when Types::OdinNull then ""
        when Types::OdinDate, Types::OdinTimestamp, Types::OdinTime,
             Types::OdinDuration then value.to_s
        when Types::OdinReference then value.path
        else value.to_s
        end
      end

      def extract_numeric_value(value)
        case value
        when Types::OdinInteger, Types::OdinNumber, Types::OdinCurrency, Types::OdinPercent
          value.value.to_f
        else
          nil
        end
      end

      def has_active_conditional?(field)
        !field.conditionals.empty?
      end

      # Iterate over all schema fields paired with their document values
      def each_schema_field
        @schema.fields.each do |path, field|
          value = @doc.get(path)
          yield path, field, value if value
        end

        @schema.types.each do |type_name, schema_type|
          schema_type.fields.each do |field_name, field|
            full_path = "#{type_name}.#{field_name}"
            value = @doc.get(full_path)
            yield full_path, field, value if value
          end
        end

        @schema.arrays.each do |array_path, schema_array|
          count = count_array_items(array_path)
          count.times do |i|
            schema_array.item_fields.each do |field_name, field|
              # Try both path formats
              full_path = "#{array_path}[#{i}].#{field_name}"
              value = @doc.get(full_path)
              unless value
                alt_path = "#{array_path}[].[#{i}].#{field_name}"
                value = @doc.get(alt_path)
                full_path = alt_path if value
              end
              yield full_path, field, value if value
            end
          end
        end
      end

      # Iterate over fields with a specific constraint kind
      def each_schema_field_with_constraints(kind)
        each_schema_field do |path, field, value|
          field.constraints.each do |constraint|
            yield path, field, value, constraint if constraint.kind == kind
          end
        end
      end

      # Iterate over fields with conditionals
      def each_schema_field_with_conditionals
        @schema.fields.each do |path, field|
          yield path, field, field.conditionals unless field.conditionals.empty?
        end

        @schema.types.each do |type_name, schema_type|
          schema_type.fields.each do |field_name, field|
            unless field.conditionals.empty?
              yield "#{type_name}.#{field_name}", field, field.conditionals
            end
          end
        end
      end

      # Format validation (part of V004)
      def check_format_constraints
        each_schema_field_with_constraints(:format) do |path, field, value, constraint|
          next if value.nil? || value.null?

          # For non-string values, extract string representation for format check
          if value.string?
            val_str = value.value
          elsif value.date? || value.timestamp? || value.time?
            val_str = value.to_s
          else
            next # Non-string, non-temporal values skip format checks
          end

          # date-iso: validate against YYYY-MM-DD pattern (matches TypeScript)
          if constraint.format_name == "date-iso"
            unless val_str.match?(/\A\d{4}-\d{2}-\d{2}\z/)
              add_error(
                code: Errors::ValidationErrorCode::PATTERN_MISMATCH,
                path: path,
                message: "Value does not match format 'date-iso' at '#{path}'",
                expected: "date-iso",
                actual: val_str
              )
            end
            next
          end

          unless FormatValidators.validate(constraint.format_name, val_str)
            add_error(
              code: Errors::ValidationErrorCode::PATTERN_MISMATCH,
              path: path,
              message: "Value does not match format '#{constraint.format_name}' at '#{path}'",
              expected: constraint.format_name,
              actual: val_str
            )
          end
        end
      end
    end
  end
end
