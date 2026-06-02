# frozen_string_literal: true

module Odin
  module Transform
    class TransformEngine
      # Verb registry — populated in Phase 9-10. For now, core verbs only.
      CORE_VERBS = {}.freeze

      class TransformError < StandardError
        attr_reader :code
        attr_accessor :segment, :field

        def initialize(message, code: "E001")
          @code = code
          super(message)
        end
      end

      # A warning carrying a stable transform error code. Collected alongside
      # string warnings; consumers that inspect codes read `.code`.
      class TransformWarning
        attr_reader :code, :message
        attr_accessor :segment, :field

        def initialize(message, code:)
          @message = message
          @code = code
        end

        def to_s
          @message
        end
      end

      # Raised during expression evaluation to carry a coded TransformError up to
      # the mapping handler, which preserves the code under fail/warn.
      class CodedTransformError < StandardError
        attr_reader :transform_error

        def initialize(transform_error)
          @transform_error = transform_error
          super(transform_error.message)
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
        T012_DANGLING_BRANCH         = "T012"
        T014_NESTED_INTERPOLATION    = "T014"
      end

      # Create a T014 Nested Interpolation error.
      def self.nested_interpolation_error(expr, segment = nil)
        err = TransformError.new(
          "Nested interpolation is not allowed: ${#{expr}}",
          code: ErrorCodes::T014_NESTED_INTERPOLATION
        )
        err.segment = segment if segment
        err
      end

      # Create a T012 Dangling Branch error (elif/else with no preceding if).
      def self.dangling_branch_error(directive)
        TransformError.new(
          "'#{directive}' segment has no preceding 'if'",
          code: ErrorCodes::T012_DANGLING_BRANCH
        )
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

      # Create a T001 Unknown Verb error.
      def self.unknown_verb_error(verb_name)
        TransformError.new("Unknown verb: #{verb_name}", code: ErrorCodes::T001_UNKNOWN_VERB)
      end

      # Create a T003 Lookup Table Not Found error.
      def self.lookup_table_not_found_error(table_name)
        TransformError.new("Lookup table not found: #{table_name}", code: ErrorCodes::T003_LOOKUP_TABLE_NOT_FOUND)
      end

      # Create a T004 Lookup Key Not Found error.
      def self.lookup_key_not_found_error(table_name, key)
        TransformError.new("Lookup key '#{key}' not found in table '#{table_name}'", code: ErrorCodes::T004_LOOKUP_KEY_NOT_FOUND)
      end

      # Create a T005 Source Path Not Found error.
      def self.source_path_not_found_error(path)
        TransformError.new("Source path not found: #{path}", code: ErrorCodes::T005_SOURCE_PATH_NOT_FOUND)
      end

      # Create a T006 Invalid Output Format error.
      def self.invalid_output_format_error(format)
        TransformError.new("Invalid or unsupported output format: #{format}", code: ErrorCodes::T006_INVALID_OUTPUT_FORMAT)
      end

      # Create a T008 Accumulator Overflow error.
      def self.accumulator_overflow_error(name, value)
        TransformError.new("Accumulator '#{name}' overflow with value #{value}", code: ErrorCodes::T008_ACCUMULATOR_OVERFLOW)
      end

      # Create a T009 Loop Source Not Array error.
      def self.loop_source_not_array_error(path)
        TransformError.new("Loop source path '#{path}' does not resolve to an array", code: ErrorCodes::T009_LOOP_SOURCE_NOT_ARRAY)
      end

      # The required-source-missing code: a present-but-null :required field.
      SOURCE_MISSING = "SOURCE_MISSING"

      attr_reader :verb_registry

      def initialize
        @verb_registry = build_verb_registry
      end

      def execute(transform_def, source_data, import_resolver: nil)
        # Merge imported tables, constants, accumulators, and segments.
        if import_resolver && transform_def.imports && !transform_def.imports.empty?
          resolve_imports(transform_def, import_resolver)
        end

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
          process_segment_list(transform_def.segments, source, context, output)
        else
          # Multi-pass: explicit passes first, then pass-0 (implicit)
          all_passes = passes.include?(0) ? passes : passes + [0]
          first_pass = true
          all_passes.each do |pass_num|
            unless first_pass
              reset_non_persist_accumulators(context, transform_def.accumulators)
            end
            first_pass = false

            pass_segments = transform_def.segments.select { |s| (s.pass || 0) == pass_num }
            process_segment_list(pass_segments, source, context, output)
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

        TransformResult.new(output: plain_output, formatted: formatted, output_dv: output_dv, errors: context.errors, warnings: context.warnings)
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

        TransformResult.new(output: plain_output, formatted: formatted, output_dv: output_dv, errors: context.errors, warnings: context.warnings)
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
        raise CodedTransformError.new(self.class.unknown_verb_error(name)) unless verb_fn

        verb_fn.call(args, context)
      end

      # Verbs whose leading arguments must be numeric; checked under strictTypes.
      NUMERIC_ARG_VERBS = %w[
        sqrt abs round floor ceil negate sign trunc ln log log10 log2 exp pow
        add subtract multiply divide mod between formatNumber formatInteger
        formatCurrency toRadians toDegrees
      ].freeze

      NUMERIC_DYN_TYPES = %i[integer float float_raw currency currency_raw percent null].freeze

      # T002: under strictTypes, a numeric verb argument that is not a numeric
      # (or null) value fails the field.
      def check_verb_arg_types!(verb_name, args)
        return unless NUMERIC_ARG_VERBS.include?(verb_name)

        args.each_with_index do |arg, i|
          next if arg.nil?
          next if NUMERIC_DYN_TYPES.include?(arg.type)

          err = TransformError.new(
            "Verb '#{verb_name}' arg #{i + 1}: expected number, got #{arg.type}",
            code: ErrorCodes::T002_INVALID_VERB_ARGS
          )
          raise CodedTransformError.new(err)
        end
      end

      # ── Expression Evaluation ──

      def evaluate(expr, context)
        case expr
        when LiteralExpr
          val = expr.value
          if val.is_a?(Types::DynValue) && val.string? && val.value.include?("${")
            return interpolate_string(val.value, context)
          end
          val
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

      # Merge imported lookup tables, constants, accumulators, and named segments
      # into this transform. Local declarations win over imported ones; imported
      # segments are appended so their mappings remain referenceable.
      def resolve_imports(transform_def, resolver)
        seen = {}
        transform_def.imports.each do |path|
          next if seen[path]

          seen[path] = true
          text = resolver.call(path)
          next if text.nil?

          imported = TransformParser.new.parse(text)

          imported.tables.each do |name, table|
            transform_def.tables[name] = table unless transform_def.tables.key?(name)
          end
          imported.constants.each do |name, value|
            transform_def.constants[name] = value unless transform_def.constants.key?(name)
          end
          imported.accumulators.each do |name, acc_def|
            transform_def.accumulators[name] = acc_def unless transform_def.accumulators.key?(name)
          end

          existing_names = transform_def.segments.map(&:name)
          imported.segments.each do |seg|
            next if seg.name.to_s.empty? || existing_names.include?(seg.name)

            transform_def.segments << seg
          end
        end
      end

      # Signed 32-bit right shift (>>) with sign-extension from bit 31.
      # Ruby integers are arbitrary precision and always do logical (unsigned) shift.
      def js_signed_rshift(val, shift)
        val = val & 0xFFFFFFFF
        val -= 0x100000000 if val >= 0x80000000
        (val >> shift) & 0xFF
      end

      # Extract a [key, value] pair from a %toObject entry in either
      # pair-array ([k, v]) or {key, value} / {k, v} object form.
      def to_object_pair(item)
        return nil unless item.is_a?(Types::DynValue)

        if item.array?
          items = item.value || []
          return nil if items.length < 2
          return [items[0].to_string, items[1]]
        end

        if item.object?
          entries = item.value || {}
          if entries.key?("key") && entries.key?("value")
            return [entries["key"].to_string, entries["value"]]
          end
          if entries.key?("k") && entries.key?("v")
            return [entries["k"].to_string, entries["v"]]
          end
        end

        nil
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
          Types::DynValue.of_currency(val.value, val.respond_to?(:decimal_places) ? val.decimal_places : 2,
                                      val.respond_to?(:currency_code) ? val.currency_code : nil)
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
        ov = transform_def.header.target_options["onValidation"]
        context.on_validation = ov if ov && !ov.empty?
        om = transform_def.header.target_options["onMissing"]
        context.on_missing = om if om && !om.empty?
        oe = transform_def.header.target_options["onError"]
        context.on_error = oe if oe && !oe.empty?
        context.strict_types = transform_def.header.strict_types

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

      # Report a missing lookup key (T004) honoring the on_missing policy.
      # Defaults to silent null; raises only when on_missing is fail/warn.
      def report_lookup_miss(context, table_name, key)
        case context.on_missing
        when "fail"
          context.errors << self.class.lookup_key_not_found_error(table_name, key)
        when "warn"
          context.warnings << TransformWarning.new(
            "Lookup key '#{key}' not found in table '#{table_name}'",
            code: ErrorCodes::T004_LOOKUP_KEY_NOT_FOUND
          )
        end
      end

      # Report a missing lookup table (T003) honoring the on_missing policy.
      # Distinct from a missing key (T004): the referenced table was never declared.
      def report_table_not_found(context, table_name)
        case context.on_missing
        when "fail"
          context.errors << self.class.lookup_table_not_found_error(table_name)
        when "warn"
          context.warnings << TransformWarning.new(
            "Lookup table not found: #{table_name}",
            code: ErrorCodes::T003_LOOKUP_TABLE_NOT_FOUND
          )
        end
      end

      def reset_non_persist_accumulators(context, accumulator_defs)
        accumulator_defs.each do |key, acc_def|
          next if acc_def.persist

          context.accumulators[key] = acc_def.initial_value
        end
      end

      # ── Segment Processing ──

      # Process a list of segments, honoring if/elif/else conditional chains.
      # A chain is a run of consecutive segments: one `if`, then any `elif`, then
      # an optional `else`. Only the first branch whose condition holds is emitted.
      def process_segment_list(segments, source, context, output)
        # :none = no active chain; :pending = chain open, none taken; :taken = a branch taken
        branch = :none

        segments.each do |segment|
          if segment.if_condition
            taken = evaluate_condition(segment.if_condition, source, context)
            branch = taken ? :taken : :pending
            process_segment(segment, source, context, output) if taken
          elsif segment.elif_condition
            if branch == :none
              context.errors << self.class.dangling_branch_error("elif")
              next
            end
            next if branch == :taken

            taken = evaluate_condition(segment.elif_condition, source, context)
            branch = taken ? :taken : :pending
            process_segment(segment, source, context, output) if taken
          elsif segment.is_else
            if branch == :none
              context.errors << self.class.dangling_branch_error("else")
              next
            end
            process_segment(segment, source, context, output) if branch == :pending
            branch = :none
          else
            branch = :none
            process_segment(segment, source, context, output)
          end
        end
      end

      # A segment whose name begins with "_" is a computation-only sink:
      # it runs for side effects (accumulators, verbs) and is never emitted.
      def sink_segment?(segment)
        name = segment.name.to_s
        return false if name.empty?

        last = name.split(".").last || name
        last.start_with?("_")
      end

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

        # Literal block: emit interpolated text lines instead of field mappings.
        if segment.is_literal
          process_literal_segment(segment, source, context, output)
          return
        end

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

        # Sink section: side effects only, nothing emitted.
        return if sink_segment?(segment)

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

      # Render a :literal segment to interpolated text lines. Under a :loop the
      # block renders once per item; lines are emitted verbatim by the formatter.
      def process_literal_segment(segment, source, context, output)
        template = segment.literal_body.to_s
        lines = []
        render = lambda do |ctx|
          render_literal(template, ctx, segment.path).split("\n", -1).each { |l| lines << l }
        end

        if (segment.loops && !segment.loops.empty?) || segment.each_source
          loops = segment_loops(segment)
          dummy = []
          begin
            iterate_loops(loops, 0, segment, source, context, dummy, on_item: render)
          rescue CodedTransformError => e
            coded = e.transform_error
            coded.segment = segment.name
            case context.on_error
            when "warn"
              context.warnings << TransformWarning.new(coded.message, code: coded.code).tap { |w| w.segment = segment.name }
            when "skip"
              # drop silently
            else
              context.errors << coded
            end
          end
        else
          render.call(context)
        end

        set_output_path(output, segment.name, { "__literalLines" => lines })
      end

      def render_literal(template, context, segment_path)
        interpolate_literal_block(template, context)
      rescue TransformError => e
        if e.code == ErrorCodes::T014_NESTED_INTERPOLATION
          e.segment ||= segment_path
          context.errors << e
          ""
        else
          raise
        end
      end

      # Interpolate ${...} in a literal block body. Escapes: \${ -> ${, \$ -> $,
      # \\ -> \. A ${...} whose expression contains another ${ is a T014 error.
      def interpolate_literal_block(template, context)
        out = +""
        i = 0
        len = template.length
        while i < len
          ch = template[i]
          if ch == "\\"
            nxt = template[i + 1]
            if nxt == "$" && template[i + 2] == "{"
              out << "${"; i += 3; next
            elsif nxt == "\\"
              out << "\\"; i += 2; next
            elsif nxt == "$"
              out << "$"; i += 2; next
            else
              out << "\\"; i += 1; next
            end
          end

          if ch == "$" && template[i + 1] == "{"
            close = template.index("}", i + 2)
            if close.nil?
              out << template[i..]
              break
            end
            expr = template[(i + 2)...close]
            raise TransformEngine.nested_interpolation_error(expr) if expr.include?("${")
            out << evaluate_interpolation_expr(expr.strip, context)
            i = close + 1
            next
          end

          out << ch
          i += 1
        end
        out
      end

      def evaluate_interpolation_expr(expr, context)
        if expr.start_with?("%")
          parser = TransformParser.new
          parsed, = parser.send(:parse_expr_from_tokens, parser.send(:tokenize_expression, expr))
          parsed ? dynvalue_string(evaluate(parsed, context)) : "${#{expr}}"
        elsif expr.start_with?("@")
          dynvalue_string(resolve_path(expr[1..], context))
        else
          "${#{expr}}"
        end
      end

      def process_loop_segment(segment, source, context, output, modifier_prefix: "")
        loops = segment_loops(segment)
        results = []
        begin
          iterate_loops(loops, 0, segment, source, context, results, modifier_prefix: modifier_prefix)
        rescue CodedTransformError => e
          coded = e.transform_error
          coded.segment = segment.name
          case context.on_error
          when "warn"
            context.warnings << TransformWarning.new(coded.message, code: coded.code).tap { |w| w.segment = segment.name }
          when "skip"
            # drop silently
          else
            context.errors << coded
          end
          return
        end

        return if sink_segment?(segment)

        seg_name = segment.name
        # Always set the array in output, even if empty
        set_output_path(output, seg_name, results)
      end

      # Normalize a segment's loop directives to a list of {source:, alias:} specs.
      def segment_loops(segment)
        if segment.loops && !segment.loops.empty?
          segment.loops
        else
          [{ source: segment.each_source, alias: nil }]
        end
      end

      # Drive one or more :loop directives as a nested cross-product. Each level
      # binds its alias and current item, then recurses; the innermost level emits
      # one element per item. A non-array source at any level yields no rows.
      def iterate_loops(loops, depth, segment, source, context, results, modifier_prefix: "", on_item: nil)
        loop_ctx = context.dup_for_loop
        raise TransformError.new("Maximum loop nesting depth exceeded") if loop_ctx.loop_depth > VerbContext::MAX_LOOP_DEPTH

        spec = loops[depth]
        is_outermost = depth.zero?
        is_innermost = depth == loops.length - 1

        items = resolve_loop_items(spec[:source], is_outermost, source, context)
        unless items.is_a?(Types::DynValue) && items.array?
          # A present non-array scalar is a T009 error; an absent/null source
          # yields zero rows silently.
          if items.is_a?(Types::DynValue) && !items.null?
            raise CodedTransformError.new(self.class.loop_source_not_array_error(spec[:source].to_s))
          end
          return
        end

        has_underscore_only = segment.field_mappings.all? { |m| m.target_field == "_" } &&
                              segment.field_mappings.any? && segment.children.empty?

        items.value.each_with_index do |item, idx|
          item_ctx = loop_ctx.dup_for_loop
          item_ctx.loop_depth = loop_ctx.loop_depth
          item_ctx.current_item = item
          item_ctx.loop_index = idx
          item_ctx.loop_length = items.value.length
          item_ctx.loop_vars["_item"] = item
          item_ctx.loop_vars["_index"] = Types::DynValue.of_integer(idx)
          item_ctx.loop_vars["_length"] = Types::DynValue.of_integer(items.value.length)
          item_ctx.aliases[spec[:alias]] = item if spec[:alias]

          # :counter binds the innermost index and resets per outer item.
          if segment.counter_name && is_innermost
            item_ctx.loop_vars[segment.counter_name] = Types::DynValue.of_integer(idx)
          end

          unless is_innermost
            iterate_loops(loops, depth + 1, segment, item, item_ctx, results,
                          modifier_prefix: modifier_prefix, on_item: on_item)
            next
          end

          if on_item
            on_item.call(item_ctx)
            next
          end

          if has_underscore_only
            val = Types::DynValue.of_null
            segment.field_mappings.each do |mapping|
              val = evaluate(mapping.expression, item_ctx)
              val = apply_extraction_directives(val, mapping.directives)
              mapping.directives.each do |directive|
                next if %w[pos len field].include?(directive.name)
                val = apply_directive(val, directive, item, item_ctx)
              end
            end
            results << val
          else
            item_result = {}
            segment.field_mappings.each do |mapping|
              process_mapping(mapping, item, item_ctx, item_result, modifier_prefix: modifier_prefix)
            end
            segment.children.each do |child|
              process_segment(child, item, item_ctx, item_result, modifier_prefix: modifier_prefix)
            end
            results << item_result if item_result.any?
          end
        end
      end

      # Resolve the array for a loop level. Outermost resolves against the source
      # root; inner levels resolve relative (.field) or aliased paths against the
      # current item.
      def resolve_loop_items(path, is_outermost, source, context)
        p = path.to_s
        p = p[1..] if p.start_with?("@")

        items = if p.start_with?(".")
                  base = context.in_loop? && context.current_item ? context.current_item : source
                  resolve_dotted_path(base, p[1..])
                elsif is_outermost
                  resolve_path_from_string(p, source, context)
                else
                  first = p.split(".").first
                  if context.aliases.key?(first)
                    aliased = context.aliases[first]
                    rest = p.include?(".") ? p[(first.length + 1)..] : ""
                    rest.empty? ? aliased : resolve_dotted_path(aliased, rest)
                  else
                    base = context.in_loop? && context.current_item ? context.current_item : source
                    resolve_dotted_path(base, p)
                  end
                end

        items
      end

      # Precompiled :validate / :enum / :range data for a mapping.
      CompiledValidation = Struct.new(
        :pattern, :regex, :regex_error,
        :enum_allowed, :enum_label,
        :range_str, :range_min, :range_max,
        keyword_init: true
      )

      # Per-mapping directive references and flags, derived once from the mapping's
      # data-independent directives/modifiers and reused across all executions.
      MappingMods = Struct.new(
        :if_dir, :unless_dir, :object_dir,
        :has_default, :has_raw, :has_array,
        :extraction_dir_names, :required,
        :validate_dir, :enum_dir, :range_dir,
        :validation, :validation_active,
        keyword_init: true
      )

      # Build (or reuse) the precomputed modifier data for a mapping, memoized on
      # the mapping object so the directive list is scanned only once.
      def mapping_mods(mapping)
        cached = mapping.instance_variable_get(:@__mods)
        return cached if cached

        directives = mapping.directives
        validate_dir = directives.find { |d| d.name == "validate" }
        enum_dir = directives.find { |d| d.name == "enum" }
        range_dir = directives.find { |d| d.name == "range" }

        mods = MappingMods.new(
          if_dir: directives.find { |d| d.name == "if" },
          unless_dir: directives.find { |d| d.name == "unless" },
          object_dir: directives.find { |d| d.name == "object" },
          has_default: directives.any? { |d| d.name == "default" },
          has_raw: directives.any? { |d| d.name == "raw" },
          has_array: directives.any? { |d| d.name == "array" },
          extraction_dir_names: directives.map(&:name) & %w[pos len field trim],
          required: mapping.modifiers.include?(FieldModifier::REQUIRED),
          validate_dir: validate_dir,
          enum_dir: enum_dir,
          range_dir: range_dir,
          validation: compile_validation(validate_dir, enum_dir, range_dir),
          validation_active: !validate_dir.nil? || !enum_dir.nil? || !range_dir.nil?
        )
        mapping.instance_variable_set(:@__mods, mods)
        mods
      end

      # Precompile the regex / enum set / range bounds for validation directives.
      def compile_validation(validate_dir, enum_dir, range_dir)
        cv = CompiledValidation.new

        if validate_dir && !validate_dir.value.nil?
          cv.pattern = validate_dir.value.to_s
          begin
            cv.regex = Regexp.new(cv.pattern)
          rescue RegexpError
            cv.regex_error = true
          end
        end

        if enum_dir && !enum_dir.value.nil?
          allowed = enum_dir.value.to_s.split(",").map { |v| v.strip.gsub(/\A["']|["']\z/, "") }
          cv.enum_allowed = allowed
          cv.enum_label = allowed.join(", ")
        end

        if range_dir && !range_dir.value.nil?
          cv.range_str = range_dir.value.to_s
          parts = cv.range_str.split("..")
          cv.range_min = (Float(parts[0]) rescue nil)
          cv.range_max = (Float(parts[1]) rescue nil)
        end

        cv
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
          mods = mapping_mods(mapping)

          # Field-level :if / :unless gate the assignment on a comparison expression.
          if_dir = mods.if_dir
          if if_dir
            return unless evaluate_condition(if_dir.value.to_s, source, context)
          end
          unless_dir = mods.unless_dir
          if unless_dir
            return if evaluate_condition(unless_dir.value.to_s, source, context)
          end

          # A :default modifier handles a missing lookup; suppress errors raised during evaluation.
          has_default = mods.has_default
          errors_before = has_default ? context.errors.length : 0

          # :object builds a nested object from an inline {key = @path, …} spec.
          object_dir = mods.object_dir
          if object_dir
            val = build_inline_object(object_dir.value.to_s, context)
          else
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
              # to the first CopyExpr argument before calling the verb
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
              next if %w[pos len field trim if unless object raw array cdata validate enum range].include?(directive.name)
              val = apply_directive(val, directive, source, context)
            end
          end

          # If a :default rescued a null result, drop errors raised during evaluation.
          if has_default && context.errors.length > errors_before
            context.errors.slice!(errors_before..)
          end

          # Validation modifiers: :validate / :enum / :range (honors onValidation policy).
          return unless validate_field_value(val, mapping, context)

          # :raw emits inline JSON structurally instead of an escaped string.
          if mods.has_raw
            val = parse_raw_json_value(val)
          end

          # :array wraps the value in a single-element array.
          if mods.has_array
            val = Types::DynValue.of_array([val.is_a?(Types::DynValue) ? val : Types::DynValue.from_ruby(val)])
          end

          # Missing source path: a :required field always fails (T005); an ordinary
          # field honors the onMissing policy (fail -> T005, warn -> warning,
          # skip/default -> keep null). A path that is merely null is not "missing".
          required = mods.required
          val_null = val.is_a?(Types::DynValue) && val.null?
          if val_null && copy_source_absent?(mapping, source, context)
            raw_path = mapping.expression.is_a?(CopyExpr) ? mapping.expression.source_path : target
            path = raw_path.to_s.start_with?(".") ? raw_path[1..] : raw_path.to_s
            if required
              context.errors << self.class.source_path_not_found_error(path)
              return
            end
            case context.on_missing
            when "fail"
              context.errors << self.class.source_path_not_found_error(path)
              return
            when "warn"
              context.warnings << TransformWarning.new(
                "Source path not found: #{path}", code: ErrorCodes::T005_SOURCE_PATH_NOT_FOUND
              )
            end
          elsif required && val_null
            # Required field present but explicitly null.
            context.errors << TransformError.new(
              "Required field '#{target}' is missing or null", code: SOURCE_MISSING
            )
            return
          end

          # Track field modifiers with full path
          unless mapping.modifiers.empty?
            full_path = modifier_prefix.empty? ? target : "#{modifier_prefix}.#{target}"
            context.field_modifiers[full_path] = mapping.modifiers
          end

          # Store DynValue directly to preserve type information (date, timestamp, etc.)
          dv_val = val.is_a?(Types::DynValue) ? val : Types::DynValue.from_ruby(val)
          set_path(output, target, dv_val)
        rescue CodedTransformError => e
          # Coded errors carry a stable T-code; preserve it under fail/warn.
          coded = e.transform_error
          coded.field = target
          case context.on_error
          when "warn"
            context.warnings << TransformWarning.new(coded.message, code: coded.code).tap { |w| w.field = target }
          when "skip"
            # drop silently
          else
            context.errors << coded
          end
        rescue StandardError => e
          case context.on_error
          when "warn"
            context.warnings << e.message
          when "skip"
            # drop silently
          else
            context.errors << TransformError.new(e.message)
          end
        end
      end

      # Whether a mapping copies a source path that is absent (undefined) — distinct
      # from a path present with a null value. Only plain copy expressions qualify;
      # verbs, literals, objects, and special paths are never "missing source".
      def copy_source_absent?(mapping, source, context)
        expr = mapping.expression
        return false unless expr.is_a?(CopyExpr)
        # A :default / :object modifier supplies its own fallback.
        return false if mapping.directives.any? { |d| %w[default object].include?(d.name) }

        path = expr.source_path.to_s
        return false if path.empty? || path.start_with?("$") || path == "_index"
        return false if context.loop_vars.key?(path)

        base = source.is_a?(Types::DynValue) ? source : context.source
        if path.start_with?(".")
          base = context.current_item if context.in_loop? && context.current_item
          target_path = path[1..]
        else
          first = path.split(".").first
          if context.aliases.key?(first)
            base = context.aliases[first]
            target_path = path.include?(".") ? path[(first.length + 1)..] : ""
          else
            target_path = path
          end
        end

        resolved = target_path.to_s.empty? ? base : resolve_dotted_path(base, target_path)
        # resolve_dotted_path collapses both absent and explicit-null to of_null; an
        # absent path is one whose leaf key is not explicitly present.
        return false unless resolved.is_a?(Types::DynValue) && resolved.null?

        !path_present?(base, target_path)
      end

      # True when target_path resolves to an explicitly-present key (even if its
      # value is null); false when any segment along the path is missing.
      def path_present?(base, target_path)
        return true if target_path.to_s.empty?
        return false unless base.is_a?(Types::DynValue)

        segments = parse_path_segments(target_path)
        current = base
        segments.each do |seg|
          return false unless current.is_a?(Types::DynValue)

          if seg.is_a?(Integer)
            return false unless current.array? && seg < current.value.length

            current = current.get_index(seg)
          else
            return false unless current.object? && current.value.key?(seg)

            current = current.get(seg)
          end
        end
        true
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
          acc = context.get_accumulator(key)
          return acc unless acc.null?
          # Loop counters declared via :counter are also readable through the accumulator reference.
          return context.loop_vars[key] if context.loop_vars.key?(key)
          return acc
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

        # A leading :loop :as alias resolves against its bound item.
        aliased = resolve_via_alias(path, context)
        return aliased unless aliased.nil?

        # Determine source to navigate
        current_source = if context.in_loop? && context.current_item
                           context.current_item
                         else
                           context.source
                         end

        # Navigate the path
        resolve_dotted_path(current_source, path)
      end

      # When the first dotted segment names a :loop alias, resolve the remainder
      # against the bound item. Returns nil when the path is not alias-led.
      def resolve_via_alias(path, context)
        return nil unless context.respond_to?(:aliases) && context.aliases && !context.aliases.empty?

        first = path.split(".").first
        return nil unless context.aliases.key?(first)

        aliased = context.aliases[first]
        rest = path.include?(".") ? path[(first.length + 1)..] : ""
        rest.empty? ? aliased : resolve_dotted_path(aliased, rest)
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

          # A leading :loop :as alias resolves against its bound item.
          aliased = resolve_via_alias(sub_path, context)
          return aliased unless aliased.nil?

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

        # T002: enforce verb argument types under strictTypes.
        if context.strict_types
          check_verb_arg_types!(verb_name, evaluated_args)
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

        sum = current.to_number + increment.to_number

        # T008: the result exceeds representable numeric capacity (non-finite, or
        # an integer accumulator beyond the safe-integer magnitude where precision
        # is lost). Retain the last valid value.
        if accumulator_overflow?(current, sum)
          context.errors << self.class.accumulator_overflow_error(name, sum)
          return current
        end

        # Preserve integer type if both are integers
        new_val = if current.integer? && increment.integer?
                    Types::DynValue.of_integer(sum)
                  else
                    Types::DynValue.of_float(sum.to_f)
                  end

        context.set_accumulator(name, new_val)
        new_val
      end

      # The largest integer that survives a double round-trip (2^53 - 1).
      MAX_SAFE_INTEGER = 9_007_199_254_740_991

      def accumulator_overflow?(current, sum)
        f = sum.to_f
        return true if f.nan? || f.infinite?

        current.integer? && sum.abs > MAX_SAFE_INTEGER
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
          # Treat as path without @; an unresolved bare word is a string literal.
          resolved = resolve_dotted_path(source.is_a?(Types::DynValue) ? source : context.source, str)
          resolved.is_a?(Types::DynValue) && resolved.null? ? Types::DynValue.of_string(str) : resolved
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
        if val.type == :currency || val.type == :currency_raw
          existing_dp = val.decimal_places || dp
          code = currency_code || val.currency_code
          if val.type == :currency_raw
            return Types::DynValue.of_currency_raw(val.value, existing_dp, code)
          end
          return Types::DynValue.of_currency(val.value.to_f, existing_dp, code)
        end
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

      # ── Inline Object / Raw JSON / Validation ──

      # Build a structural object from an inline ":object {key = @path, …}" spec.
      def build_inline_object(spec, context)
        trimmed = spec.strip.sub(/\A\{/, "").sub(/\}\z/, "")
        entries = {}
        unless trimmed.strip.empty?
          split_object_pairs(trimmed).each do |pair|
            eq = pair.index("=")
            next unless eq

            key = pair[0...eq].strip
            rhs = pair[(eq + 1)..].strip
            next if key.empty?

            expr, = TransformParser.new.parse_expression_string(rhs)
            entries[key] = evaluate(expr, context)
          end
        end
        Types::DynValue.of_object(entries)
      end

      # Split an inline-object body on commas not nested inside braces.
      def split_object_pairs(body)
        pairs = []
        depth = 0
        current = +""
        body.each_char do |ch|
          depth += 1 if ch == "{"
          depth -= 1 if ch == "}"
          if ch == "," && depth.zero?
            pairs << current
            current = +""
          else
            current << ch
          end
        end
        pairs << current unless current.strip.empty?
        pairs
      end

      # Parse a string value as JSON for :raw, producing a structural DynValue.
      def parse_raw_json_value(val)
        return val unless val.is_a?(Types::DynValue) && val.string?

        begin
          Types::DynValue.from_ruby(JSON.parse(val.value))
        rescue StandardError
          val
        end
      end

      # Validate a value against :validate / :enum / :range directives.
      # Returns false when the field should be dropped (onValidation = skip / fail).
      def validate_field_value(val, mapping, context)
        return true if val.is_a?(Types::DynValue) && val.null?

        cv = mapping_mods(mapping).validation
        policy = context.on_validation || "fail"
        failures = []

        if cv.pattern
          str = dynvalue_string(val)
          if cv.regex_error
            failures << "invalid validation pattern '#{cv.pattern}'"
          elsif !cv.regex.match?(str)
            failures << "value '#{str}' does not match pattern '#{cv.pattern}'"
          end
        end

        if cv.enum_allowed
          str = dynvalue_string(val)
          failures << "value '#{str}' is not one of [#{cv.enum_label}]" unless cv.enum_allowed.include?(str)
        end

        if cv.range_str
          num = numeric_of(val)
          if num.nil?
            failures << "value '#{dynvalue_string(val)}' is not numeric for range #{cv.range_str}"
          elsif (cv.range_min && num < cv.range_min) || (cv.range_max && num > cv.range_max)
            failures << "value #{num} is outside range #{cv.range_str}"
          end
        end

        return true if failures.empty?

        message = "Validation failed for '#{mapping.target_field}': #{failures.join('; ')}"
        case policy
        when "warn"
          # Warn but still emit.
          true
        when "skip"
          false
        else
          context.errors << TransformError.new(message, code: "T013")
          false
        end
      end

      def numeric_of(val)
        return nil unless val.is_a?(Types::DynValue)

        case val.type
        when :integer, :float, :float_raw, :currency, :currency_raw, :percent
          val.to_number.to_f
        when :string
          Float(val.value) rescue nil
        else
          nil
        end
      end

      def dynvalue_string(val)
        return val.to_s unless val.is_a?(Types::DynValue)

        FormatExporters.send(:dynvalue_to_string, val)
      end

      MAX_INTERPOLATIONS = 320

      # Interpolate ${...} expressions within a string template.
      # Supports ${@path}, ${%verb args}, and \${...} (literal ${...}).
      def interpolate_string(template, context)
        count = 0
        result = template.gsub(/\\?\$\{([^}]+)\}/) do
          match = Regexp.last_match(0)
          expr = Regexp.last_match(1)
          count += 1
          next match if count > MAX_INTERPOLATIONS

          # Escaped \${ — emit a literal ${...}.
          next "${#{expr}}" if match.start_with?("\\")

          trimmed = expr.strip
          if trimmed.start_with?("%")
            parsed, = TransformParser.new.send(:parse_expr_from_tokens,
                                               TransformParser.new.send(:tokenize_expression, trimmed))
            parsed ? dynvalue_string(evaluate(parsed, context)) : match
          elsif trimmed.start_with?("@")
            dynvalue_string(resolve_path(trimmed[1..], context))
          else
            match
          end
        end
        Types::DynValue.of_string(result)
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

      # Output formats with a registered formatter. An unrecognized format raises
      # T006 rather than silently defaulting to JSON.
      KNOWN_OUTPUT_FORMATS = %w[json odin xml csv fixed-width flat properties].freeze

      def format_output(output_dv, transform_def, context = nil)
        target_format = transform_def.target_format
        return nil unless target_format

        unless KNOWN_OUTPUT_FORMATS.include?(target_format)
          context.errors << self.class.invalid_output_format_error(target_format) if context
          return ""
        end

        # T007: positional layout directives (:pos/:len) only apply to fixed-width
        # output; on any other target they are invalid for the format.
        if context && target_format != "fixed-width"
          transform_def.segments.each do |segment|
            segment.field_mappings.each do |mapping|
              next unless mapping.directives.any? { |d| %w[pos len].include?(d.name) }

              err = TransformError.new(
                "Modifier ':pos/:len' is not valid for #{target_format} output",
                code: ErrorCodes::T007_INVALID_MODIFIER
              )
              err.field = mapping.target_field
              context.errors << err
            end
          end
        end

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
          format_fixed_width_output(output_dv, transform_def, context)
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

      # Format output as fixed-width text (segment-based)
      def format_fixed_width_output(output_dv, transform_def, context = nil)
        lw = transform_def.header.target_options["lineWidth"]
        has_line_width = !lw.nil? && parse_target_int(lw, 0) > 0
        line_width = has_line_width ? parse_target_int(lw, 80) : 80

        # T010: a field whose pos+len exceeds the configured line width overflows.
        if has_line_width && context
          transform_def.segments.each do |segment|
            segment.field_mappings.each do |mapping|
              pos_dir = mapping.directives.find { |d| d.name == "pos" }
              len_dir = mapping.directives.find { |d| d.name == "len" }
              next unless pos_dir && len_dir

              pos = pos_dir.value.to_i
              len = len_dir.value.to_i
              next unless pos + len > line_width

              err = TransformError.new(
                "Field '#{mapping.target_field}' position #{pos} + length #{len} exceeds line width #{line_width}",
                code: ErrorCodes::T010_POSITION_OVERFLOW
              )
              err.field = mapping.target_field
              context.errors << err
            end
          end
        end
        default_pad = transform_def.header.target_options["padChar"] || " "
        truncate = transform_def.header.target_options["truncate"] == "true"
        line_ending = transform_def.header.target_options["lineEnding"] || "\n"

        lines = []

        transform_def.segments.each do |segment|
          seg_name = segment.name
          seg_data = resolve_segment_data(output_dv, seg_name)

          literal_lines = extract_literal_lines(seg_data)
          if literal_lines
            literal_lines.each { |l| lines << l }
            next
          end

          if segment.is_array && seg_data.is_a?(Array)
            # Array segment: one line per item
            seg_data.each do |item|
              data = item.is_a?(Types::DynValue) ? dynvalue_to_flat_hash(item) : (item.is_a?(Hash) ? item : {})
              lines << format_fwf_line(segment.field_mappings, data, line_width, default_pad, has_line_width, truncate)
            end
          elsif segment.is_array && seg_data.is_a?(Types::DynValue) && seg_data.array?
            seg_data.value.each do |item|
              data = dynvalue_to_flat_hash(item)
              lines << format_fwf_line(segment.field_mappings, data, line_width, default_pad, has_line_width, truncate)
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
            lines << format_fwf_line(segment.field_mappings, data, line_width, default_pad, has_line_width, truncate)
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

      # Returns the verbatim lines of a rendered :literal segment, or nil.
      def extract_literal_lines(seg_data)
        return nil unless seg_data.is_a?(Types::DynValue) && seg_data.object?

        marker = seg_data.get("__literalLines")
        return nil unless marker.is_a?(Types::DynValue) && marker.array?

        marker.value.map { |v| v.is_a?(Types::DynValue) ? v.to_string : v.to_s }
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

      def format_fwf_line(mappings, data, line_width, default_pad, has_line_width = false, truncate = false)
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

        # Pad the record to the configured fixed line width.
        if has_line_width
          if line.length < line_width
            line += default_pad * (line_width - line.length)
          elsif line.length > line_width && truncate
            line = line[0...line_width]
          end
        end

        line
      end

      # ── XML Output Formatting (segment-based) ──

      def format_xml_output(output_dv, transform_def, context)
        topts = transform_def.header.target_options
        decl_val = topts["declaration"]
        include_declaration = decl_val != "false" && decl_val != "?false"
        indent_val = topts["indent"]
        indent_size = indent_val ? parse_target_int(indent_val, 2) : 2
        indent_str = " " * indent_size
        # emitTypeHints=false produces plain XML with no odin: attributes/namespace
        eth_val = topts["emitTypeHints"]
        emit_type_hints = eth_val != "false" && eth_val != "?false"
        namespaces = transform_def.header.target_namespaces || {}

        xml = +""
        xml << %{<?xml version="1.0" encoding="UTF-8"?>\n} if include_declaration

        # Collect per-field :attr, :ns and :cdata directives per segment
        attr_fields = {}
        ns_fields = {}
        cdata_fields = {}
        transform_def.segments.each do |segment|
          segment.field_mappings.each do |mapping|
            full = "#{segment.name}.#{mapping.target_field}"
            attr_fields[full] = true if mapping.directives.any? { |d| d.name == "attr" }
            cdata_fields[full] = true if mapping.directives.any? { |d| d.name == "cdata" }
            ns_dir = mapping.directives.find { |d| d.name == "ns" }
            ns_fields[full] = ns_dir.value if ns_dir
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
              xml << render_xml_segment_element(seg_name, item, segment, attr_fields, ns_fields, cdata_fields,
                                                is_array: true, indent_str: indent_str,
                                                emit_type_hints: emit_type_hints, namespaces: namespaces)
            end
          else
            data = if seg_data.is_a?(Types::DynValue)
                     seg_data
                   elsif seg_data.is_a?(Hash)
                     Types::DynValue.from_ruby(seg_data)
                   else
                     output_dv
                   end
            xml << render_xml_segment_element(seg_name, data, segment, attr_fields, ns_fields, cdata_fields,
                                              is_array: false, indent_str: indent_str,
                                              emit_type_hints: emit_type_hints, namespaces: namespaces)
          end
        end

        xml
      end

      def render_xml_segment_element(seg_name, data, segment, attr_fields, ns_fields, cdata_fields = {}, is_array: false, indent_str: "  ", emit_type_hints: true, namespaces: {})
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

        # xmlns:odin only when type hints are emitted; omitted on namespaced roots without typed content
        include_odin_ns = emit_type_hints && !is_array && (namespaces.empty? || has_typed)
        odin_ns = include_odin_ns ? ' xmlns:odin="https://odin.foundation/ns"' : ""
        ns_decls = !is_array ? build_xml_namespace_decls(namespaces) : ""
        attrs = attr_parts.empty? ? "" : " #{attr_parts.join(' ')}"

        xml = +"<#{seg_name}#{odin_ns}#{ns_decls}#{attrs}>\n"
        child_keys.each do |key|
          val = entries[key]
          next unless val
          tag = ns_qualify_xml(key, ns_fields["#{seg_name}.#{key}"])
          type_attr = emit_type_hints ? xml_type_attr(val) : ""
          text = if cdata_fields["#{seg_name}.#{key}"]
                   "<![CDATA[#{val_to_xml_string(val)}]]>"
                 else
                   xml_escape_attr(val_to_xml_string(val))
                 end
          xml << "#{indent_str}<#{tag}#{type_attr}>#{text}</#{tag}>\n"
        end
        xml << "</#{seg_name}>\n"
        xml
      end

      # Build xmlns:<prefix> declarations for target namespaces in insertion order
      def build_xml_namespace_decls(namespaces)
        return "" if namespaces.nil? || namespaces.empty?
        namespaces.map { |prefix, uri| " xmlns:#{prefix}=\"#{xml_escape_attr(uri)}\"" }.join
      end

      # Qualify an element name with its namespace prefix when :ns is set
      def ns_qualify_xml(key, prefix)
        prefix ? "#{prefix}:#{key}" : key
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
          # every currency is first-class; a coded currency also carries its ISO code
          dv.currency_code ? " odin:type=\"currency\" odin:currencyCode=\"#{dv.currency_code}\"" : ' odin:type="currency"'
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
          # render at the value's decimal scale (default 2), preserving precision
          dp = dv.decimal_places || 2
          format("%.#{dp}f", dv.value.to_f)
        when :currency_raw
          # raw string already carries exact precision
          dv.value.to_s
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
            Types::DynValue.of_string(s.empty? ? s : s[0].upcase + s[1..].downcase)
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
            sum = current.to_number + increment.to_number
            if accumulator_overflow?(current, sum)
              ctx.errors << self.class.accumulator_overflow_error(name, sum)
              current
            else
              new_val = if current.integer? && increment.integer?
                          Types::DynValue.of_integer(sum)
                        else
                          Types::DynValue.of_float(sum.to_f)
                        end
              ctx.set_accumulator(name, new_val)
              new_val
            end
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

          # Get match values (all args after table ref)
          match_values = args[1..].map { |a| a&.to_string || "" }
          match_key = match_values.join(", ")

          table = ctx.get_table(table_name)
          unless table
            report_table_not_found(ctx, table_name)
            return Types::DynValue.of_null
          end

          # Build list of match columns (all columns except return column)
          columns = table.columns
          return_col_index = columns.index(return_column)
          unless return_col_index
            report_lookup_miss(ctx, table_name, match_key)
            return Types::DynValue.of_null
          end

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

          report_lookup_miss(ctx, table_name, match_key)
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
          return Types::DynValue.of_integer(1) if args.empty?

          name = args[0].to_string
          start_value = args.length > 1 ? (args[1]&.to_number || 1).floor : 1
          current = ctx.sequences[name]
          current = current.nil? ? start_value : current + 1
          ctx.sequences[name] = current
          Types::DynValue.of_integer(current)
        }

        registry["resetSequence"] = ->(args, ctx) {
          return Types::DynValue.of_null if args.empty?

          name = args[0].to_string
          value = args.length > 1 ? (args[1]&.to_number || 0).floor : 0
          ctx.sequences[name] = value
          Types::DynValue.of_integer(value)
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
          return Types::DynValue.of_null if args.length < 2

          s = args[0]&.to_string || ""
          width = (args[1]&.to_number || 0).floor
          return Types::DynValue.of_null if width <= 0
          return Types::DynValue.of_string(s) if s.length <= width

          lines = []
          current = +""
          s.split(/\s+/).each do |word|
            if current.empty?
              current = word.dup
            elsif current.length + 1 + word.length <= width
              current << " " << word
            else
              lines << current
              current = word.dup
            end
          end
          lines << current unless current.empty?
          Types::DynValue.of_string(lines.join("\n"))
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
          return Types::DynValue.of_null if args.length < 3

          value = args[0]&.to_number || 0
          min = args[1]&.to_number || 0
          max = args[2]&.to_number || 0
          Types::DynValue.of_bool(value >= min && value <= max)
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
          Types::DynValue.of_string(format("%08x", Zlib.crc32(s)))
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
            items = v.value || []
            pairs = items.map { |item| to_object_pair(item) }
            if !items.empty? && pairs.all?
              obj = {}
              pairs.each { |k, val| obj[k] = val }
              Types::DynValue.of_object(obj)
            else
              obj = {}
              items.each_with_index { |item, i| obj[i.to_s] = item }
              Types::DynValue.of_object(obj)
            end
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
            # Deterministic UUID from seed
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
