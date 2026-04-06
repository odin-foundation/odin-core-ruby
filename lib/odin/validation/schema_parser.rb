# frozen_string_literal: true

module Odin
  module Validation
    class SchemaParser
      # Core schema metadata keys (always metadata, never field definitions)
      SCHEMA_META_KEYS = %w[odin schema].freeze

      KEYWORD_TYPES = [
        ["timestamp", Types::SchemaFieldType::TIMESTAMP],
        ["datetime", Types::SchemaFieldType::TIMESTAMP],
        ["date", Types::SchemaFieldType::DATE],
        ["time", Types::SchemaFieldType::TIME],
        ["duration", Types::SchemaFieldType::DURATION],
        ["string", Types::SchemaFieldType::STRING],
        ["integer", Types::SchemaFieldType::INTEGER],
        ["number", Types::SchemaFieldType::NUMBER],
        ["boolean", Types::SchemaFieldType::BOOLEAN],
        ["currency", Types::SchemaFieldType::CURRENCY],
        ["percent", Types::SchemaFieldType::PERCENT],
        ["binary", Types::SchemaFieldType::BINARY],
        ["null", Types::SchemaFieldType::NULL],
      ].freeze

      def initialize
        @metadata = {}
        @types = {}
        @fields = {}
        @arrays = {}
        @imports = []
        @object_constraints = {}

        @current_header = nil
        @current_header_kind = :root # :root, :metadata, :type, :array, :object
        @current_type_name = nil
        @current_array_path = nil
      end

      # Parse an ODIN schema document text into an OdinSchema
      def parse_schema(text)
        lines = text.split("\n")
        lines.each do |raw_line|
          line = raw_line.strip

          if line.empty?
            # Blank line resets metadata mode to root
            if @current_header_kind == :metadata
              @current_header_kind = :root
              @current_header = nil
            end
            next
          end

          next if line.start_with?(";")

          if line.start_with?("@import ")
            parse_import(line)
          elsif line.start_with?("{") && line.include?("}")
            parse_header(line)
          elsif line.start_with?("@") && !line.include?("=")
            parse_bare_type_line(line)
          elsif line.start_with?(":")
            parse_object_constraint(line)
          elsif line.include?("=")
            parse_field_definition(line)
          end
        end

        Types::OdinSchema.new(
          metadata: @metadata,
          types: @types,
          fields: @fields,
          arrays: @arrays,
          imports: @imports,
          object_constraints: @object_constraints
        )
      end

      private

      def parse_import(line)
        parts = line[8..].strip.split
        @imports << Types::SchemaImport.new(path: parts[0]) if parts.any?
      end

      # Handle bare @TypeName lines (not inside {})
      # Supports: @TypeName, @Extended : @Base, @TypeA & @TypeB
      def parse_bare_type_line(line)
        rest = line[1..].strip
        @current_header_kind = :bare_type
        @current_array_path = nil

        # Check for inheritance: @Extended : @Base
        if rest.include?(" : ")
          parts = rest.split(" : ", 2)
          type_name = parts[0].strip
          parent_refs = parts[1].strip.split(/\s*,\s*/).map { |p| p.strip.sub(/^@/, "") }
          @current_type_name = type_name
          @types[type_name] ||= Types::SchemaType.new(name: type_name, parent_types: parent_refs)
        elsif rest.include?(" & ")
          # Intersection: @TypeA & @TypeB (this is a composed result)
          # The type name is before any & — but actually the type definition is
          # @SmallPositive\n= @Positive & @SmallNumber
          # This is handled in field_definition when = is present
          type_name = rest.strip
          @current_type_name = type_name
          @types[type_name] ||= Types::SchemaType.new(name: type_name)
        else
          type_name = rest.strip
          # Handle namespace prefix &
          namespace = nil
          if type_name.start_with?("&")
            raw = type_name[1..]
            dot_idx = raw.rindex(".")
            if dot_idx
              namespace = raw[0...dot_idx]
            end
          end
          @current_type_name = type_name
          @types[type_name] ||= Types::SchemaType.new(name: type_name, namespace: namespace)
        end

        @current_header = "@#{@current_type_name}"
      end

      def parse_header(line)
        brace_end = line.index("}")
        content = line[1...brace_end].strip
        after_header = line[(brace_end + 1)..].to_s.strip

        if content == "$" || content == "$derivation"
          @current_header = content
          @current_header_kind = :metadata
          @current_type_name = nil
          @current_array_path = nil
        elsif content.start_with?("@")
          # Type definition
          type_name = content[1..]
          @current_header = content
          @current_header_kind = :type
          @current_type_name = type_name
          @current_array_path = nil
          @types[type_name] ||= Types::SchemaType.new(name: type_name, fields: {})
        elsif content.end_with?("[]")
          # Array definition
          array_path = content[0...-2]
          @current_header = array_path
          @current_header_kind = :array
          @current_type_name = nil
          @current_array_path = array_path

          min_items = nil
          max_items = nil
          unique = false

          if after_header && !after_header.empty?
            unique, min_items, max_items = parse_array_constraint_text(after_header)
          end

          @arrays[array_path] = Types::SchemaArray.new(
            path: array_path,
            item_fields: {},
            min_items: min_items,
            max_items: max_items,
            unique: unique
          )
        else
          # Regular object header
          @current_header = content
          @current_header_kind = :object
          @current_type_name = nil
          @current_array_path = nil
        end
      end

      def parse_array_constraint_text(text)
        unique = false
        min_items = nil
        max_items = nil

        if text.include?(":unique")
          unique = true
          text = text.gsub(":unique", "").strip
        end

        bounds_match = text.match(/:\((\d*)\.\.(\d*)\)/)
        if bounds_match
          min_items = bounds_match[1].to_i unless bounds_match[1].empty?
          max_items = bounds_match[2].to_i unless bounds_match[2].empty?
        end

        [unique, min_items, max_items]
      end

      def parse_object_constraint(line)
        scope = @current_header || ""
        @object_constraints[scope] ||= []

        if line.start_with?(":invariant ")
          expr = line[11..].strip
          @object_constraints[scope] << Types::SchemaInvariant.new(expression: expr)
        elsif line.start_with?(":one_of ")
          fields = parse_field_list(line[8..])
          @object_constraints[scope] << Types::SchemaCardinality.new(
            cardinality_type: "one_of", fields: fields, min: 1
          )
        elsif line.start_with?(":exactly_one ")
          fields = parse_field_list(line[13..])
          @object_constraints[scope] << Types::SchemaCardinality.new(
            cardinality_type: "exactly_one", fields: fields, min: 1, max: 1
          )
        elsif line.start_with?(":at_most_one ")
          fields = parse_field_list(line[13..])
          @object_constraints[scope] << Types::SchemaCardinality.new(
            cardinality_type: "at_most_one", fields: fields, max: 1
          )
        elsif line.start_with?(":of ")
          parse_of_constraint(line[4..], scope)
        elsif line.start_with?(":(")
          # Array bounds constraint: :(min..max) — applies to current array
          if @current_array_path && @arrays[@current_array_path]
            unique, min_items, max_items = parse_array_constraint_text(line)
            old = @arrays[@current_array_path]
            @arrays[@current_array_path] = Types::SchemaArray.new(
              path: old.path,
              item_fields: old.item_fields,
              min_items: min_items || old.min_items,
              max_items: max_items || old.max_items,
              unique: unique || old.unique,
              columns: old.columns
            )
          end
        elsif line.start_with?(":unique")
          if @current_array_path && @arrays[@current_array_path]
            # Rebuild array with unique flag
            old = @arrays[@current_array_path]
            @arrays[@current_array_path] = Types::SchemaArray.new(
              path: old.path,
              item_fields: old.item_fields,
              min_items: old.min_items,
              max_items: old.max_items,
              unique: true,
              columns: old.columns
            )
          end
        end
      end

      def parse_of_constraint(text, scope)
        bounds_match = text.strip.match(/\A\((\d*)\.\.(\d*)\)\s*(.*)\z/)
        return unless bounds_match

        min_val = bounds_match[1].empty? ? nil : bounds_match[1].to_i
        max_val = bounds_match[2].empty? ? nil : bounds_match[2].to_i
        fields = parse_field_list(bounds_match[3])
        @object_constraints[scope] << Types::SchemaCardinality.new(
          cardinality_type: "of", fields: fields, min: min_val, max: max_val
        )
      end

      def parse_field_list(text)
        text.split(",").map(&:strip).reject(&:empty?)
      end

      # Parse type-level constraint line for bare @TypeName definitions
      # e.g., = :(10..15) :pattern "..." or = @TypeA & @TypeB or = ##:(1..)
      def parse_type_constraint_line(spec)
        return unless @current_type_name

        # Check for intersection: @TypeA & @TypeB
        if spec.include?(" & ")
          refs = spec.split("&").map { |p| p.strip.sub(/^@/, "") }
          old = @types[@current_type_name]
          @types[@current_type_name] = Types::SchemaType.new(
            name: old.name, fields: old.fields, namespace: old.namespace,
            intersection_types: refs, parent_types: old.parent_types
          )
          return
        end

        # Check for :deprecated directive
        deprecated = false
        deprecation_msg = nil
        if spec.include?(":deprecated")
          deprecated = true
          dep_match = spec.match(/:deprecated\s+"([^"]*)"/)
          if dep_match
            deprecation_msg = dep_match[1]
            spec = spec.sub(/:deprecated\s+"[^"]*"/, "").strip
          else
            spec = spec.sub(/:deprecated/, "").strip
          end
        end

        # Parse as a field spec to extract type and constraints
        old = @types[@current_type_name]
        existing_constraints = old.constraints.dup

        unless spec.empty?
          dummy_field = parse_field_spec(@current_type_name, spec)
          base = field_type_to_string(dummy_field.field_type)
          new_constraints = build_constraint_hash(dummy_field.constraints, dummy_field.field_type)
          existing_constraints.merge!(new_constraints)
        end

        @types[@current_type_name] = Types::SchemaType.new(
          name: old.name, fields: old.fields, namespace: old.namespace,
          base_type: old.base_type || (spec.empty? ? nil : base),
          constraints: existing_constraints,
          intersection_types: old.intersection_types, parent_types: old.parent_types
        )
      end

      def field_type_to_string(ft)
        case ft
        when :string then "string"
        when :integer then "integer"
        when :number then "number"
        when :boolean then "boolean"
        when :currency then "currency"
        when :percent then "percent"
        when :date then "date"
        when :timestamp then "timestamp"
        when :time then "time"
        when :duration then "duration"
        when :reference then "reference"
        when :binary then "binary"
        when :null then "null"
        else ft.to_s
        end
      end

      def build_constraint_hash(constraints, field_type)
        h = {}
        constraints.each do |c|
          case c
          when Types::BoundsConstraint
            if field_type == :string || field_type == Types::SchemaFieldType::STRING
              if c.min == c.max && c.min
                h["length"] = c.min
              else
                h["minLength"] = c.min if c.min
                h["maxLength"] = c.max if c.max
              end
            else
              h["min"] = c.min if c.min
              h["max"] = c.max if c.max
            end
          when Types::PatternConstraint
            h["pattern"] = c.pattern
          when Types::FormatConstraint
            h["format"] = c.format_name
          when Types::EnumConstraint
            h["enum"] = c.values
          when Types::UniqueConstraint
            h["unique"] = true
          end
        end
        h
      end

      def parse_field_definition(line)
        # Handle comment at end of line
        comment_idx = find_comment(line)
        line = line[0...comment_idx].rstrip if comment_idx >= 0

        eq_idx = line.index("=")
        return unless eq_idx

        left = line[0...eq_idx].strip
        right = line[(eq_idx + 1)..].strip

        # Handle lines with empty left side: = constraint_spec
        if left.empty?
          if @current_header_kind == :bare_type && @current_type_name
            # Type-level constraint: = :(10..15) :pattern "..." or = @TypeA & @TypeB
            parse_type_constraint_line(right)
            return
          elsif right.start_with?(":")
            if @current_array_path && @arrays[@current_array_path]
              unique, min_items, max_items = parse_array_constraint_text(right)
              old = @arrays[@current_array_path]
              @arrays[@current_array_path] = Types::SchemaArray.new(
                path: old.path,
                item_fields: old.item_fields,
                min_items: min_items || old.min_items,
                max_items: max_items || old.max_items,
                unique: unique || old.unique,
                columns: old.columns
              )
            end
            return
          end
          return
        end

        field_name = left
        # Strip array indicator from field names
        is_array_field = field_name.end_with?("[]")
        field_name = field_name[0...-2] if is_array_field

        # Unquote the value (Java does this before metadata check)
        if right.length >= 2 && right[0] == '"' && right[-1] == '"'
          right = right[1...-1]
        end

        # Store metadata
        if @current_header_kind == :metadata
          @metadata[field_name] = right
          return
        end

        # Build full path based on context
        full_path = case @current_header_kind
                    when :type then field_name
                    when :array then field_name
                    when :object
                      @current_header ? "#{@current_header}.#{field_name}" : field_name
                    else
                      field_name
                    end

        # Parse the field spec from the right side
        schema_field = parse_field_spec(full_path, right)

        # Override type_ref for array fields
        if is_array_field
          schema_field = Types::SchemaField.new(
            name: schema_field.name, field_type: schema_field.field_type,
            required: schema_field.required, nullable: schema_field.nullable,
            redacted: schema_field.redacted, deprecated: schema_field.deprecated,
            constraints: schema_field.constraints, conditionals: schema_field.conditionals,
            computed: schema_field.computed, immutable: schema_field.immutable,
            type_ref: "array"
          )
        end

        # Store the field
        case @current_header_kind
        when :type, :bare_type
          if @current_type_name && @types[@current_type_name]
            old_type = @types[@current_type_name]
            new_fields = old_type.fields.dup
            new_fields[field_name] = schema_field
            @types[@current_type_name] = Types::SchemaType.new(
              name: old_type.name,
              fields: new_fields,
              namespace: old_type.namespace,
              composition: old_type.composition,
              base_type: old_type.base_type,
              constraints: old_type.constraints,
              intersection_types: old_type.intersection_types,
              parent_types: old_type.parent_types
            )
          end
        when :array
          if @current_array_path && @arrays[@current_array_path]
            old_arr = @arrays[@current_array_path]
            new_fields = old_arr.item_fields.dup
            new_fields[field_name] = schema_field
            @arrays[@current_array_path] = Types::SchemaArray.new(
              path: old_arr.path,
              item_fields: new_fields,
              min_items: old_arr.min_items,
              max_items: old_arr.max_items,
              unique: old_arr.unique,
              columns: old_arr.columns
            )
          end
          # Don't add array item fields to root @fields — they are only in item_fields
        else
          @fields[full_path] = schema_field
        end
      end

      def parse_field_spec(path, spec)
        field_type = Types::SchemaFieldType::STRING
        required = false
        nullable = false
        redacted = false
        deprecated = false
        computed = false
        immutable = false
        constraints = []
        conditionals = []
        type_ref = nil

        return Types::SchemaField.new(
          name: path, field_type: field_type, required: required,
          nullable: nullable, redacted: redacted, deprecated: deprecated,
          constraints: constraints, conditionals: conditionals,
          computed: computed, immutable: immutable, type_ref: type_ref
        ) if spec.nil? || spec.empty?

        pos = 0
        # Parse modifiers: ! ~ * -
        while pos < spec.length
          case spec[pos]
          when "!" then required = true; pos += 1
          when "~" then nullable = true; pos += 1
          when "*" then redacted = true; pos += 1
          when "-" then deprecated = true; pos += 1
          else break
          end
        end

        remaining = spec[pos..].to_s.strip

        # Parse type
        type_result = parse_type_spec(remaining)
        field_type = type_result[0]
        remaining = type_result[1]
        enum_values = type_result[2] # may be nil
        type_ref = type_result[3] # may be nil

        # If enum values were returned, add as constraint
        if enum_values
          constraints << Types::EnumConstraint.new(values: enum_values)
        end

        # Parse constraints (append to existing, don't replace)
        more_constraints, remaining = parse_constraints(remaining)
        constraints.concat(more_constraints)

        # Parse conditionals
        conditionals, remaining = parse_conditionals(remaining)

        # Parse directives
        while remaining && !remaining.empty?
          if remaining.start_with?(":computed")
            computed = true
            remaining = remaining[9..].to_s.strip
          elsif remaining.start_with?(":immutable")
            immutable = true
            remaining = remaining[10..].to_s.strip
          else
            break
          end
        end

        Types::SchemaField.new(
          name: path, field_type: field_type, required: required,
          nullable: nullable, redacted: redacted, deprecated: deprecated,
          constraints: constraints, conditionals: conditionals,
          computed: computed, immutable: immutable, type_ref: type_ref
        )
      end

      # Returns [type, remaining, enum_values_or_nil, type_ref_or_nil]
      def parse_type_spec(text)
        text = text.to_s.strip
        return [Types::SchemaFieldType::STRING, "", nil, nil] if text.empty?

        # Check for enum: (val1, val2, ...)
        if text.start_with?("(")
          return parse_enum_type(text)
        end

        # Type prefixes
        if text.start_with?("##")
          return [Types::SchemaFieldType::INTEGER, text[2..].to_s.strip, nil, nil]
        elsif text.start_with?("#" + "$")
          rest = text[2..].to_s.strip
          if rest.start_with?(".") && rest.length > 1 && rest[1]&.match?(/\d/)
            return [Types::SchemaFieldType::CURRENCY, rest[2..].to_s.strip, nil, nil]
          end
          return [Types::SchemaFieldType::CURRENCY, rest, nil, nil]
        elsif text.start_with?("#" + "%")
          return [Types::SchemaFieldType::PERCENT, text[2..].to_s.strip, nil, nil]
        elsif text.start_with?("#")
          rest = text[1..].to_s.strip
          if rest.start_with?(".") && rest.length > 1 && rest[1]&.match?(/\d/)
            return [Types::SchemaFieldType::NUMBER, rest[2..].to_s.strip, nil, nil]
          end
          return [Types::SchemaFieldType::NUMBER, rest, nil, nil]
        elsif text.start_with?("?")
          return [Types::SchemaFieldType::BOOLEAN, text[1..].to_s.strip, nil, nil]
        elsif text.start_with?("@")
          rest = text[1..]
          name = ""
          i = 0
          while i < rest.length && !(" \t:,)".include?(rest[i]))
            name += rest[i]
            i += 1
          end
          remaining = rest[i..].to_s.strip
          ref = name.empty? ? nil : "@#{name}"
          return [Types::SchemaFieldType::REFERENCE, remaining, nil, ref]
        elsif text.start_with?("^")
          return [Types::SchemaFieldType::BINARY, text[1..].to_s.strip, nil, nil]
        elsif text.start_with?("~")
          return [Types::SchemaFieldType::NULL, text[1..].to_s.strip, nil, nil]
        elsif text.start_with?('"')
          return [Types::SchemaFieldType::STRING, text, nil, nil]
        end

        # Keyword types
        KEYWORD_TYPES.each do |keyword, type_val|
          if text.start_with?(keyword)
            after = text[keyword.length..]
            if after.nil? || after.empty? || " \t:,)".include?(after[0])
              return [type_val, after.to_s.strip, nil, nil]
            end
          end
        end

        # Default: string
        [Types::SchemaFieldType::STRING, text, nil, nil]
      end

      def parse_enum_type(text)
        depth = 0
        close_idx = 0
        text.each_char.with_index do |ch, i|
          if ch == "("
            depth += 1
          elsif ch == ")"
            depth -= 1
            if depth == 0
              close_idx = i
              break
            end
          end
        end

        enum_content = text[1...close_idx]
        values = enum_content.split(",").map { |v| v.strip.gsub(/\A["']|["']\z/, "") }
        remaining = text[(close_idx + 1)..].to_s.strip
        # Store as STRING type with an enum constraint - enum is handled as a constraint
        [Types::SchemaFieldType::STRING, remaining, values, nil]
      end

      def parse_constraints(text)
        constraints = []
        text = text.to_s.strip

        # Handle enum values returned from parse_type_spec
        # (This is handled via the 3-element return from parse_enum_type)

        while text.start_with?(":")
          if text.start_with?(":(")
            # Bounds constraint
            constraint, text = parse_bounds_constraint(text[1..])
            constraints << constraint if constraint
          elsif text.start_with?(":/")
            # Pattern constraint
            constraint, text = parse_pattern_constraint(text[1..])
            constraints << constraint if constraint
          elsif text.start_with?(":format ")
            rest = text[8..].strip
            fmt_name = ""
            i = 0
            while i < rest.length && !" \t:".include?(rest[i])
              fmt_name += rest[i]
              i += 1
            end
            constraints << Types::FormatConstraint.new(format_name: fmt_name) unless fmt_name.empty?
            text = rest[i..].to_s.strip
          elsif text.start_with?(":unique")
            constraints << Types::UniqueConstraint.new
            text = text[7..].to_s.strip
          elsif text.start_with?(":pattern ")
            rest = text[9..].strip
            if rest.start_with?('"')
              end_idx = rest.index('"', 1)
              if end_idx
                pat = rest[1...end_idx]
                constraints << Types::PatternConstraint.new(pattern: pat)
                text = rest[(end_idx + 1)..].to_s.strip
              else
                text = rest
              end
            else
              text = rest
            end
          elsif text.start_with?(":if ") || text.start_with?(":unless ")
            break # Conditionals handled separately
          elsif text.start_with?(":computed") || text.start_with?(":immutable")
            break # Directives handled separately
          else
            break
          end
        end

        [constraints, text]
      end

      def parse_bounds_constraint(text)
        return [nil, text] unless text.start_with?("(")

        depth = 0
        close_idx = 0
        text.each_char.with_index do |ch, i|
          if ch == "("
            depth += 1
          elsif ch == ")"
            depth -= 1
            if depth == 0
              close_idx = i
              break
            end
          end
        end

        content = text[1...close_idx]
        remaining = text[(close_idx + 1)..].to_s.strip

        if content.include?("..")
          parts = content.split("..", 2)
          min_val = parts[0].strip.empty? ? nil : parse_bound_value(parts[0].strip)
          max_val = parts[1].strip.empty? ? nil : parse_bound_value(parts[1].strip)
        else
          val = parse_bound_value(content.strip)
          min_val = val
          max_val = val
        end

        [Types::BoundsConstraint.new(min: min_val, max: max_val), remaining]
      end

      def parse_pattern_constraint(text)
        return [nil, text] unless text.start_with?("/")

        end_idx = text.index("/", 1)
        return [nil, text] unless end_idx

        pattern = text[1...end_idx]
        remaining = text[(end_idx + 1)..].to_s.strip
        [Types::PatternConstraint.new(pattern: pattern), remaining]
      end

      def parse_conditionals(text)
        conditionals = []
        text = text.to_s.strip

        while !text.empty?
          if text.start_with?(":if ")
            cond, text = parse_single_conditional(text[4..], false)
            conditionals << cond if cond
          elsif text.start_with?(":unless ")
            cond, text = parse_single_conditional(text[8..], true)
            conditionals << cond if cond
          else
            break
          end
        end

        [conditionals, text]
      end

      def parse_single_conditional(text, is_unless)
        text = text.to_s.strip

        # Try operator match first: field op value
        match = text.match(/\A(\w[\w.]*)\s*(>=|<=|!=|>|<|=)\s*(\S+)(.*)\z/)
        if match
          field_name = match[1]
          operator = match[2]
          raw_value = match[3].gsub(/\A["']|["']\z/, "")
          remaining = match[4].strip
        else
          # Shorthand boolean: :if field_name (implies field = true)
          match = text.match(/\A(\w[\w.]*)(.*)\z/)
          return [nil, text] unless match
          field_name = match[1]
          operator = "="
          raw_value = "true"
          remaining = match[2].strip
        end

        cond_field = field_name

        [Types::SchemaConditional.new(
          field: cond_field, operator: operator, value: raw_value, unless_cond: is_unless
        ), remaining]
      end

      def parse_bound_value(s)
        return nil if s.nil? || s.empty?
        if s.match?(/\A-?\d+\z/)
          s.to_i
        elsif s.match?(/\A-?\d+\.\d+\z/)
          s.to_f
        else
          s
        end
      end

      def find_comment(line)
        in_string = false
        line.each_char.with_index do |ch, i|
          if ch == '"' && (i == 0 || line[i - 1] != "\\")
            in_string = !in_string
          elsif ch == ";" && !in_string
            return i
          end
        end
        -1
      end

      def unquote(s)
        s = s.strip
        if s.length >= 2 && s[0] == '"' && s[-1] == '"'
          s[1...-1]
        elsif s.length >= 2 && s[0] == "'" && s[-1] == "'"
          s[1...-1]
        else
          s
        end
      end
    end
  end
end
