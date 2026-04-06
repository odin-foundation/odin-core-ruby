# frozen_string_literal: true

module Odin
  module Transform
    class TransformEngine
      # Verb registry — populated in Phase 9-10. For now, core verbs only.
      CORE_VERBS = {}.freeze

      class TransformError < StandardError
        attr_reader :code

        def initialize(message, code: "E001")
          @code = code
          super(message)
        end
      end

      # ── Transform Error Codes ──
      # T001-T010 are reserved for core transform errors.
      # T011+ are for implementation-specific errors.
      module ErrorCodes
        T001_UNKNOWN_VERB            = "T001"
        T002_INVALID_VERB_ARGS       = "T002"
        T003_LOOKUP_TABLE_NOT_FOUND  = "T003"
        T004_LOOKUP_KEY_NOT_FOUND    = "T004"
        T005_SOURCE_PATH_NOT_FOUND   = "T005"
        T006_INVALID_OUTPUT_FORMAT   = "T006"
        T007_INVALID_MODIFIER        = "T007"
        T008_ACCUMULATOR_OVERFLOW    = "T008"
        T009_LOOP_SOURCE_NOT_ARRAY   = "T009"
        T010_POSITION_OVERFLOW       = "T010"
        T011_INCOMPATIBLE_CONVERSION = "T011"
      end

      # Create a T011 Incompatible Conversion error.
      # Used when a verb receives an unknown or incompatible conversion target
      # (e.g., unknown unit in dateDiff or distance).
      def self.incompatible_conversion_error(verb_name, detail)
        TransformError.new(
          "#{verb_name}: incompatible conversion — #{detail}",
          code: ErrorCodes::T011_INCOMPATIBLE_CONVERSION
        )
      end

      attr_reader :verb_registry

      def initialize
        @verb_registry = build_verb_registry
      end

      def execute(transform_def, source_data)
        # Check for multi-record mode (discriminator dispatch)
        disc_config = transform_def.discriminator_config
        if disc_config
          raw_str = case source_data
                    when String then source_data
                    when Types::DynValue
                      source_data.string? ? source_data.value : nil
                    end
          return execute_multi_record(transform_def, raw_str, disc_config) if raw_str
        end

        # 1. Normalize source data to DynValue
        source = normalize_source(source_data, transform_def.source_format)

        # 2. Build context
        context = build_context(transform_def, source)

        # 3. Process segments (multi-pass support)
        output = {}
        passes = transform_def.passes
        if passes.empty?
          # Single implicit pass
          transform_def.segments.each do |segment|
            process_segment(segment, source, context, output)
          end
        else
          # Multi-pass: explicit passes first, then pass-0 (implicit)
          all_passes = passes.include?(0) ? passes : passes + [0]
          first_pass = true
          all_passes.each do |pass_num|
            unless first_pass
              reset_non_persist_accumulators(context, transform_def.accumulators)
            end
            first_pass = false

            transform_def.segments.each do |segment|
              seg_pass = segment.pass || 0
              next unless seg_pass == pass_num

              process_segment(segment, source, context, output)
            end
          end
        end

        # 4. Apply confidential enforcement
        if transform_def.header.enforce_confidential != ConfidentialMode::NONE
          apply_confidential(output, transform_def.header.enforce_confidential, context.field_modifiers)
        end

        # 5. Convert output to DynValue (preserves types like date, timestamp)
        output_dv = Types::DynValue.from_ruby(output)

        # 6. Format output
        formatted = format_output(output_dv, transform_def, context)

        # 7. Convert output to plain Ruby for result (DynValues -> native Ruby)
        plain_output = deep_to_ruby(output)

        TransformResult.new(output: plain_output, formatted: formatted, output_dv: output_dv, errors: context.errors)
      end

      # ── Multi-Record Execution (discriminator-based routing) ──

      def execute_multi_record(transform_def, raw_input, disc_config)
        # Parse discriminator config
        disc = parse_discriminator_config(disc_config)
        return TransformResult.new(output: {}, formatted: "", errors: []) unless disc

        source_format = transform_def.source_format
        delimiter = transform_def.header.source_options["delimiter"] || ","

        # Build segment routing map: _type literal value -> segment
        segment_map = {}
        transform_def.segments.each do |seg|
          next unless seg.discriminator_value

          seg.discriminator_value.split(",").each do |type_val|
            segment_map[type_val.strip] = seg
          end
        end

        context = build_context(transform_def, Types::DynValue.of_null)
        context.source_format = source_format

        output = {}
        array_accumulators = {}

        # Initialize array accumulators
        transform_def.segments.each do |seg|
          if seg.is_array
            array_accumulators[seg.name] = []
          end
        end

        # Process each record/line
        lines = raw_input.split(/[\r\n]+/)
        lines.each do |line|
          next if line.strip.empty?

          disc_value = extract_discriminator_value(line, disc, delimiter)
          segment = segment_map[disc_value]
          next unless segment

          record_source = parse_record(line, source_format, delimiter)
          record_output = {}

          # Set the record as the current source for path resolution
          context.source = record_source

          # Process field mappings
          segment.field_mappings.each do |mapping|
            process_mapping(mapping, record_source, context, record_output)
          end

          # Process children
          segment.children.each do |child|
            process_segment(child, record_source, context, record_output)
          end

          # Merge into output
          seg_name = segment.name

          if segment.is_array
            array_accumulators[seg_name] ||= []
            array_accumulators[seg_name] << record_output
          else
            # Merge fields into existing segment object
            if output[seg_name].is_a?(Hash)
              record_output.each { |k, v| output[seg_name][k] = v }
            else
              output[seg_name] = record_output
            end
          end
        end

        # Merge array accumulators into output in segment order
        transform_def.segments.each do |seg|
          next unless seg.is_array

          items = array_accumulators[seg.name]
          next unless items

          output[seg.name] = items
        end

        # Convert output to DynValue
        output_dv = Types::DynValue.from_ruby(output)

        # Format output
        formatted = format_output(output_dv, transform_def, context)

        # Convert output to plain Ruby
        plain_output = deep_to_ruby(output)

        TransformResult.new(output: plain_output, formatted: formatted, output_dv: output_dv, errors: context.errors)
      end

      private def parse_discriminator_config(config)
        parts = config.strip.split(/\s+/)
        pos = nil
        len = nil
        field_index = nil

        i = 0
        while i < parts.length
          case parts[i]
          when ":pos"
            pos = parts[i + 1]&.to_i
            i += 2
          when ":len"
            len = parts[i + 1]&.to_i
            i += 2
          when ":field"
            field_index = parts[i + 1]&.to_i
            i += 2
          else
            i += 1
          end
        end

        if field_index
          { mode: :field, field_index: field_index }
        elsif pos && len
          { mode: :position, pos: pos, len: len }
        else
          nil
        end
      end

      private def extract_discriminator_value(line, disc, delimiter)
        if disc[:mode] == :position
          pos = disc[:pos]
          len = disc[:len]
          if pos + len <= line.length
            line[pos, len].strip
          elsif pos < line.length
            line[pos..].strip
          else
            ""
          end
        else
          fields = line.split(delimiter.include?(",") ? "," : delimiter, -1)
          idx = disc[:field_index]
          idx < fields.length ? fields[idx].strip : ""
        end
      end

      private def parse_record(line, format, delimiter)
        entries = {
          "_raw" => Types::DynValue.of_string(line),
          "_line" => Types::DynValue.of_string(line)
        }

        if format == "csv" || format == "delimited"
          fields = line.split(delimiter.include?(",") ? "," : delimiter, -1)
          fields.each_with_index do |f, i|
            entries[i.to_s] = Types::DynValue.of_string(f)
          end
        end

        Types::DynValue.of_object(entries)
      end

      # Public for unit testing verbs directly
      def invoke_verb(name, args, context)
        verb_fn = @verb_registry[name]
        raise TransformError.new("Unknown verb: %#{name}") unless verb_fn

        verb_fn.call(args, context)
      end

      # ── Expression Evaluation ──

      def evaluate(expr, context)
        case expr
        when LiteralExpr
          expr.value
        when CopyExpr
          val = resolve_path(expr.source_path, context)
          # Apply CopyExpr-level extraction directives only for compatible source formats
          # (fixed-width, csv, delimited, flat — NOT odin, json, xml)
          if expr.directives && !expr.directives.empty?
            src_fmt = context.source_format
            if src_fmt == "fixed-width" || src_fmt == "csv" || src_fmt == "delimited" || src_fmt == "flat"
              val = apply_extraction_directives(val, expr.directives)
            end
          end
          val
        when VerbExpr
          evaluate_verb(expr, context)
        when ObjectExpr
          evaluate_object(expr, context)
        else
          Types::DynValue.of_null
        end
      end

      private

      # Emulate JavaScript's signed 32-bit right shift (>>).
      # Ruby integers are arbitrary precision and always do logical (unsigned) shift,
      # but JS >> sign-extends from bit 31.
      def js_signed_rshift(val, shift)
        val = val & 0xFFFFFFFF
        val -= 0x100000000 if val >= 0x80000000
        (val >> shift) & 0xFF
      end

      def deep_to_ruby(obj)
        case obj
        when Types::DynValue
          obj.to_ruby
        when Hash
          obj.transform_values { |v| deep_to_ruby(v) }
        when Array
          obj.map { |v| deep_to_ruby(v) }
        else
          obj
        end
      end

      # ── Source Normalization ──

      def normalize_source(source_data, source_format)
        case source_data
        when Types::DynValue
          # Auto-parse raw string DynValues based on source format
          if source_data.string? && source_format
            case source_format
            when "json"
              begin; return SourceParsers.parse_json(source_data.value); rescue StandardError; end
            when "xml"
              begin; return SourceParsers.parse_xml(source_data.value); rescue StandardError; end
            when "csv"
              begin; return SourceParsers.parse_csv(source_data.value); rescue StandardError; end
            when "yaml"
              begin; return SourceParsers.parse_yaml(source_data.value); rescue StandardError; end
            when "flat", "properties", "flat-kvp"
              begin; return SourceParsers.parse_flat_kvp(source_data.value); rescue StandardError; end
            when "odin"
              begin
                doc = Odin.parse(source_data.value)
                return doc_to_dynvalue(doc)
              rescue StandardError; end
            end
          end
          source_data
        when Hash
          Types::DynValue.from_ruby(source_data)
        when Array
          Types::DynValue.from_ruby(source_data)
        when String
          # Parse based on source format
          case source_format
          when "json" then SourceParsers.parse_json(source_data)
          when "xml" then SourceParsers.parse_xml(source_data)
          when "csv" then SourceParsers.parse_csv(source_data)
          when "odin"
            doc = Odin.parse(source_data)
            doc_to_dynvalue(doc)
          else
            # Try JSON first, fall back to string
            begin
              SourceParsers.parse_json(source_data)
            rescue StandardError
              Types::DynValue.of_string(source_data)
            end
          end
        when NilClass
          Types::DynValue.of_null
        else
          Types::DynValue.from_ruby(source_data)
        end
      end

      def doc_to_dynvalue(doc)
        # OdinDocument stores flat path -> value assignments
        # We need to reconstruct a nested structure
        result = {}
        doc.each_assignment do |path, value|
          parts = path.split(".")
          current = result
          parts[0...-1].each do |part|
            current[part] ||= {}
            current = current[part]
          end
          current[parts.last] = odin_value_to_dynvalue(value)
        end
        build_nested_dynvalue(result)
      end

      def build_nested_dynvalue(obj)
        case obj
        when Hash
          Types::DynValue.of_object(obj.transform_values { |v| v.is_a?(Hash) ? build_nested_dynvalue(v) : v })
        else
          obj
        end
      end

      def odin_value_to_dynvalue(val)
        case val
        when Types::OdinString then Types::DynValue.of_string(val.value)
        when Types::OdinNumber then Types::DynValue.of_float(val.value)
        when Types::OdinInteger then Types::DynValue.of_integer(val.value)
        when Types::OdinBoolean then Types::DynValue.of_bool(val.value)
        when Types::OdinNull then Types::DynValue.of_null
        when Types::OdinCurrency
          Types::DynValue.of_currency(val.value, val.respond_to?(:decimal_places) ? val.decimal_places : 2)
        when Types::OdinReference then Types::DynValue.of_reference(val.path)
        when Types::OdinBinary then Types::DynValue.of_binary(val.data)
        else Types::DynValue.of_null
        end
      end

      # ── Context Building ──

      def build_context(transform_def, source)
        context = VerbContext.new
        context.source = source
        context.source_format = transform_def.source_format || ""

        # Initialize constants
        transform_def.constants.each do |key, val|
          context.constants[key] = val
        end

        # Initialize accumulators
        transform_def.accumulators.each do |key, acc_def|
          context.accumulators[key] = acc_def.initial_value
        end

        # Initialize tables
        transform_def.tables.each do |key, table|
          context.tables[key] = table
        end

        context
      end

      def reset_non_persist_accumulators(context, accumulator_defs)
        accumulator_defs.each do |key, acc_def|
          next if acc_def.persist

          context.accumulators[key] = acc_def.initial_value
        end
      end

      # ── Segment Processing ──

      def process_segment(segment, source, context, output, modifier_prefix: "")
        # Check _when condition
        if segment.when_condition
          return unless evaluate_condition(segment.when_condition, source, context)
        end

        # Check _if condition
        if segment.if_condition
          return unless evaluate_condition(segment.if_condition, source, context)
        end

        # Check _discriminator
        if segment.discriminator
          disc_val = resolve_path_from_string(segment.discriminator, source, context)
          expected = segment.discriminator_value
          if expected
            disc_str = disc_val.is_a?(Types::DynValue) ? disc_val.to_string : disc_val.to_s
            return unless disc_str == expected
          end
        end

        seg_name = segment.name
        full_prefix = modifier_prefix.empty? ? seg_name : "#{modifier_prefix}.#{seg_name}"

        # Handle _each (loop over array)
        if segment.each_source
          process_loop_segment(segment, source, context, output, modifier_prefix: full_prefix)
          return
        end

        # Process field mappings into the segment's output
        segment_result = {}
        segment.field_mappings.each do |mapping|
          process_mapping(mapping, source, context, segment_result, modifier_prefix: full_prefix)
        end

        # Process children
        segment.children.each do |child|
          process_segment(child, source, context, segment_result, modifier_prefix: full_prefix)
        end

        # Merge segment result into output
        if segment_result.any?
          if segment.is_array && segment.array_index
            existing_arr = get_output_path(output, seg_name)
            set_output_path(output, seg_name, []) unless existing_arr.is_a?(Array)
            get_output_path(output, seg_name)[segment.array_index] = segment_result
          elsif segment.is_array
            existing = get_output_path(output, seg_name)
            if existing.is_a?(Array)
              existing.concat(segment_result.is_a?(Array) ? segment_result : [segment_result])
            else
              set_output_path(output, seg_name, segment_result.is_a?(Array) ? segment_result : [segment_result])
            end
          elsif seg_name.empty?
            # Root segment: flatten into output
            segment_result.each { |k, v| output[k] = v }
          else
            # Merge into existing nested object if it already exists
            existing = get_output_path(output, seg_name)
            if existing.is_a?(Hash)
              segment_result.each { |k, v| existing[k] = v }
            else
              set_output_path(output, seg_name, segment_result)
            end
          end
        end
      end

      def process_loop_segment(segment, source, context, output, modifier_prefix: "")
        # Resolve the array to iterate
        each_path = segment.each_source
        items = resolve_path_from_string(each_path, source, context)

        # If the resolved value is null (path not found), skip iteration
        # matching TypeScript which checks Array.isArray(items)
        if items.is_a?(Types::DynValue) && items.null?
          return
        end

        # If the resolved value is not an array, wrap single non-null values
        if items.is_a?(Types::DynValue) && !items.array?
          items = Types::DynValue.of_array([items])
        end

        return unless items.is_a?(Types::DynValue) && items.array?

        # Check if this is a scalar array loop (only has _ = expr mappings)
        has_underscore_only = segment.field_mappings.all? { |m| m.target_field == "_" } &&
                              segment.field_mappings.any? && segment.children.empty?

        results = []
        loop_ctx = context.dup_for_loop
        raise TransformError.new("Maximum loop nesting depth exceeded") if loop_ctx.loop_depth > VerbContext::MAX_LOOP_DEPTH

        items.value.each_with_index do |item, idx|
          loop_ctx.current_item = item
          loop_ctx.loop_index = idx
          loop_ctx.loop_length = items.value.length
          loop_ctx.loop_vars["_item"] = item
          loop_ctx.loop_vars["_index"] = Types::DynValue.of_integer(idx)
          loop_ctx.loop_vars["_length"] = Types::DynValue.of_integer(items.value.length)

          if segment.counter_name
            loop_ctx.loop_vars[segment.counter_name] = Types::DynValue.of_integer(idx)
          end

          if has_underscore_only
            # Scalar array: evaluate the _ mapping and use the result as the array element
            val = Types::DynValue.of_null
            segment.field_mappings.each do |mapping|
              val = evaluate(mapping.expression, loop_ctx)
              # Apply extraction directives first (:pos, :len, :field) as a group
              val = apply_extraction_directives(val, mapping.directives)
              # Apply remaining directives
              mapping.directives.each do |directive|
                next if %w[pos len field].include?(directive.name)
                val = apply_directive(val, directive, item, loop_ctx)
              end
            end
            results << val
          else
            item_result = {}
            segment.field_mappings.each do |mapping|
              process_mapping(mapping, item, loop_ctx, item_result, modifier_prefix: modifier_prefix)
            end

            # Process children
            segment.children.each do |child|
              process_segment(child, item, loop_ctx, item_result, modifier_prefix: modifier_prefix)
            end

            results << item_result if item_result.any?
          end
        end

        seg_name = segment.name
        # Always set the array in output, even if empty (Java parity)
        set_output_path(output, seg_name, results)
      end

      def process_mapping(mapping, source, context, output, modifier_prefix: "")
        target = mapping.target_field

        # Handle _pass directive and other underscore-prefixed targets
        # but still evaluate `_` (bare underscore) for side effects like accumulate
        if target == "_"
          begin
            evaluate(mapping.expression, context)
          rescue StandardError => e
            context.errors << TransformError.new(e.message)
          end
          return
        end
        return if target.start_with?("_")

        begin
          # Evaluate expression
          # Extraction directives (pos, len, field, trim) only apply for extraction-compatible
          # source formats. For output formats like fixed-width, these directives are used by
          # the formatter for positioning, NOT for input extraction.
          src_fmt = context.source_format
          extraction_compatible = %w[fixed-width csv delimited flat].include?(src_fmt)
          has_extraction = extraction_compatible &&
            mapping.directives.any? { |d| %w[pos len field trim].include?(d.name) }

          # Check if CopyExpr already has its own extraction directives
          # (applied during evaluate() for compatible source formats)
          expr_has_own_extraction = extraction_compatible && expr_has_extraction_directives?(mapping.expression)

          if has_extraction && mapping.expression.is_a?(VerbExpr) && !expr_has_own_extraction
            # For verb expressions with extraction directives, apply extraction
            # to the first CopyExpr argument before calling the verb (matching Java behavior)
            val = evaluate_verb_with_extraction(mapping.expression, context, mapping.directives)
          else
            val = evaluate(mapping.expression, context)
            # Apply extraction directives only if expression doesn't handle its own extraction
            if has_extraction && !expr_has_own_extraction
              val = apply_extraction_directives(val, mapping.directives)
            end
          end

          # Apply remaining directives (non-extraction: type, default, upper, lower, etc.)
          mapping.directives.each do |directive|
            next if %w[pos len field trim].include?(directive.name)
            val = apply_directive(val, directive, source, context)
          end

          # Track field modifiers with full path
          unless mapping.modifiers.empty?
            full_path = modifier_prefix.empty? ? target : "#{modifier_prefix}.#{target}"
            context.field_modifiers[full_path] = mapping.modifiers
          end

          # Store DynValue directly to preserve type information (date, timestamp, etc.)
          dv_val = val.is_a?(Types::DynValue) ? val : Types::DynValue.from_ruby(val)
          set_path(output, target, dv_val)
        rescue StandardError => e
          context.errors << TransformError.new(e.message)
        end
      end

      # ── Path Assignment (nested object creation for dotted paths) ──

      def set_path(output, path, value)
        return if output.nil? || path.nil? || path.empty?

        parts = path.split(".")
        if parts.length == 1
          set_single_field(output, parts[0], value)
          return
        end

        # Navigate/create intermediate objects
        current = output
        parts[0...-1].each do |part|
          existing = current[part]
          if existing.nil? || (existing.is_a?(Types::DynValue) && existing.null?)
            new_obj = {}
            current[part] = new_obj
            current = new_obj
          elsif existing.is_a?(Hash)
            current = existing
          elsif existing.is_a?(Types::DynValue) && existing.object?
            # DynValue object - convert to mutable hash
            h = existing.value.dup
            current[part] = h
            current = h
          else
            # Can't navigate into non-object
            return
          end
        end
        set_single_field(current, parts.last, value)
      end

      def set_single_field(obj, field, value)
        # Check for array index syntax: field[N]
        bracket_pos = field.index("[")
        if bracket_pos && field.end_with?("]")
          clean_field = field[0...bracket_pos]
          idx_str = field[bracket_pos + 1...-1]
          begin
            idx = Integer(idx_str)
            existing = obj[clean_field]
            arr = if existing.is_a?(Array)
                    existing
                  else
                    new_arr = []
                    obj[clean_field] = new_arr
                    new_arr
                  end
            arr[idx] = value
          rescue ArgumentError
            obj[field] = value
          end
        else
          obj[field] = value
        end
      end

      # ── Path Resolution ──

      def resolve_path(path, context)
        # Empty path (bare @) -> source root
        if path.nil? || path.empty?
          return context.in_loop? && context.current_item ? context.current_item : context.source
        end

        # Special paths
        if path.start_with?("$const.") || path.start_with?("$constants.")
          key = path.sub(/\A\$(?:const|constants)\./, "")
          return context.get_constant(key)
        end

        if path.start_with?("$accumulator.") || path.start_with?("$accumulators.")
          key = path.sub(/\A\$(?:accumulator|accumulators)\./, "")
          return context.get_accumulator(key)
        end

        # _index, _length loop vars
        if path == "_index" || path == "_length" || path == "_item"
          loop_var = context.loop_vars[path]
          return loop_var || Types::DynValue.of_null
        end

        # Check loop vars first
        if context.loop_vars.key?(path)
          return context.loop_vars[path]
        end

        # Determine source to navigate
        current_source = if context.in_loop? && context.current_item
                           context.current_item
                         else
                           context.source
                         end

        # Navigate the path
        resolve_dotted_path(current_source, path)
      end

      def resolve_path_from_string(path_str, source, context)
        return source if path_str.nil? || path_str.empty?

        # Handle @ prefix
        if path_str.start_with?("@")
          sub_path = path_str == "@" ? "" : path_str[1..]
          sub_path = sub_path[1..] if sub_path.start_with?(".") # strip leading .

          if sub_path.nil? || sub_path.empty?
            return context.in_loop? && context.current_item ? context.current_item : source
          end

          current_source = if context.in_loop? && context.current_item
                             context.current_item
                           else
                             source.is_a?(Types::DynValue) ? source : context.source
                           end
          return resolve_dotted_path(current_source, sub_path)
        end

        # Non-@ path — resolve from source
        current_source = source.is_a?(Types::DynValue) ? source : context.source
        resolve_dotted_path(current_source, path_str)
      end

      def resolve_dotted_path(source, path)
        return Types::DynValue.of_null unless source.is_a?(Types::DynValue)
        return source if path.nil? || path.empty?

        # Strip leading dot
        path = path[1..] if path.start_with?(".")

        segments = parse_path_segments(path)
        current = source

        segments.each do |seg|
          return Types::DynValue.of_null unless current.is_a?(Types::DynValue)

          case seg
          when Integer
            if current.array?
              current = current.get_index(seg) || Types::DynValue.of_null
            else
              return Types::DynValue.of_null
            end
          when String
            if current.object?
              current = current.get(seg) || Types::DynValue.of_null
            else
              return Types::DynValue.of_null
            end
          end
        end

        current
      end

      # Navigate dotted path in output Hash, creating intermediaries as needed
      def set_output_path(output, path, value)
        parts = path.split(".")
        current = output
        parts[0...-1].each do |part|
          current[part] ||= {}
          current = current[part]
        end
        current[parts.last] = value
      end

      def get_output_path(output, path)
        parts = path.split(".")
        current = output
        parts.each do |part|
          return nil unless current.is_a?(Hash) && current.key?(part)
          current = current[part]
        end
        current
      end

      def parse_path_segments(path)
        segments = []
        path.scan(/([^.\[\]]+)|\[(\d+)\]/) do |name, index|
          if index
            segments << index.to_i
          elsif name
            segments << name
          end
        end
        segments
      end

      # ── Verb Evaluation ──

      # Evaluate a verb expression, applying extraction directives to CopyExpr arguments
      def evaluate_verb_with_extraction(expr, context, extraction_directives)
        verb_name = expr.verb_name
        args = expr.arguments

        # Lazy evaluation for conditional verbs — apply extraction to result
        case verb_name
        when "ifElse"
          val = evaluate_if_else(args, context)
          return apply_extraction_directives(val, extraction_directives)
        when "cond"
          val = evaluate_cond(args, context)
          return apply_extraction_directives(val, extraction_directives)
        when "switch"
          val = evaluate_switch(args, context)
          return apply_extraction_directives(val, extraction_directives)
        end

        # Eager evaluation: apply extraction directives to CopyExpr arguments
        # Skip field-level extraction for CopyExpr that already has its own directives
        # (already applied in evaluate() for compatible source formats)
        evaluated_args = args.map do |arg|
          val = evaluate(arg, context)
          if arg.is_a?(CopyExpr) && arg.directives.empty?
            val = apply_extraction_directives(val, extraction_directives)
            # Also apply :trim
            extraction_directives.each do |d|
              val = apply_directive(val, d, nil, context) if d.name == "trim"
            end
          elsif arg.is_a?(VerbExpr)
            # Nested verb: apply extraction to its CopyExpr args too
            val = evaluate_verb_with_extraction(arg, context, extraction_directives)
          end
          val
        end

        # Special handling for accumulate/set
        case verb_name
        when "accumulate"
          return handle_accumulate(args, evaluated_args, context)
        when "set"
          return handle_set(args, evaluated_args, context)
        end

        # Custom verbs — passthrough
        if expr.respond_to?(:custom) && expr.custom && !@verb_registry.key?(verb_name)
          return evaluated_args.first || Types::DynValue.of_null
        end

        invoke_verb(verb_name, evaluated_args, context)
      end

      def evaluate_verb(expr, context)
        verb_name = expr.verb_name
        args = expr.arguments

        # Lazy evaluation for conditional verbs
        case verb_name
        when "ifElse"
          return evaluate_if_else(args, context)
        when "cond"
          return evaluate_cond(args, context)
        when "switch"
          return evaluate_switch(args, context)
        end

        # Eager evaluation for all other verbs
        evaluated_args = args.map { |arg| evaluate(arg, context) }

        # Special handling for accumulate/set
        case verb_name
        when "accumulate"
          return handle_accumulate(args, evaluated_args, context)
        when "set"
          return handle_set(args, evaluated_args, context)
        end

        # Custom verbs (namespace syntax) — passthrough first argument if not registered
        if expr.respond_to?(:custom) && expr.custom && !@verb_registry.key?(verb_name)
          return evaluated_args.first || Types::DynValue.of_null
        end

        # Look up and invoke verb
        invoke_verb(verb_name, evaluated_args, context)
      end

      def evaluate_if_else(args, context)
        return Types::DynValue.of_null if args.length < 3

        condition = evaluate(args[0], context)
        if condition.truthy?
          evaluate(args[1], context)
        else
          evaluate(args[2], context)
        end
      end

      def evaluate_cond(args, context)
        # pairs of condition, value, with optional default at end
        i = 0
        while i + 1 < args.length
          condition = evaluate(args[i], context)
          if condition.truthy?
            return evaluate(args[i + 1], context)
          end
          i += 2
        end

        # Odd number of args — last is default
        if args.length.odd?
          evaluate(args.last, context)
        else
          Types::DynValue.of_null
        end
      end

      def evaluate_switch(args, context)
        return Types::DynValue.of_null if args.empty?

        # First arg is the value to switch on
        switch_val = evaluate(args[0], context)

        i = 1
        while i + 1 < args.length
          case_val = evaluate(args[i], context)
          if dynvalue_equals(switch_val, case_val)
            return evaluate(args[i + 1], context)
          end
          i += 2
        end

        # Odd remaining args — last is default
        if (args.length - 1).odd?
          evaluate(args.last, context)
        else
          Types::DynValue.of_null
        end
      end

      def handle_accumulate(raw_args, evaluated_args, context)
        return Types::DynValue.of_null if raw_args.length < 2

        # First arg should be a string (accumulator name)
        name = if raw_args[0].is_a?(LiteralExpr)
                 raw_args[0].value.to_string
               else
                 evaluated_args[0].to_string
               end
        increment = evaluated_args[1]

        current = context.get_accumulator(name)
        if current.null?
          context.set_accumulator(name, increment)
          return increment
        end

        # Numeric accumulation
        new_val = Types::DynValue.of_float(current.to_number + increment.to_number)
        # Preserve integer type if both are integers
        if current.integer? && increment.integer?
          new_val = Types::DynValue.of_integer(current.to_number + increment.to_number)
        end

        context.set_accumulator(name, new_val)
        new_val
      end

      def handle_set(raw_args, evaluated_args, context)
        return Types::DynValue.of_null if raw_args.length < 2

        name = if raw_args[0].is_a?(LiteralExpr)
                 raw_args[0].value.to_string
               else
                 evaluated_args[0].to_string
               end
        value = evaluated_args[1]
        context.set_accumulator(name, value)
        value
      end

      def dynvalue_equals(a, b)
        return true if a == b
        return true if a.to_string == b.to_string

        false
      end

      # ── Condition Evaluation ──

      def evaluate_condition(condition_str, source, context)
        return true if condition_str.nil? || condition_str.strip.empty?

        str = condition_str.strip

        # Handle verb expression in condition
        if str.start_with?("%")
          parser = TransformParser.new
          expr, = parser.parse_expression_string(str)
          result = evaluate(expr, context)
          return result.truthy?
        end

        # Handle comparison operators
        operators = ["!=", "<>", "<=", ">=", "==", "=", "<", ">"]
        operators.each do |op|
          idx = str.index(op)
          next unless idx

          lhs_str = str[0...idx].strip
          rhs_str = str[(idx + op.length)..].strip

          lhs_val = resolve_condition_value(lhs_str, source, context)
          rhs_val = resolve_condition_value(rhs_str, source, context)

          return evaluate_comparison(lhs_val, op, rhs_val)
        end

        # Simple truthy check
        val = resolve_condition_value(str, source, context)
        val.truthy?
      end

      def resolve_condition_value(str, source, context)
        if str.start_with?("@")
          path = str == "@" ? "" : str[1..]
          path = path[1..] if path&.start_with?(".")
          if path.nil? || path.empty?
            context.in_loop? && context.current_item ? context.current_item : source
          else
            resolve_dotted_path(source.is_a?(Types::DynValue) ? source : context.source, path)
          end
        elsif str.start_with?('"') && str.end_with?('"')
          Types::DynValue.of_string(str[1...-1])
        elsif str.start_with?("'") && str.end_with?("'")
          Types::DynValue.of_string(str[1...-1])
        elsif str == "true"
          Types::DynValue.of_bool(true)
        elsif str == "false"
          Types::DynValue.of_bool(false)
        elsif str == "null" || str == "nil"
          Types::DynValue.of_null
        elsif str.match?(/\A-?\d+\z/)
          Types::DynValue.of_integer(str.to_i)
        elsif str.match?(/\A-?\d+\.\d+\z/)
          Types::DynValue.of_float(str.to_f)
        else
          # Treat as path without @
          resolve_dotted_path(source.is_a?(Types::DynValue) ? source : context.source, str)
        end
      end

      def evaluate_comparison(lhs, op, rhs)
        case op
        when "=", "=="
          dynvalue_equals(lhs, rhs)
        when "!=", "<>"
          !dynvalue_equals(lhs, rhs)
        when "<"
          lhs.to_number < rhs.to_number
        when "<="
          lhs.to_number <= rhs.to_number
        when ">"
          lhs.to_number > rhs.to_number
        when ">="
          lhs.to_number >= rhs.to_number
        else
          false
        end
      end

      # ── Extraction Directives (:pos, :len, :field) ──
      # Check if an expression has CopyExpr with its own extraction directives
      def expr_has_extraction_directives?(expr)
        case expr
        when CopyExpr
          expr.directives.any? { |d| %w[pos len field trim].include?(d.name) }
        when VerbExpr
          expr.arguments.any? { |arg| expr_has_extraction_directives?(arg) }
        else
          false
        end
      end

      # These must be applied as a group: field first, then pos/len

      def apply_extraction_directives(val, directives)
        pos_val = nil
        len_val = nil
        field_idx = nil
        should_trim = false

        directives.each do |d|
          case d.name
          when "pos"
            pos_val = d.value.to_i if d.value
          when "len"
            len_val = d.value.to_i if d.value
          when "field"
            field_idx = d.value.to_i if d.value
          when "trim"
            should_trim = true
          end
        end

        return val unless pos_val || len_val || field_idx || should_trim
        return val unless val.string?

        s = val.value

        # Field extraction first (split by comma)
        if field_idx
          fields = s.split(",", -1)
          s = field_idx < fields.length ? fields[field_idx].strip : ""
        end

        # Then positional extraction
        if pos_val
          if len_val
            s = s[pos_val, len_val] || ""
          else
            s = s[pos_val..] || ""
          end
        end

        # Trim
        s = s.strip if should_trim

        Types::DynValue.of_string(s)
      end

      # ── Directive Application ──

      def apply_directive(val, directive, source, context)
        case directive.name
        when "type"
          coerce_to_type(val, directive.value.to_s)
        when "trim"
          val.string? ? Types::DynValue.of_string(val.value.strip) : val
        when "default"
          val.null? ? Types::DynValue.of_string(directive.value.to_s) : val
        when "upper"
          val.string? ? Types::DynValue.of_string(val.value.upcase) : val
        when "lower"
          val.string? ? Types::DynValue.of_string(val.value.downcase) : val
        when "maxLen"
          if val.string? && directive.value.is_a?(Integer)
            Types::DynValue.of_string(val.value[0...directive.value])
          else
            val
          end
        when "leftPad"
          val
        when "rightPad"
          val
        when "truncate"
          if val.string? && directive.value.is_a?(Integer)
            Types::DynValue.of_string(val.value[0...directive.value])
          else
            val
          end
        when "date"
          coerce_to_type(val, "date")
        when "time"
          coerce_to_type(val, "time")
        when "timestamp"
          coerce_to_type(val, "timestamp")
        when "integer"
          coerce_to_type(val, "integer")
        when "number"
          coerce_to_type(val, "number")
        when "boolean"
          coerce_to_type(val, "boolean")
        when "decimals"
          if val.is_a?(Types::DynValue) && (val.type == :currency || val.type == :currency_raw)
            dp = directive.value.to_i
            if val.type == :currency_raw
              # Re-format the raw value with new decimal places
              Types::DynValue.of_currency_raw(val.value, dp, val.currency_code)
            else
              Types::DynValue.of_currency(val.value.to_f, dp, val.currency_code)
            end
          else
            val
          end
        when "currencyCode"
          if val.is_a?(Types::DynValue) && (val.type == :currency || val.type == :currency_raw)
            code = directive.value.to_s.gsub('"', '')
            if val.type == :currency_raw
              Types::DynValue.of_currency_raw(val.value, val.decimal_places || 2, code)
            else
              Types::DynValue.of_currency(val.value.to_f, val.decimal_places || 2, code)
            end
          else
            val
          end
        when "duration"
          coerce_to_type(val, "duration")
        else
          val
        end
      end

      def coerce_to_type(val, type_name)
        # Null values stay null regardless of target type
        return val if val.null?

        case type_name
        when "integer"
          Types::DynValue.of_integer(val.to_number.to_i)
        when "number", "float"
          coerce_to_number(val)
        when "string"
          Types::DynValue.of_string(val.to_string)
        when "boolean"
          coerce_to_boolean(val)
        when "currency"
          coerce_to_currency(val)
        when "percent"
          Types::DynValue.of_percent(val.to_number.to_f)
        when "date"
          Types::DynValue.of_date(val.to_string)
        when "timestamp"
          coerce_to_timestamp(val)
        when "time"
          Types::DynValue.of_time(val.to_string)
        when "reference"
          Types::DynValue.of_reference(val.to_string)
        when "binary"
          Types::DynValue.of_binary(val.to_string)
        when "duration"
          Types::DynValue.of_duration(val.to_string)
        else
          val
        end
      end

      def coerce_to_number(val)
        # If already a numeric type, return as float
        if val.type == :integer
          return Types::DynValue.of_float(val.value.to_f)
        end
        if val.type == :float || val.type == :float_raw
          return val
        end
        if val.type == :currency || val.type == :currency_raw
          return Types::DynValue.of_float(val.to_number.to_f)
        end
        # String coercion
        s = val.to_string
        return val if s.nil? || s.empty?
        begin
          f = Float(s)
          # Check if OdinFormatter's integer shortcut would alter the representation
          rt = f.to_s
          if rt == s
            if f == f.floor && !f.infinite? && f.abs < 1e15 && s.include?(".")
              return Types::DynValue.of_float_raw(s)
            end
            return Types::DynValue.of_float(f)
          end
          Types::DynValue.of_float_raw(s)
        rescue ArgumentError
          val
        end
      end

      def coerce_to_boolean(val)
        s = val.to_string.downcase
        case s
        when "true", "yes", "1" then Types::DynValue.of_bool(true)
        when "false", "no", "0" then Types::DynValue.of_bool(false)
        else
          if val.type == :integer
            Types::DynValue.of_bool(val.value != 0)
          elsif val.type == :float
            Types::DynValue.of_bool(val.value != 0.0)
          else
            Types::DynValue.of_bool(val.truthy?)
          end
        end
      end

      def coerce_to_timestamp(val)
        return val unless val.type == :string
        ts_str = val.to_string
        begin
          require "time"
          parsed = Time.parse(ts_str)
          utc = parsed.utc
          normalized = utc.strftime("%Y-%m-%dT%H:%M:%S.%LZ")
          Types::DynValue.of_timestamp(normalized)
        rescue ArgumentError, TypeError
          Types::DynValue.of_timestamp(ts_str)
        end
      end

      def coerce_to_currency(val, dp = 2, currency_code = nil)
        if val.type == :float || val.type == :float_raw
          f = val.to_number.to_f
          formatted = format("%.#{dp}f", f)
          g_str = f.to_s
          if formatted != g_str
            return Types::DynValue.of_currency_raw(formatted, dp, currency_code)
          end
          return Types::DynValue.of_currency(f, dp, currency_code)
        end
        if val.type == :integer
          return Types::DynValue.of_currency(val.value.to_f, dp, currency_code)
        end
        s = val.to_string
        return val if s.nil? || s.empty?
        cleaned = s.gsub(/[$£€,]/, "")
        actual_dp = if cleaned.include?(".")
                      cleaned.length - cleaned.index(".") - 1
                    else
                      dp
                    end
        begin
          f = Float(cleaned)
          rt = f.to_s
          if rt == cleaned
            Types::DynValue.of_currency(f, actual_dp, currency_code)
          else
            Types::DynValue.of_currency_raw(cleaned, actual_dp, currency_code)
          end
        rescue ArgumentError
          val
        end
      end

      # ── Confidential Enforcement ──

      def apply_confidential(output, mode, field_modifiers)
        field_modifiers.each do |field_path, modifiers|
          next unless modifiers.include?(FieldModifier::CONFIDENTIAL)

          # Navigate to the field in output
          parts = field_path.split(".")
          target = output

          parts[0...-1].each do |part|
            if target.is_a?(Hash)
              target = target[part]
            else
              target = nil
              break
            end
          end

          next unless target.is_a?(Hash)

          field_name = parts.last
          next unless target.key?(field_name)

          case mode
          when ConfidentialMode::REDACT
            target[field_name] = Types::DynValue.of_null
          when ConfidentialMode::MASK
            val = target[field_name]
            target[field_name] = mask_dynvalue(val)
          end
        end
      end

      def mask_value(val)
        case val
        when String
          "*" * [val.length, 3].max
        when Integer, Float
          nil
        when TrueClass, FalseClass
          nil
        else
          nil
        end
      end

      def mask_dynvalue(val)
        if val.is_a?(Types::DynValue)
          case val.type
          when :string
            Types::DynValue.of_string("*" * [val.value.length, 3].max)
          else
            Types::DynValue.of_null
          end
        else
          mask_value(val)
        end
      end

      # ── Object Expression Evaluation ──

      def evaluate_object(expr, context)
        result = {}
        expr.field_mappings.each do |mapping|
          val = evaluate(mapping.expression, context)
          result[mapping.target_field] = val
        end
        Types::DynValue.of_object(result)
      end

      # ── Format Output ──

      def format_output(output_dv, transform_def, context = nil)
        target_format = transform_def.target_format
        return nil unless target_format

        case target_format
        when "json"
          topts = transform_def.header.target_options
          indent_val = topts["indent"]
          indent = indent_val ? parse_target_int(indent_val, 2) : 2
          nulls = topts["nulls"]
          empty_arrays = topts["emptyArrays"]
          FormatExporters.to_json(output_dv, pretty: indent > 0, indent: indent, nulls: nulls, empty_arrays: empty_arrays)
        when "odin"
          mods = context ? context.field_modifiers : {}
          header_val = transform_def.header.target_options["header"]
          include_header = header_val == "true" || header_val == "?true"
          FormatExporters.to_odin(output_dv, header: include_header, modifiers: mods)
        when "xml"
          format_xml_output(output_dv, transform_def, context)
        when "csv"
          topts = transform_def.header.target_options
          delimiter = topts["delimiter"] || ","
          header_val = topts["header"]
          include_header = header_val != "false" && header_val != "?false"
          # For CSV, unwrap single-key object containing an array
          csv_dv = output_dv
          if csv_dv.object? && csv_dv.value.size == 1
            inner = csv_dv.value.values.first
            csv_dv = inner if inner.array?
          end
          FormatExporters.to_csv(csv_dv, delimiter: delimiter, header: include_header)
        when "fixed-width"
          format_fixed_width_output(output_dv, transform_def)
        when "flat", "properties"
          style = transform_def.header.target_options["style"]
          if style == "yaml"
            FormatExporters.to_flat_yaml(output_dv)
          else
            FormatExporters.to_flat_kvp(output_dv)
          end
        else
          # Default to JSON
          FormatExporters.to_json(output_dv, pretty: true)
        end
      end

      # Format output as fixed-width text (segment-based, matching TypeScript)
      def format_fixed_width_output(output_dv, transform_def)
        line_width = 80
        lw = transform_def.header.target_options["lineWidth"]
        line_width = lw.to_i if lw && lw.to_i > 0
        default_pad = transform_def.header.target_options["padChar"] || " "
        line_ending = transform_def.header.target_options["lineEnding"] || "\n"

        lines = []

        transform_def.segments.each do |segment|
          seg_name = segment.name
          seg_data = resolve_segment_data(output_dv, seg_name)

          if segment.is_array && seg_data.is_a?(Array)
            # Array segment: one line per item
            seg_data.each do |item|
              data = item.is_a?(Types::DynValue) ? dynvalue_to_flat_hash(item) : (item.is_a?(Hash) ? item : {})
              lines << format_fwf_line(segment.field_mappings, data, line_width, default_pad)
            end
          elsif segment.is_array && seg_data.is_a?(Types::DynValue) && seg_data.array?
            seg_data.value.each do |item|
              data = dynvalue_to_flat_hash(item)
              lines << format_fwf_line(segment.field_mappings, data, line_width, default_pad)
            end
          else
            # Single segment: one line
            data = if seg_data.is_a?(Types::DynValue)
                     dynvalue_to_flat_hash(seg_data)
                   elsif seg_data.is_a?(Hash)
                     seg_data
                   else
                     dynvalue_to_flat_hash(output_dv)
                   end
            lines << format_fwf_line(segment.field_mappings, data, line_width, default_pad)
          end
        end

        lines.join(line_ending)
      end

      # Parse an integer from a target option value, handling ODIN ##N prefix
      def parse_target_int(val, default_val)
        return default_val if val.nil?
        # Strip ODIN integer prefix ##
        stripped = val.to_s.sub(/\A##/, "")
        stripped.to_i
      rescue
        default_val
      end

      def resolve_segment_data(output_dv, seg_name)
        return output_dv unless output_dv.is_a?(Types::DynValue) && output_dv.object?

        parts = seg_name.split(".")
        current = output_dv
        parts.each do |part|
          return nil unless current.is_a?(Types::DynValue) && current.object?
          current = current.get(part)
          return nil unless current
        end
        current
      end

      def dynvalue_to_flat_hash(dv)
        return {} unless dv.is_a?(Types::DynValue) && dv.object?
        result = {}
        dv.value.each do |k, v|
          result[k] = v
        end
        result
      end

      def format_fwf_line(mappings, data, line_width, default_pad)
        # Sort mappings by :pos for deterministic output
        sorted = mappings.sort_by do |m|
          pos_dir = m.directives.find { |d| d.name == "pos" }
          pos_dir ? pos_dir.value.to_i : 0
        end

        line = ""

        sorted.each do |mapping|
          pos_dir = mapping.directives.find { |d| d.name == "pos" }
          len_dir = mapping.directives.find { |d| d.name == "len" }
          left_pad_dir = mapping.directives.find { |d| d.name == "leftPad" }
          right_pad_dir = mapping.directives.find { |d| d.name == "rightPad" }

          next unless pos_dir && len_dir

          pos = pos_dir.value.to_i
          len = len_dir.value.to_i
          next if len == 0

          # Fill gap to field position
          if line.length < pos
            line += default_pad * (pos - line.length)
          end

          # Get field value
          raw_val = data[mapping.target_field]
          value = if raw_val.is_a?(Types::DynValue)
                    FormatExporters.send(:dynvalue_to_string, raw_val)
                  elsif raw_val.nil?
                    ""
                  else
                    raw_val.to_s
                  end

          # Determine pad character
          pad_char = default_pad
          if left_pad_dir
            pad_char = left_pad_dir.value.to_s[0] || " "
          elsif right_pad_dir
            pad_char = right_pad_dir.value.to_s[0] || " "
          end

          # Truncate if needed
          value = value[0...len] if value.length > len

          # Apply padding
          if left_pad_dir || (!right_pad_dir && raw_val.is_a?(Types::DynValue) &&
              (raw_val.type == :integer || raw_val.type == :float || raw_val.type == :currency))
            value = value.rjust(len, pad_char)
          else
            value = value.ljust(len, pad_char)
          end

          # Splice into line at position
          if pos < line.length
            line = line[0...pos] + value + (pos + len < line.length ? line[(pos + len)..] : "")
          else
            line += value
          end
        end

        line
      end

      # ── XML Output Formatting (segment-based, matching TypeScript) ──

      def format_xml_output(output_dv, transform_def, context)
        topts = transform_def.header.target_options
        decl_val = topts["declaration"]
        include_declaration = decl_val != "false" && decl_val != "?false"
        indent_val = topts["indent"]
        indent_size = indent_val ? parse_target_int(indent_val, 2) : 2
        indent_str = " " * indent_size

        xml = +""
        xml << %{<?xml version="1.0" encoding="UTF-8"?>\n} if include_declaration

        # Collect which fields have :attr directive per segment
        attr_fields = {}
        transform_def.segments.each do |segment|
          segment.field_mappings.each do |mapping|
            if mapping.directives.any? { |d| d.name == "attr" }
              attr_fields["#{segment.name}.#{mapping.target_field}"] = true
            end
          end
        end

        transform_def.segments.each do |segment|
          seg_name = segment.name
          seg_data = resolve_segment_data(output_dv, seg_name)

          if segment.is_array
            items = if seg_data.is_a?(Types::DynValue) && seg_data.array?
                      seg_data.value
                    elsif seg_data.is_a?(Array)
                      seg_data
                    else
                      []
                    end
            items.each do |item|
              xml << render_xml_segment_element(seg_name, item, segment, attr_fields, is_array: true, indent_str: indent_str)
            end
          else
            data = if seg_data.is_a?(Types::DynValue)
                     seg_data
                   elsif seg_data.is_a?(Hash)
                     Types::DynValue.from_ruby(seg_data)
                   else
                     output_dv
                   end
            xml << render_xml_segment_element(seg_name, data, segment, attr_fields, is_array: false, indent_str: indent_str)
          end
        end

        xml
      end

      def render_xml_segment_element(seg_name, data, segment, attr_fields, is_array: false, indent_str: "  ")
        return "" unless data.is_a?(Types::DynValue) && data.object?

        entries = data.value
        # Determine which fields are :attr and which are child elements
        attr_parts = []
        child_keys = []
        has_typed = false

        segment.field_mappings.each do |mapping|
          key = mapping.target_field
          next if key.start_with?("_")
          val = entries[key]
          next unless val

          is_attr = attr_fields["#{seg_name}.#{key}"]
          if is_attr
            attr_parts << "#{key}=\"#{xml_escape_attr(val_to_xml_string(val))}\""
          else
            child_keys << key
            has_typed = true if xml_type_attr(val) != ""
          end
        end

        # Non-array segments always get xmlns:odin namespace
        ns = !is_array ? ' xmlns:odin="https://odin.foundation/ns"' : ""
        attrs = attr_parts.empty? ? "" : " #{attr_parts.join(' ')}"

        xml = +"<#{seg_name}#{ns}#{attrs}>\n"
        child_keys.each do |key|
          val = entries[key]
          next unless val
          type_attr = xml_type_attr(val)
          xml << "#{indent_str}<#{key}#{type_attr}>#{xml_escape_attr(val_to_xml_string(val))}</#{key}>\n"
        end
        xml << "</#{seg_name}>\n"
        xml
      end

      def xml_type_attr(dv)
        case dv.type
        when :null then ' odin:type="null"'
        when :bool then ' odin:type="boolean"'
        when :integer then ' odin:type="integer"'
        when :float, :float_raw
          v = dv.value.to_f
          v == v.to_i.to_f && v.abs < 1e15 ? ' odin:type="integer"' : ' odin:type="number"'
        when :currency, :currency_raw
          v = dv.value.to_f
          v == v.to_i.to_f && v.abs < 1e15 ? ' odin:type="integer"' : ' odin:type="number"'
        when :percent then ' odin:type="percent"'
        else ""
        end
      end

      def val_to_xml_string(dv)
        case dv.type
        when :null then ""
        when :bool then dv.value.to_s
        when :integer then dv.value.to_s
        when :float then FormatExporters.send(:format_number, dv.value)
        when :string then dv.value
        when :currency
          v = dv.value.to_f
          v == v.to_i && v.abs < 1e15 ? v.to_i.to_s : v.to_s
        else FormatExporters.send(:dynvalue_to_string, dv)
        end
      end

      def xml_escape_attr(s)
        s.gsub("&", "&amp;")
         .gsub("<", "&lt;")
         .gsub(">", "&gt;")
         .gsub('"', "&quot;")
         .gsub("'", "&apos;")
      end

      # ── Verb Registry ──

      def build_verb_registry
        registry = {}

        # Core verbs that are needed for engine testing
        register_core_verbs(registry)

        # Phase 10 verb categories (override core verbs where needed)
        Verbs::NumericVerbs.register(registry)
        Verbs::CollectionVerbs.register(registry)
        Verbs::DateTimeVerbs.register(registry)
        Verbs::FinancialVerbs.register(registry)
        Verbs::AggregationVerbs.register(registry)
        Verbs::ObjectVerbs.register(registry)
        Verbs::GeoVerbs.register(registry)

        registry
      end

      def register_core_verbs(registry)
        # String verbs
        registry["upper"] = ->(args, _ctx) { args[0]&.string? ? Types::DynValue.of_string(args[0].value.upcase) : (args[0] || Types::DynValue.of_null) }
        registry["lower"] = ->(args, _ctx) { args[0]&.string? ? Types::DynValue.of_string(args[0].value.downcase) : (args[0] || Types::DynValue.of_null) }
        registry["trim"] = ->(args, _ctx) { args[0]&.string? ? Types::DynValue.of_string(args[0].value.strip) : (args[0] || Types::DynValue.of_null) }
        registry["capitalize"] = ->(args, _ctx) {
          if args[0]&.string?
            s = args[0].value
            Types::DynValue.of_string(s.empty? ? s : s[0].upcase + s[1..])
          else
            args[0] || Types::DynValue.of_null
          end
        }
        registry["length"] = ->(args, _ctx) {
          v = args[0]
          if v&.string?
            Types::DynValue.of_integer(v.value.length)
          elsif v&.array?
            Types::DynValue.of_integer(v.value.length)
          else
            Types::DynValue.of_integer(0)
          end
        }

        # Concat (variadic)
        registry["concat"] = ->(args, _ctx) {
          result = args.map { |a| a.is_a?(Types::DynValue) ? a.to_string : a.to_s }.join
          Types::DynValue.of_string(result)
        }

        # Coalesce (variadic)
        registry["coalesce"] = ->(args, _ctx) {
          args.each { |a| return a unless a.null? }
          Types::DynValue.of_null
        }

        # Comparisons
        registry["eq"] = ->(args, _ctx) {
          a, b = args
          Types::DynValue.of_bool(a&.to_string == b&.to_string)
        }
        registry["ne"] = ->(args, _ctx) {
          a, b = args
          Types::DynValue.of_bool(a&.to_string != b&.to_string)
        }

        # Null checks
        registry["ifNull"] = ->(args, _ctx) {
          a, b = args
          (a.nil? || a.null?) ? (b || Types::DynValue.of_null) : a
        }
        registry["ifEmpty"] = ->(args, _ctx) {
          a, b = args
          if a.nil? || a.null? || (a.string? && a.value.empty?)
            b || Types::DynValue.of_null
          else
            a
          end
        }
        registry["isNull"] = ->(args, _ctx) {
          Types::DynValue.of_bool(args[0].nil? || args[0].null?)
        }
        registry["not"] = ->(args, _ctx) {
          Types::DynValue.of_bool(!args[0]&.truthy?)
        }

        # Type checks
        registry["typeOf"] = ->(args, _ctx) {
          v = args[0]
          type_str = v.nil? ? "null" : v.type.to_s
          Types::DynValue.of_string(type_str)
        }
        registry["isString"] = ->(args, _ctx) { Types::DynValue.of_bool(args[0]&.string? || false) }
        registry["isNumber"] = ->(args, _ctx) { Types::DynValue.of_bool(args[0]&.numeric? || false) }
        registry["isBoolean"] = ->(args, _ctx) { Types::DynValue.of_bool(args[0]&.bool? || false) }
        registry["isArray"] = ->(args, _ctx) { Types::DynValue.of_bool(args[0]&.array? || false) }
        registry["isObject"] = ->(args, _ctx) { Types::DynValue.of_bool(args[0]&.object? || false) }
        registry["isDate"] = ->(args, _ctx) { Types::DynValue.of_bool(args[0]&.date? || false) }

        # Coercion
        registry["coerceString"] = ->(args, _ctx) { Types::DynValue.of_string(args[0]&.to_string || "") }
        registry["coerceNumber"] = ->(args, _ctx) { Types::DynValue.of_float(args[0]&.to_number&.to_f || 0.0) }
        registry["coerceInteger"] = ->(args, _ctx) { Types::DynValue.of_integer(args[0]&.to_number&.to_i || 0) }
        registry["coerceBoolean"] = ->(args, _ctx) { Types::DynValue.of_bool(args[0]&.truthy? || false) }

        # Arithmetic
        registry["add"] = ->(args, _ctx) {
          a, b = args
          av = a&.to_number || 0
          bv = b&.to_number || 0
          if a&.integer? && b&.integer?
            Types::DynValue.of_integer(av + bv)
          else
            Types::DynValue.of_float(av.to_f + bv.to_f)
          end
        }
        registry["subtract"] = ->(args, _ctx) {
          a, b = args
          av = a&.to_number || 0
          bv = b&.to_number || 0
          if a&.integer? && b&.integer?
            Types::DynValue.of_integer(av - bv)
          else
            Types::DynValue.of_float(av.to_f - bv.to_f)
          end
        }
        registry["multiply"] = ->(args, _ctx) {
          a, b = args
          av = a&.to_number || 0
          bv = b&.to_number || 0
          if a&.integer? && b&.integer?
            Types::DynValue.of_integer(av * bv)
          else
            Types::DynValue.of_float(av.to_f * bv.to_f)
          end
        }
        registry["divide"] = ->(args, _ctx) {
          a, b = args
          bv = b&.to_number || 0
          return Types::DynValue.of_null if bv == 0

          Types::DynValue.of_float((a&.to_number || 0).to_f / bv.to_f)
        }

        # Accumulate/set handled specially in evaluate_verb
        registry["accumulate"] = ->(args, ctx) {
          name = args[0]&.to_string || ""
          increment = args[1] || Types::DynValue.of_integer(0)
          current = ctx.get_accumulator(name)
          if current.null?
            ctx.set_accumulator(name, increment)
            increment
          else
            new_val = if current.integer? && increment.integer?
                        Types::DynValue.of_integer(current.to_number + increment.to_number)
                      else
                        Types::DynValue.of_float(current.to_number.to_f + increment.to_number.to_f)
                      end
            ctx.set_accumulator(name, new_val)
            new_val
          end
        }

        registry["set"] = ->(args, ctx) {
          name = args[0]&.to_string || ""
          value = args[1] || Types::DynValue.of_null
          ctx.set_accumulator(name, value)
          value
        }

        # Today/Now
        registry["today"] = ->(_args, _ctx) {
          Types::DynValue.of_date(Time.now.utc.strftime("%Y-%m-%d"))
        }
        registry["now"] = ->(_args, _ctx) {
          Types::DynValue.of_timestamp(Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ"))
        }

        # Lookup: %lookup "TABLE.returnColumn" matchValue1 [matchValue2 ...]
        registry["lookup"] = ->(args, ctx) {
          return Types::DynValue.of_null if args.length < 2

          table_ref = args[0]&.to_string || ""

          # Parse TABLE.column syntax
          dot_index = table_ref.index(".")
          return Types::DynValue.of_null unless dot_index

          table_name = table_ref[0...dot_index]
          return_column = table_ref[(dot_index + 1)..]

          table = ctx.get_table(table_name)
          return Types::DynValue.of_null unless table

          # Get match values (all args after table ref)
          match_values = args[1..].map { |a| a&.to_string || "" }

          # Build list of match columns (all columns except return column)
          columns = table.columns
          return_col_index = columns.index(return_column)
          return Types::DynValue.of_null unless return_col_index

          match_col_names = columns.reject { |c| c == return_column }

          # Find matching row
          table.rows.each do |row|
            matches = true
            match_values.each_with_index do |mv, i|
              break if i >= match_col_names.length
              col_name = match_col_names[i]
              row_val = row[col_name]
              if row_val && row_val.to_string != mv
                matches = false
                break
              end
            end

            if matches
              return row[return_column] || Types::DynValue.of_null
            end
          end

          Types::DynValue.of_null
        }

        # LookupDefault: %lookupDefault "TABLE.returnColumn" matchValue1 [...] defaultValue
        registry["lookupDefault"] = ->(args, ctx) {
          return Types::DynValue.of_null if args.length < 3

          table_ref = args[0]&.to_string || ""
          default_val = args[-1] || Types::DynValue.of_null

          # Parse TABLE.column syntax
          dot_index = table_ref.index(".")
          return default_val unless dot_index

          table_name = table_ref[0...dot_index]
          return_column = table_ref[(dot_index + 1)..]

          table = ctx.get_table(table_name)
          return default_val unless table

          columns = table.columns
          return_col_index = columns.index(return_column)
          return default_val unless return_col_index

          # Get match values (between table ref and default)
          match_values = args[1...-1].map { |a| a&.to_string || "" }

          match_col_names = columns.reject { |c| c == return_column }

          # Find matching row
          table.rows.each do |row|
            matches = true
            match_values.each_with_index do |mv, i|
              break if i >= match_col_names.length
              col_name = match_col_names[i]
              row_val = row[col_name]
              if row_val && row_val.to_string != mv
                matches = false
                break
              end
            end

            if matches
              return row[return_column] || default_val
            end
          end

          default_val
        }

        # Sequence
        registry["sequence"] = ->(args, ctx) {
          name = args[0]&.to_string || "default"
          val = ctx.next_sequence(name)
          Types::DynValue.of_integer(val)
        }

        registry["resetSequence"] = ->(args, ctx) {
          name = args[0]&.to_string || "default"
          ctx.reset_sequence(name)
          Types::DynValue.of_integer(0)
        }

        # Min/Max of variadic
        registry["minOf"] = ->(args, _ctx) {
          nums = args.map { |a| a.to_number }
          Types::DynValue.of_float(nums.min || 0)
        }
        registry["maxOf"] = ->(args, _ctx) {
          nums = args.map { |a| a.to_number }
          Types::DynValue.of_float(nums.max || 0)
        }

        # Collection basics
        registry["first"] = ->(args, _ctx) {
          v = args[0]
          v&.array? && !v.value.empty? ? v.value.first : Types::DynValue.of_null
        }
        registry["last"] = ->(args, _ctx) {
          v = args[0]
          v&.array? && !v.value.empty? ? v.value.last : Types::DynValue.of_null
        }
        registry["count"] = ->(args, _ctx) {
          v = args[0]
          v&.array? ? Types::DynValue.of_integer(v.value.length) : Types::DynValue.of_integer(0)
        }
        registry["sum"] = ->(args, _ctx) {
          v = args[0]
          if v&.array?
            total = v.value.sum { |item| item.to_number.to_f }
            Types::DynValue.of_float(total)
          else
            Types::DynValue.of_float(0)
          end
        }
        registry["join"] = ->(args, _ctx) {
          v = args[0]
          sep = args[1]&.to_string || ","
          if v&.array?
            result = v.value.map(&:to_string).join(sep)
            Types::DynValue.of_string(result)
          else
            v || Types::DynValue.of_null
          end
        }

        # Object verbs
        registry["keys"] = ->(args, _ctx) {
          v = args[0]
          if v&.object?
            Types::DynValue.of_array(v.value.keys.map { |k| Types::DynValue.of_string(k) })
          else
            Types::DynValue.of_array([])
          end
        }
        registry["values"] = ->(args, _ctx) {
          v = args[0]
          if v&.object?
            Types::DynValue.of_array(v.value.values)
          else
            Types::DynValue.of_array([])
          end
        }
        registry["has"] = ->(args, _ctx) {
          obj = args[0]
          key = args[1]&.to_string || ""
          Types::DynValue.of_bool(obj&.object? && obj.value.key?(key))
        }
        registry["merge"] = ->(args, _ctx) {
          a = args[0]
          b = args[1]
          if a&.object? && b&.object?
            merged = a.value.merge(b.value)
            Types::DynValue.of_object(merged)
          else
            a || Types::DynValue.of_null
          end
        }

        # Boolean logic
        registry["and"] = ->(args, _ctx) {
          Types::DynValue.of_bool(args[0]&.truthy? && args[1]&.truthy?)
        }
        registry["or"] = ->(args, _ctx) {
          Types::DynValue.of_bool(args[0]&.truthy? || args[1]&.truthy?)
        }

        # Comparison
        registry["lt"] = ->(args, _ctx) {
          Types::DynValue.of_bool((args[0]&.to_number || 0) < (args[1]&.to_number || 0))
        }
        registry["lte"] = ->(args, _ctx) {
          Types::DynValue.of_bool((args[0]&.to_number || 0) <= (args[1]&.to_number || 0))
        }
        registry["gt"] = ->(args, _ctx) {
          Types::DynValue.of_bool((args[0]&.to_number || 0) > (args[1]&.to_number || 0))
        }
        registry["gte"] = ->(args, _ctx) {
          Types::DynValue.of_bool((args[0]&.to_number || 0) >= (args[1]&.to_number || 0))
        }

        # String operations
        registry["contains"] = ->(args, _ctx) {
          a = args[0]&.to_string || ""
          b = args[1]&.to_string || ""
          Types::DynValue.of_bool(a.include?(b))
        }
        registry["startsWith"] = ->(args, _ctx) {
          a = args[0]&.to_string || ""
          b = args[1]&.to_string || ""
          Types::DynValue.of_bool(a.start_with?(b))
        }
        registry["endsWith"] = ->(args, _ctx) {
          a = args[0]&.to_string || ""
          b = args[1]&.to_string || ""
          Types::DynValue.of_bool(a.end_with?(b))
        }
        registry["substring"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          start = args[1]&.to_number&.to_i || 0
          len = args[2]&.to_number&.to_i || s.length
          Types::DynValue.of_string(s[start, len] || "")
        }
        registry["replace"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          from = args[1]&.to_string || ""
          to = args[2]&.to_string || ""
          Types::DynValue.of_string(s.gsub(from, to))
        }

        # Math
        registry["abs"] = ->(args, _ctx) {
          v = args[0]
          n = v&.to_number || 0
          v&.integer? ? Types::DynValue.of_integer(n.abs) : Types::DynValue.of_float(n.to_f.abs)
        }
        registry["floor"] = ->(args, _ctx) { Types::DynValue.of_integer((args[0]&.to_number || 0).floor) }
        registry["ceil"] = ->(args, _ctx) { Types::DynValue.of_integer((args[0]&.to_number || 0).ceil) }
        registry["round"] = ->(args, _ctx) {
          n = args[0]&.to_number || 0
          places = args[1]&.to_number&.to_i || 0
          Types::DynValue.of_float(n.to_f.round(places))
        }
        registry["negate"] = ->(args, _ctx) {
          v = args[0]
          n = v&.to_number || 0
          v&.integer? ? Types::DynValue.of_integer(-n) : Types::DynValue.of_float(-n.to_f)
        }
        registry["mod"] = ->(args, _ctx) {
          a = args[0]&.to_number || 0
          b = args[1]&.to_number || 0
          return Types::DynValue.of_null if b == 0

          Types::DynValue.of_integer(a.to_i % b.to_i)
        }

        # At/get
        registry["at"] = ->(args, _ctx) {
          arr = args[0]
          idx = args[1]&.to_number&.to_i || 0
          arr&.array? ? (arr.get_index(idx) || Types::DynValue.of_null) : Types::DynValue.of_null
        }
        registry["get"] = ->(args, _ctx) {
          obj = args[0]
          key = args[1]&.to_string || ""
          default_val = args[2] || Types::DynValue.of_null
          if obj&.object?
            obj.get(key) || default_val
          else
            default_val
          end
        }

        # Assertions
        registry["assert"] = ->(args, _ctx) {
          condition = args[0]
          msg = args[1]&.to_string || "Assertion failed"
          raise TransformError.new(msg) unless condition&.truthy?

          Types::DynValue.of_bool(true)
        }

        # Switch/cond handled via lazy evaluation in evaluate_verb
        registry["switch"] = ->(args, _ctx) { args.last || Types::DynValue.of_null }
        registry["cond"] = ->(args, _ctx) { args.last || Types::DynValue.of_null }

        # ── String verbs (missing) ──

        registry["trimLeft"] = ->(args, _ctx) {
          args[0]&.string? ? Types::DynValue.of_string(args[0].value.lstrip) : (args[0] || Types::DynValue.of_null)
        }
        registry["trimRight"] = ->(args, _ctx) {
          args[0]&.string? ? Types::DynValue.of_string(args[0].value.rstrip) : (args[0] || Types::DynValue.of_null)
        }

        registry["camelCase"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          words = s.scan(/[a-zA-Z0-9]+/)
          return Types::DynValue.of_string("") if words.empty?
          result = words.first.downcase + words[1..].map { |w| w.capitalize }.join
          Types::DynValue.of_string(result)
        }

        registry["snakeCase"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          # Insert underscore before uppercase runs followed by lowercase
          result = s.gsub(/([a-z\d])([A-Z])/, '\1_\2')
                     .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          words = result.scan(/[a-zA-Z0-9]+/)
          Types::DynValue.of_string(words.map(&:downcase).join("_"))
        }

        registry["kebabCase"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          result = s.gsub(/([a-z\d])([A-Z])/, '\1_\2')
                     .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          words = result.scan(/[a-zA-Z0-9]+/)
          Types::DynValue.of_string(words.map(&:downcase).join("-"))
        }

        registry["pascalCase"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          words = s.scan(/[a-zA-Z0-9]+/)
          Types::DynValue.of_string(words.map(&:capitalize).join)
        }

        registry["titleCase"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          Types::DynValue.of_string(s.gsub(/\b\w/) { |m| m.upcase })
        }

        registry["slugify"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          result = s.downcase
                    .gsub(/[^a-z0-9\s-]/, "")
                    .strip
                    .gsub(/[\s-]+/, "-")
          Types::DynValue.of_string(result)
        }

        registry["normalizeSpace"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          Types::DynValue.of_string(s.strip.gsub(/\s+/, " "))
        }

        registry["stripAccents"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          # Unicode decomposition then strip combining marks
          result = s.unicode_normalize(:nfd).gsub(/[\u0300-\u036f]/, "")
          Types::DynValue.of_string(result)
        }

        registry["clean"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          Types::DynValue.of_string(s.strip.gsub(/\s+/, " "))
        }

        registry["wordCount"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          words = s.strip.split(/\s+/)
          count = s.strip.empty? ? 0 : words.length
          Types::DynValue.of_integer(count)
        }

        registry["soundex"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          return Types::DynValue.of_string("") if s.empty?
          # Standard Soundex algorithm
          s = s.upcase.gsub(/[^A-Z]/, "")
          return Types::DynValue.of_string("") if s.empty?
          first = s[0]
          coded = s[1..].tr("AEIOUYHW", "00000000")
                       .tr("BFPV", "1111")
                       .tr("CGJKQSXZ", "22222222")
                       .tr("DT", "33")
                       .tr("L", "5")
                       .tr("MN", "66")
                       .tr("R", "6")
          # Map remaining letters
          map = { "B" => "1", "F" => "1", "P" => "1", "V" => "1",
                  "C" => "2", "G" => "2", "J" => "2", "K" => "2",
                  "Q" => "2", "S" => "2", "X" => "2", "Z" => "2",
                  "D" => "3", "T" => "3",
                  "L" => "4",
                  "M" => "5", "N" => "5",
                  "R" => "6" }
          codes = s.chars.map { |c| map[c] || "0" }
          # Remove adjacent duplicates
          deduped = [codes[0]]
          codes[1..].each { |c| deduped << c unless c == deduped.last }
          # Remove zeros, prepend first letter
          digits = deduped[1..].reject { |c| c == "0" }
          result = first + digits.join
          result = (result + "000")[0, 4]
          Types::DynValue.of_string(result)
        }

        registry["reverseString"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          Types::DynValue.of_string(s.reverse)
        }

        registry["truncate"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          max_len = args[1]&.to_number&.to_i || s.length
          if s.length > max_len
            Types::DynValue.of_string(s[0, max_len])
          else
            Types::DynValue.of_string(s)
          end
        }

        registry["split"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          delimiter = args[1]&.to_string || ","
          parts = s.split(delimiter, -1)
          # If a third argument (index) is provided, return that element
          if args[2] && !args[2].null?
            idx = args[2].to_number&.to_i || 0
            if idx >= 0 && idx < parts.length
              Types::DynValue.of_string(parts[idx])
            else
              Types::DynValue.of_null
            end
          else
            Types::DynValue.of_array(parts.map { |p| Types::DynValue.of_string(p) })
          end
        }

        registry["mask"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          pattern = args[1]&.to_string || "*"

          # Pattern-based masking: # A * are placeholders for input characters
          result = +""
          value_index = 0
          pattern.each_char do |ch|
            break if value_index >= s.length
            if ch == "#" || ch == "A" || ch == "*"
              result << s[value_index]
              value_index += 1
            else
              result << ch
            end
          end
          Types::DynValue.of_string(result)
        }

        registry["match"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          pattern = args[1]&.to_string || ""
          begin
            Types::DynValue.of_bool(!!(s =~ Regexp.new(pattern)))
          rescue RegexpError
            Types::DynValue.of_bool(false)
          end
        }
        registry["matches"] = registry["match"]

        registry["leftOf"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          delimiter = args[1]&.to_string || ""
          idx = s.index(delimiter)
          Types::DynValue.of_string(idx ? s[0, idx] : s)
        }

        registry["rightOf"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          delimiter = args[1]&.to_string || ""
          idx = s.index(delimiter)
          Types::DynValue.of_string(idx ? s[(idx + delimiter.length)..] : "")
        }

        registry["pad"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          len = args[1]&.to_number&.to_i || 0
          pad_char = args[2]&.to_string || " "
          pad_char = " " if pad_char.empty?
          Types::DynValue.of_string(s.ljust(len, pad_char))
        }

        registry["padLeft"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          len = args[1]&.to_number&.to_i || 0
          pad_char = args[2]&.to_string || " "
          pad_char = " " if pad_char.empty?
          Types::DynValue.of_string(s.rjust(len, pad_char))
        }

        registry["padRight"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          len = args[1]&.to_number&.to_i || 0
          pad_char = args[2]&.to_string || " "
          pad_char = " " if pad_char.empty?
          Types::DynValue.of_string(s.ljust(len, pad_char))
        }

        registry["repeat"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          count = args[1]&.to_number&.to_i || 0
          count = 0 if count < 0
          Types::DynValue.of_string(s * count)
        }

        registry["replaceRegex"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          pattern = args[1]&.to_string || ""
          replacement = args[2]&.to_string || ""
          begin
            Types::DynValue.of_string(s.gsub(Regexp.new(pattern), replacement))
          rescue RegexpError
            Types::DynValue.of_string(s)
          end
        }

        registry["center"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          len = args[1]&.to_number&.to_i || 0
          pad_char = args[2]&.to_string || " "
          pad_char = " " if pad_char.empty?
          Types::DynValue.of_string(s.center(len, pad_char))
        }

        registry["wrap"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          prefix = args[1]&.to_string || ""
          suffix = args[2]&.to_string || ""
          Types::DynValue.of_string(prefix + s + suffix)
        }

        registry["tokenize"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          delimiter = args[1]&.to_string || " "
          parts = s.split(delimiter, -1)
          Types::DynValue.of_array(parts.map { |p| Types::DynValue.of_string(p.strip) }.reject { |p| p.value.empty? })
        }

        registry["levenshtein"] = ->(args, _ctx) {
          a = args[0]&.to_string || ""
          b = args[1]&.to_string || ""
          m = a.length
          n = b.length
          return Types::DynValue.of_integer(n) if m == 0
          return Types::DynValue.of_integer(m) if n == 0

          d = Array.new(m + 1) { Array.new(n + 1, 0) }
          (0..m).each { |i| d[i][0] = i }
          (0..n).each { |j| d[0][j] = j }
          (1..m).each do |i|
            (1..n).each do |j|
              cost = a[i - 1] == b[j - 1] ? 0 : 1
              d[i][j] = [d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost].min
            end
          end
          Types::DynValue.of_integer(d[m][n])
        }

        registry["between"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          start_delim = args[1]&.to_string || ""
          end_delim = args[2]&.to_string || ""
          start_idx = s.index(start_delim)
          if start_idx
            after_start = start_idx + start_delim.length
            end_idx = s.index(end_delim, after_start)
            if end_idx
              Types::DynValue.of_string(s[after_start...end_idx])
            else
              Types::DynValue.of_string("")
            end
          else
            Types::DynValue.of_string("")
          end
        }

        # ── Encoding verbs ──

        registry["base64Encode"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          require "base64"
          Types::DynValue.of_string(Base64.strict_encode64(s))
        }

        registry["base64Decode"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          require "base64"
          begin
            Types::DynValue.of_string(Base64.strict_decode64(s))
          rescue ArgumentError
            Types::DynValue.of_null
          end
        }

        registry["hexEncode"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          Types::DynValue.of_string(s.bytes.map { |b| format("%02x", b) }.join)
        }

        registry["hexDecode"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          begin
            Types::DynValue.of_string([s].pack("H*"))
          rescue ArgumentError
            Types::DynValue.of_null
          end
        }

        registry["urlEncode"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          require "uri"
          Types::DynValue.of_string(URI.encode_www_form_component(s).gsub("+", "%20"))
        }

        registry["urlDecode"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          require "uri"
          begin
            Types::DynValue.of_string(URI.decode_www_form_component(s))
          rescue ArgumentError
            Types::DynValue.of_string(s)
          end
        }

        registry["jsonEncode"] = ->(args, _ctx) {
          v = args[0]
          require "json"
          Types::DynValue.of_string(v.nil? || v.null? ? "null" : JSON.generate(v.to_ruby))
        }

        registry["jsonDecode"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          require "json"
          begin
            parsed = JSON.parse(s)
            Types::DynValue.from_ruby(parsed)
          rescue JSON::ParserError
            Types::DynValue.of_null
          end
        }

        registry["sha256"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          require "digest"
          Types::DynValue.of_string(Digest::SHA256.hexdigest(s))
        }

        registry["sha1"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          require "digest"
          Types::DynValue.of_string(Digest::SHA1.hexdigest(s))
        }

        registry["sha512"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          require "digest"
          Types::DynValue.of_string(Digest::SHA512.hexdigest(s))
        }

        registry["md5"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          require "digest"
          Types::DynValue.of_string(Digest::MD5.hexdigest(s))
        }

        registry["crc32"] = ->(args, _ctx) {
          s = args[0]&.to_string || ""
          require "zlib"
          Types::DynValue.of_integer(Zlib.crc32(s))
        }

        # ── Logic verbs ──

        registry["ifElse"] = ->(args, _ctx) {
          condition = args[0]
          true_val = args[1] || Types::DynValue.of_null
          false_val = args[2] || Types::DynValue.of_null
          condition&.truthy? ? true_val : false_val
        }

        registry["xor"] = ->(args, _ctx) {
          a = args[0]&.truthy? || false
          b = args[1]&.truthy? || false
          Types::DynValue.of_bool(a ^ b)
        }

        # ── Coercion verbs ──

        registry["tryCoerce"] = ->(args, _ctx) {
          v = args[0]
          return Types::DynValue.of_null if v.nil? || v.null?
          return v unless v.string?
          s = v.value.strip

          # Try boolean
          return Types::DynValue.of_bool(true) if s == "true"
          return Types::DynValue.of_bool(false) if s == "false"

          # Try integer
          if s =~ /\A-?\d+\z/
            return Types::DynValue.of_integer(s.to_i)
          end

          # Try float
          if s =~ /\A-?\d+\.\d+\z/
            return Types::DynValue.of_float(s.to_f)
          end

          # Try date (YYYY-MM-DD)
          if s =~ /\A\d{4}-\d{2}-\d{2}\z/
            begin
              Date.parse(s)
              return Types::DynValue.of_date(s)
            rescue
            end
          end

          # Try timestamp
          if s =~ /\A\d{4}-\d{2}-\d{2}T/
            begin
              Time.parse(s)
              return Types::DynValue.of_timestamp(s)
            rescue
            end
          end

          v
        }

        registry["coerceDate"] = ->(args, _ctx) {
          v = args[0]
          return Types::DynValue.of_null if v.nil? || v.null?
          s = v.to_string.strip
          begin
            d = Date.parse(s)
            Types::DynValue.of_date(d.strftime("%Y-%m-%d"))
          rescue ArgumentError, TypeError
            Types::DynValue.of_null
          end
        }

        registry["coerceTimestamp"] = ->(args, _ctx) {
          v = args[0]
          return Types::DynValue.of_null if v.nil? || v.null?
          s = v.to_string.strip
          begin
            t = Time.parse(s).utc
            Types::DynValue.of_timestamp(t.strftime("%Y-%m-%dT%H:%M:%S.%3NZ"))
          rescue ArgumentError, TypeError
            Types::DynValue.of_null
          end
        }

        # ── Type conversion verbs ──

        registry["toArray"] = ->(args, _ctx) {
          v = args[0]
          if v.nil? || v.null?
            Types::DynValue.of_array([])
          elsif v.array?
            v
          else
            Types::DynValue.of_array([v])
          end
        }

        registry["toObject"] = ->(args, _ctx) {
          v = args[0]
          if v.nil? || v.null?
            Types::DynValue.of_object({})
          elsif v.object?
            v
          elsif v.array?
            obj = {}
            v.value.each_with_index { |item, i| obj[i.to_s] = item }
            Types::DynValue.of_object(obj)
          else
            Types::DynValue.of_object({ "value" => v })
          end
        }

        # ── Generation verbs ──

        registry["uuid"] = ->(args, _ctx) {
          require "securerandom"
          # Check if last arg is a seed string
          seed_arg = args.length >= 1 && args[-1]&.type == :string ? args[-1].to_string : nil
          # Determine prefix: first arg if there are 2+ args
          prefix = if args.length >= 2
                     args[0]&.to_string || ""
                   elsif args.length == 1 && seed_arg
                     "" # single string arg is seed, no prefix
                   else
                     args[0]&.to_string || ""
                   end

          if seed_arg
            # Deterministic UUID from seed — matches TypeScript's exact algorithm
            hash1 = 5381
            hash2 = 52711
            seed_arg.each_byte do |c|
              hash1 = (((hash1 << 5) + hash1) ^ c) & 0xFFFFFFFF
              hash2 = (((hash2 << 5) + hash2) ^ c) & 0xFFFFFFFF
            end

            bytes = Array.new(16, 0)
            8.times do |i|
              bytes[i] = js_signed_rshift(hash1, i * 4)
              bytes[i + 8] = js_signed_rshift(hash2, i * 4)
            end

            # Version 5 and variant
            bytes[6] = (bytes[6] & 0x0F) | 0x50
            bytes[8] = (bytes[8] & 0x3F) | 0x80

            hex = bytes.map { |b| b.to_s(16).rjust(2, '0') }.join
            id = "#{hex[0,8]}-#{hex[8,4]}-#{hex[12,4]}-#{hex[16,4]}-#{hex[20,12]}"
            Types::DynValue.of_string(prefix.empty? ? id : prefix + id)
          else
            id = SecureRandom.uuid
            Types::DynValue.of_string(prefix.empty? ? id : prefix + id)
          end
        }

        registry["nanoid"] = ->(args, _ctx) {
          require "securerandom"
          length = args[0]&.to_number&.to_i || 21
          length = 1 if length < 1
          alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
          id = (0...length).map { alphabet[SecureRandom.random_number(alphabet.length)] }.join
          Types::DynValue.of_string(id)
        }

        registry["formatPhone"] = ->(args, _ctx) {
          return Types::DynValue.of_null if args.length < 2
          raw = args[0]&.to_string
          return Types::DynValue.of_null if raw.nil?
          country = args[1]&.to_string || ""
          digits = raw.gsub(/\D/, "")
          formatted = case country
          when "US", "CA"
            if digits.length == 10
              "(#{digits[0..2]}) #{digits[3..5]}-#{digits[6..9]}"
            elsif digits.length == 11 && digits.start_with?("1")
              "+1 (#{digits[1..3]}) #{digits[4..6]}-#{digits[7..10]}"
            end
          when "GB"
            if digits.length == 11 && digits.start_with?("0")
              "+44 #{digits[1..4]} #{digits[5..10]}"
            elsif digits.length == 10
              "+44 #{digits[0..3]} #{digits[4..9]}"
            end
          when "DE"
            if digits.length == 11 && digits.start_with?("0")
              "+49 #{digits[1..4]} #{digits[5..10]}"
            elsif digits.length == 10
              "+49 #{digits[0..3]} #{digits[4..9]}"
            end
          when "FR"
            if digits.length == 10 && digits.start_with?("0")
              "+33 #{digits[1]} #{digits[2..3]} #{digits[4..5]} #{digits[6..7]} #{digits[8..9]}"
            elsif digits.length == 9
              "+33 #{digits[0]} #{digits[1..2]} #{digits[3..4]} #{digits[5..6]} #{digits[7..8]}"
            end
          when "AU"
            if digits.length == 10 && digits.start_with?("0")
              "+61 #{digits[1]} #{digits[2..5]} #{digits[6..9]}"
            elsif digits.length == 9
              "+61 #{digits[0]} #{digits[1..4]} #{digits[5..8]}"
            end
          when "JP"
            if digits.length == 11 && digits.start_with?("0")
              "+81 #{digits[1..2]}-#{digits[3..6]}-#{digits[7..10]}"
            elsif digits.length == 10
              "+81 #{digits[0..1]}-#{digits[2..5]}-#{digits[6..9]}"
            end
          end
          Types::DynValue.of_string(formatted || raw)
        }
      end
    end
  end
end
