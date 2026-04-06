# frozen_string_literal: true

module Odin
  module Transform
    class TransformParser
      # ── Complete Verb Arity Table ──
      VERB_ARITY = {
        # Arity 0
        "today" => 0, "now" => 0,

        # Arity 1
        "upper" => 1, "lower" => 1, "trim" => 1, "trimLeft" => 1, "trimRight" => 1,
        "coerceString" => 1, "coerceNumber" => 1, "coerceInteger" => 1,
        "coerceBoolean" => 1, "coerceDate" => 1, "coerceTimestamp" => 1,
        "tryCoerce" => 1, "toArray" => 1, "toObject" => 1,
        "not" => 1, "isNull" => 1, "isString" => 1, "isNumber" => 1,
        "isBoolean" => 1, "isArray" => 1, "isObject" => 1, "isDate" => 1,
        "typeOf" => 1,
        "capitalize" => 1, "titleCase" => 1, "length" => 1, "reverseString" => 1,
        "camelCase" => 1, "snakeCase" => 1, "kebabCase" => 1, "pascalCase" => 1,
        "slugify" => 1, "normalizeSpace" => 1, "stripAccents" => 1, "clean" => 1,
        "wordCount" => 1, "soundex" => 1,
        "abs" => 1, "floor" => 1, "ceil" => 1, "negate" => 1, "sign" => 1,
        "trunc" => 1, "isFinite" => 1, "isNaN" => 1, "ln" => 1, "log10" => 1,
        "exp" => 1, "sqrt" => 1,
        "formatInteger" => 1, "formatCurrency" => 1,
        "startOfDay" => 1, "endOfDay" => 1, "startOfMonth" => 1, "endOfMonth" => 1,
        "startOfYear" => 1, "endOfYear" => 1, "dayOfWeek" => 1, "weekOfYear" => 1,
        "quarter" => 1, "isLeapYear" => 1, "toUnix" => 1, "fromUnix" => 1,
        "dayOfMonth" => 1, "dayOfYear" => 1,
        "base64Encode" => 1, "base64Decode" => 1, "urlEncode" => 1, "urlDecode" => 1,
        "jsonEncode" => 1, "jsonDecode" => 1, "hexEncode" => 1, "hexDecode" => 1,
        "sha256" => 1, "sha1" => 1, "sha512" => 1, "md5" => 1, "crc32" => 1,
        "flatten" => 1, "distinct" => 1, "sort" => 1, "sortDesc" => 1,
        "reverse" => 1, "compact" => 1, "unique" => 1, "cumsum" => 1, "cumprod" => 1,
        "sum" => 1, "count" => 1, "min" => 1, "max" => 1, "avg" => 1,
        "first" => 1, "last" => 1,
        "std" => 1, "stdSample" => 1, "variance" => 1, "varianceSample" => 1,
        "median" => 1, "mode" => 1, "rowNumber" => 1,
        "uuid" => 1, "sequence" => 1, "resetSequence" => 1,
        "keys" => 1, "values" => 1, "entries" => 1,
        "toRadians" => 1, "toDegrees" => 1,
        "nextBusinessDay" => 1, "formatDuration" => 1,

        # Arity 2
        "ifNull" => 2, "ifEmpty" => 2,
        "and" => 2, "or" => 2, "xor" => 2,
        "eq" => 2, "ne" => 2, "lt" => 2, "lte" => 2, "gt" => 2, "gte" => 2,
        "contains" => 2, "startsWith" => 2, "endsWith" => 2,
        "truncate" => 2, "join" => 2,
        "mask" => 2, "match" => 2, "leftOf" => 2, "rightOf" => 2,
        "repeat" => 2, "matches" => 2, "levenshtein" => 2, "tokenize" => 2,
        "add" => 2, "subtract" => 2, "multiply" => 2, "divide" => 2, "mod" => 2,
        "formatNumber" => 2, "pow" => 2, "log" => 2, "formatPercent" => 2,
        "parseInt" => 2, "formatLocaleNumber" => 2, "round" => 2,
        "formatDate" => 2, "parseDate" => 2,
        "addDays" => 2, "addMonths" => 2, "addYears" => 2,
        "addHours" => 2, "addMinutes" => 2, "addSeconds" => 2,
        "formatTime" => 2, "formatTimestamp" => 2, "parseTimestamp" => 2,
        "isBefore" => 2, "isAfter" => 2,
        "daysBetweenDates" => 2, "ageFromDate" => 2, "isValidDate" => 2,
        "formatLocaleDate" => 2,
        "accumulate" => 2, "set" => 2,
        "percentile" => 2, "quantile" => 2, "covariance" => 2, "correlation" => 2,
        "weightedAvg" => 2, "npv" => 2, "irr" => 2, "zscore" => 2,
        "sortBy" => 2, "map" => 2, "indexOf" => 2, "at" => 2,
        "includes" => 2, "concatArrays" => 2, "zip" => 2, "groupBy" => 2,
        "take" => 2, "drop" => 2, "chunk" => 2, "pluck" => 2,
        "dedupe" => 2, "diff" => 2, "pctChange" => 2, "limit" => 2,
        "nanoid" => 2,
        "has" => 2, "merge" => 2, "jsonPath" => 2,
        "assert" => 2,
        "formatPhone" => 2, "movingAvg" => 2, "businessDays" => 2,

        # Arity 3
        "ifElse" => 3, "between" => 3,
        "substring" => 3, "replace" => 3, "replaceRegex" => 3,
        "padLeft" => 3, "padRight" => 3, "pad" => 3,
        "split" => 3, "extract" => 3, "wrap" => 3, "center" => 3,
        "clamp" => 3, "random" => 3, "safeDivide" => 3,
        "dateDiff" => 3, "isBetween" => 3,
        "compound" => 3, "discount" => 3, "pmt" => 3, "fv" => 3, "pv" => 3,
        "depreciation" => 3,
        "slice" => 3, "range" => 3, "shift" => 3, "rank" => 3,
        "lag" => 3, "lead" => 3, "sample" => 3, "fillMissing" => 3,
        "get" => 3,
        "reduce" => 3, "pivot" => 3, "unpivot" => 3, "convertUnit" => 3,

        # Arity 4
        "rate" => 4, "nper" => 4,
        "filter" => 4, "every" => 4, "some" => 4, "find" => 4,
        "findIndex" => 4, "partition" => 4,
        "bearing" => 4, "midpoint" => 4,

        # Arity 5
        "distance" => 5, "interpolate" => 5,

        # Arity 6
        "inBoundingBox" => 6
      }.freeze

      VARIADIC_VERBS = %w[
        concat coalesce cond switch lookup lookupDefault minOf maxOf
      ].freeze

      ALL_DIRECTIVES = %w[
        pos len field trim type date time timestamp boolean integer number
        currency percent binary duration reference leftPad rightPad truncate
        upper lower default decimals currencyCode required confidential
        deprecated attr if unless omitNull omitEmpty
      ].freeze

      class ParseError < StandardError
        attr_reader :code, :line

        def initialize(message, code: "T001", line: nil)
          @code = code
          @line = line
          super(message)
        end
      end

      def parse(text)
        raise ParseError.new("Transform text cannot be nil", code: "T001") if text.nil?
        raise ParseError.new("Transform text cannot be empty", code: "T001") if text.strip.empty?

        lines = text.lines.map(&:chomp)
        parse_lines(lines)
      end

      # Public for testing expression parsing
      def parse_expression_string(raw)
        return [LiteralExpr.new(Types::DynValue.of_null), []] if raw.nil? || raw.strip.empty?

        raw = raw.strip
        tokens = tokenize_expression(raw)
        return [LiteralExpr.new(Types::DynValue.of_null), []] if tokens.empty?

        expr, remaining = parse_expr_from_tokens(tokens)
        directives = parse_directives(remaining)
        [expr, directives]
      end

      private

      # ── Line-Based Parser ──

      def parse_lines(lines)
        current_section = nil
        current_section_type = nil # :header, :const, :accumulator, :table, :segment, :source
        current_table_name = nil
        current_table_columns = nil
        header_fields = {}
        sections = {} # name -> { assignments: [], raw_lines: [] }
        const_sections = {} # section_name -> [assignments]
        accumulator_sections = {} # section_name -> [assignments]
        table_sections = {} # table_name -> { columns: [...], rows: [...] }
        source_section_fields = {} # {$source} section fields

        lines.each do |line|
          stripped = line.strip

          # Skip empty lines and comments
          next if stripped.empty?
          next if stripped.start_with?(";")

          # Section header: {SectionName}
          if stripped =~ /\A\{(.*)\}\s*\z/
            section_name = $1

            if section_name == "$"
              current_section = "$"
              current_section_type = :header
            elsif section_name == "$const" || section_name == "$constants"
              current_section = section_name
              current_section_type = :const
              const_sections[section_name] ||= []
            elsif section_name == "$source"
              current_section = section_name
              current_section_type = :source
            elsif section_name == "$accumulator" || section_name == "$accumulators"
              current_section = section_name
              current_section_type = :accumulator
              accumulator_sections[section_name] ||= []
            elsif section_name =~ /\A\$\.?table\.([^\[]+)\[([^\]]+)\]\z/
              current_table_name = $1
              current_table_columns = $2.split(",").map(&:strip)
              current_section = section_name
              current_section_type = :table
              table_sections[current_table_name] = { columns: current_table_columns, rows: [] }
            else
              current_section = section_name
              current_section_type = :segment
              sections[section_name] ||= { assignments: [] }
            end
            next
          end

          # Handle table CSV data lines (no = sign, comma-separated)
          if current_section_type == :table && current_table_name
            row_values = parse_table_csv_line(stripped)
            if row_values && !row_values.empty?
              row = {}
              current_table_columns&.each_with_index do |col, i|
                row[col] = i < row_values.size ? row_values[i] : Types::DynValue.of_null
              end
              table_sections[current_table_name][:rows] << row
            end
            next
          end

          # Assignment: key = value
          if stripped =~ /\A([^=]+?)\s*=\s*(.*)\z/
            key = $1.strip
            raw_value = $2.strip
            # Strip trailing comments
            raw_value = strip_comment(raw_value)

            case current_section_type
            when :header
              header_fields[key] = raw_value
            when :source
              source_section_fields[key] = raw_value
            when :const
              const_sections[current_section] << { key: key, value: raw_value }
            when :accumulator
              accumulator_sections[current_section] << { key: key, value: raw_value }
            when :segment
              sections[current_section][:assignments] << { key: key, value: raw_value } if current_section
            else
              # Root-level assignment (treat as header)
              header_fields[key] = raw_value
            end
          end
        end

        # Parse header (merge source section into source_options)
        header = parse_header(header_fields, source_section_fields)

        # Parse constants from header fields and {$const} sections
        constants = parse_constants(header_fields, sections)
        const_sections.each_value do |assignments|
          assignments.each do |a|
            constants[a[:key]] = parse_raw_literal(unquote_or_typed(a[:value]))
          end
        end

        # Parse accumulators from header fields and {$accumulator} sections
        accumulators = parse_accumulators(header_fields)
        accumulator_sections.each_value do |assignments|
          assignments.each do |a|
            key = a[:key]
            raw_val = a[:value]
            if key.end_with?("._persist")
              acc_key = key.sub(/\._persist\z/, "")
              if accumulators[acc_key]
                accumulators[acc_key] = AccumulatorDef.new(
                  initial_value: accumulators[acc_key].initial_value,
                  persist: unquote(raw_val) == "true"
                )
              end
            else
              persist = false
              # Check for corresponding _persist in same section
              assignments.each do |pa|
                if pa[:key] == "#{key}._persist"
                  persist = unquote(pa[:value]) == "true"
                  break
                end
              end
              accumulators[key] = AccumulatorDef.new(
                initial_value: parse_raw_literal(unquote_or_typed(raw_val)),
                persist: persist
              )
            end
          end
        end

        # Parse tables from header fields and {$table.*} sections
        tables = parse_tables(header_fields)
        table_sections.each do |table_name, table_data|
          tables[table_name] = LookupTable.new(
            rows: table_data[:rows],
            columns: table_data[:columns],
            default_value: nil
          )
        end

        # Parse segments
        segments = parse_segments(sections)
        passes = segments.filter_map(&:pass).uniq.sort

        TransformDef.new(
          header: header,
          segments: segments,
          constants: constants,
          tables: tables,
          accumulators: accumulators,
          passes: passes
        )
      end

      def parse_table_csv_line(line)
        # Remove trailing comment
        line = strip_comment(line)
        return nil if line.strip.empty?

        values = []
        i = 0
        chars = line.chars
        len = chars.length

        while i < len
          # Skip whitespace
          i += 1 while i < len && (chars[i] == " " || chars[i] == "\t")
          break if i >= len

          if chars[i] == '"'
            # Quoted value
            j = i + 1
            str = +""
            while j < len
              if chars[j] == '\\'
                str << (chars[j + 1] || "")
                j += 2
              elsif chars[j] == '"'
                j += 1
                break
              else
                str << chars[j]
                j += 1
              end
            end
            values << parse_raw_literal(str)
            i = j
          else
            # Unquoted value
            j = i
            j += 1 while j < len && chars[j] != ","
            token = chars[i...j].join.strip
            values << parse_raw_literal(unquote_or_typed(token))
            i = j
          end

          # Skip comma
          i += 1 while i < len && (chars[i] == " " || chars[i] == "\t")
          i += 1 if i < len && chars[i] == ","
        end

        values
      end

      # ── Header Parsing ──

      def parse_header(fields, source_section_fields = {})
        direction = unquote(fields["direction"])
        target_format = unquote(fields["target.format"])
        odin_version = unquote(fields["odin"]) || "1.0.0"
        transform_version = unquote(fields["transform"]) || "1.0.0"
        id = unquote(fields["id"])
        name = unquote(fields["name"])

        enforce_str = unquote(fields["enforceConfidential"])
        enforce_confidential = case enforce_str&.downcase
                               when "redact" then ConfidentialMode::REDACT
                               when "mask" then ConfidentialMode::MASK
                               else ConfidentialMode::NONE
                               end

        strict_types = unquote(fields["strictTypes"]) == "true"

        source_options = {}
        target_options = {}
        fields.each do |key, val|
          if key.start_with?("source.") && key != "source.format"
            source_options[key.sub("source.", "")] = unquote(val)
          elsif key.start_with?("target.") && key != "target.format"
            target_options[key.sub("target.", "")] = unquote(val)
          end
        end

        # Merge {$source} section fields into source_options
        source_section_fields.each do |key, val|
          source_options[key] = unquote(val) || val
        end

        target_format ||= Direction.target_format(direction) if direction

        TransformHeader.new(
          odin_version: odin_version,
          transform_version: transform_version,
          direction: direction,
          target_format: target_format,
          enforce_confidential: enforce_confidential,
          source_options: source_options,
          target_options: target_options,
          strict_types: strict_types,
          id: id,
          name: name
        )
      end

      # ── Constants ──

      def parse_constants(header_fields, sections)
        constants = {}

        # From header: const.name = "value"
        header_fields.each do |key, val|
          if key.start_with?("const.") || key.start_with?("constants.")
            ckey = key.sub(/\A(?:const|constants)\./, "")
            constants[ckey] = parse_raw_literal(unquote_or_typed(val))
          end
        end

        # From {Constants} section
        %w[Constants constants].each do |section_name|
          next unless sections[section_name]

          sections[section_name][:assignments].each do |a|
            constants[a[:key]] = parse_raw_literal(unquote_or_typed(a[:value]))
          end
          # Remove so it doesn't get treated as a segment
          sections.delete(section_name)
        end

        constants
      end

      # ── Accumulators ──

      def parse_accumulators(header_fields)
        accumulators = {}
        persist_keys = {}

        header_fields.each do |key, val|
          if key =~ /\A(?:accumulator|accumulators)\.(.+)\._persist\z/
            persist_keys[$1] = unquote(val) == "true"
          elsif key =~ /\A(?:accumulator|accumulators)\.(.+)\z/
            acc_key = $1
            accumulators[acc_key] = AccumulatorDef.new(
              initial_value: parse_raw_literal(unquote_or_typed(val)),
              persist: false
            )
          end
        end

        # Apply persist flags
        persist_keys.each do |key, persist|
          next unless accumulators[key]

          accumulators[key] = AccumulatorDef.new(
            initial_value: accumulators[key].initial_value,
            persist: persist
          )
        end

        accumulators
      end

      # ── Tables ──

      def parse_tables(header_fields)
        table_data = {}

        header_fields.each do |key, val|
          next unless key =~ /\A(?:table|tables)\.(.+)\z/

          remainder = $1

          if remainder =~ /\A([^.\[]+)\[(\d+)\]\.(.+)\z/
            table_name = $1
            row_idx = $2.to_i
            col_name = $3
            table_data[table_name] ||= { rows: [], default: nil }
            table_data[table_name][:rows][row_idx] ||= {}
            table_data[table_name][:rows][row_idx][col_name] = parse_raw_literal(unquote_or_typed(val))
          elsif remainder =~ /\A([^.\[]+)\._default\z/
            table_name = $1
            table_data[table_name] ||= { rows: [], default: nil }
            table_data[table_name][:default] = parse_raw_literal(unquote_or_typed(val))
          end
        end

        tables = {}
        table_data.each do |name, data|
          rows = (data[:rows] || []).compact
          tables[name] = LookupTable.new(rows: rows, default_value: data[:default])
        end
        tables
      end

      # ── Segments ──

      def parse_segments(sections)
        segments = []

        sections.each do |section_name, section_data|
          next if section_name == "$" || section_name.start_with?("$")

          segment = parse_segment(section_name, section_data[:assignments])
          segments << segment
        end

        segments
      end

      def parse_segment(section_name, assignments)
        name = section_name
        array_index = nil
        is_array = false

        # Strip tabular column spec: "Items[] : col1, col2" -> "Items[]"
        name = $1 if name =~ /\A(.+\[\d*\])\s*:.*\z/

        # Parse array index: Items[0] or Items[]
        if name =~ /\A(.+)\[(\d*)\]\z/
          name = $1
          array_index = $2.empty? ? nil : $2.to_i
          is_array = true
        end

        field_mappings = []
        discriminator = nil
        discriminator_value = nil
        when_condition = nil
        each_source = nil
        if_condition = nil
        pass = nil
        counter_name = nil

        assignments.each do |a|
          key = a[:key]
          raw_val = a[:value]

          case key
          when "_type"
            discriminator_value = unquote_or_raw(raw_val)
          when "_discriminator"
            discriminator = unquote_or_raw(raw_val)
          when "_discriminatorValue"
            discriminator_value = unquote_or_raw(raw_val)
          when "_when"
            when_condition = unquote_or_raw(raw_val)
          when "_each", "_loop", "_from"
            each_source = unquote_or_raw(raw_val)
            is_array = true
          when "_if"
            if_condition = unquote_or_raw(raw_val)
          when "_pass"
            pass = parse_int_literal(raw_val)
          when "_counter"
            counter_name = unquote_or_raw(raw_val)
          else
            next if key.start_with?("_") && key != "_"

            mapping = parse_field_mapping(key, raw_val)
            field_mappings << mapping
          end
        end

        SegmentDef.new(
          name: name,
          path: section_name,
          array_index: array_index,
          field_mappings: field_mappings,
          discriminator: discriminator,
          discriminator_value: discriminator_value,
          when_condition: when_condition,
          each_source: each_source,
          if_condition: if_condition,
          pass: pass,
          counter_name: counter_name,
          is_array: is_array
        )
      end

      # ── Field Mapping ──

      def parse_field_mapping(target_field, raw_value)
        expr, directives = parse_expression_with_directives(raw_value)

        modifiers = []
        remaining_directives = []

        directives.each do |dir|
          case dir.name
          when "required" then modifiers << FieldModifier::REQUIRED
          when "confidential" then modifiers << FieldModifier::CONFIDENTIAL
          when "deprecated" then modifiers << FieldModifier::DEPRECATED
          else remaining_directives << dir
          end
        end

        # Collect extraction directives from CopyExpr into field mapping directives
        # (TypeScript parity: directives appear on BOTH CopyExpr and FieldMapping)
        collect_expr_directives(expr, remaining_directives)

        FieldMapping.new(
          target_field: target_field,
          expression: expr,
          modifiers: modifiers,
          directives: remaining_directives
        )
      end

      # Recursively collect extraction directives from expression tree into the field mapping
      def collect_expr_directives(expr, directives)
        case expr
        when CopyExpr
          expr.directives.each do |d|
            directives << d unless directives.any? { |existing| existing.name == d.name }
          end
        when VerbExpr
          expr.arguments.each { |arg| collect_expr_directives(arg, directives) }
        end
      end

      def parse_expression_with_directives(raw)
        return [LiteralExpr.new(Types::DynValue.of_null), []] if raw.nil? || raw.strip.empty?

        stripped = raw.strip
        # A quoted string whose content starts with @ is a copy expression (or verb call)
        # e.g. "@.value" -> @.value, "%upper @.name" -> %upper @.name
        if stripped.start_with?('"') && stripped.end_with?('"')
          inner = unescape_string(stripped[1...-1])
          if inner.start_with?("@") || inner.start_with?("%")
            stripped = inner
          end
        end

        tokens = tokenize_expression(stripped)
        return [LiteralExpr.new(Types::DynValue.of_null), []] if tokens.empty?

        expr, remaining = parse_expr_from_tokens(tokens)
        directives = parse_directives(remaining)
        [expr, directives]
      end

      # ── Expression Tokenizer ──

      def tokenize_expression(raw)
        tokens = []
        i = 0
        chars = raw.chars
        len = chars.length

        while i < len
          ch = chars[i]

          if ch =~ /\s/
            i += 1
            next
          end

          if ch == '"'
            str, i = read_quoted_string(chars, i)
            tokens << str
          elsif ch == ":" && (tokens.empty? || tokens.last =~ /\s\z/ || true)
            # Directive: read :name
            j = i + 1
            j += 1 while j < len && chars[j] !~ /\s/
            tokens << chars[i...j].join
            i = j
          elsif ch == "%"
            j = i + 1
            j += 1 if j < len && chars[j] == "&"
            j += 1 while j < len && chars[j] !~ /[\s"]/
            tokens << chars[i...j].join
            i = j
          elsif ch == "@"
            j = i + 1
            j += 1 while j < len && chars[j] !~ /\s/
            tokens << chars[i...j].join
            i = j
          elsif ch == "#"
            j = i + 1
            if j < len && chars[j] == "#"
              j += 1
            elsif j < len && chars[j] == "$"
              j += 1
            elsif j < len && chars[j] == "%"
              j += 1
            end
            j += 1 while j < len && chars[j] !~ /\s/
            tokens << chars[i...j].join
            i = j
          elsif ch == "?" || ch == "~"
            j = i + 1
            j += 1 while j < len && chars[j] !~ /\s/
            tokens << chars[i...j].join
            i = j
          else
            j = i
            j += 1 while j < len && chars[j] !~ /\s/
            tokens << chars[i...j].join
            i = j
          end
        end

        tokens
      end

      def read_quoted_string(chars, start)
        i = start + 1
        result = +'"'

        while i < chars.length
          ch = chars[i]
          if ch == "\\"
            if i + 1 < chars.length
              result << ch << chars[i + 1]
              i += 2
            else
              result << ch
              i += 1
            end
          elsif ch == '"'
            result << '"'
            i += 1
            break
          else
            result << ch
            i += 1
          end
        end

        [result, i]
      end

      # ── Recursive Descent Expression Parser ──

      def parse_expr_from_tokens(tokens)
        return [LiteralExpr.new(Types::DynValue.of_null), []] if tokens.empty?

        token = tokens.first

        if token.start_with?("%")
          parse_verb_expr(tokens)
        elsif token.start_with?("@")
          parse_copy_expr(tokens)
        elsif token.start_with?(":")
          [LiteralExpr.new(Types::DynValue.of_null), tokens]
        else
          parse_literal_expr(tokens)
        end
      end

      def parse_verb_expr(tokens)
        verb_token = tokens.shift
        custom = false

        if verb_token.start_with?("%&")
          verb_name = verb_token[2..]
          custom = true
        else
          verb_name = verb_token[1..]
        end

        arity = VERB_ARITY[verb_name]

        if arity.nil?
          # Variadic — consume all non-directive tokens
          args = []
          while !tokens.empty? && !tokens.first.start_with?(":")
            arg_expr, tokens = parse_expr_from_tokens(tokens)
            args << arg_expr
          end
          [VerbExpr.new(verb_name, args, custom: custom), tokens]
        elsif arity == 0
          [VerbExpr.new(verb_name, [], custom: custom), tokens]
        else
          args = []
          arity.times do
            break if tokens.empty? || tokens.first.start_with?(":")
            arg_expr, tokens = parse_expr_from_tokens(tokens)
            args << arg_expr
          end
          [VerbExpr.new(verb_name, args, custom: custom), tokens]
        end
      end

      EXTRACTION_DIRECTIVES = %w[pos len field trim].freeze
      # Directives that take a value argument (not boolean flags)
      VALUE_DIRECTIVES = %w[pos len field].freeze

      def parse_copy_expr(tokens)
        token = tokens.shift
        path = token == "@" ? "" : token[1..]

        if path.start_with?("#")
          raise ParseError.new("Invalid copy expression: #{token}", code: "P001")
        end

        # Consume trailing extraction directives (:pos, :len, :field, :trim)
        trailing_directives = []
        while !tokens.empty? && tokens.first.start_with?(":")
          directive_name = tokens.first[1..]
          break unless EXTRACTION_DIRECTIVES.include?(directive_name)

          tokens.shift # consume :name
          # Only consume a value token for directives that take values (pos, len, field)
          # :trim is a boolean flag with no value
          if VALUE_DIRECTIVES.include?(directive_name) && !tokens.empty? &&
              !tokens.first.start_with?(":") && !tokens.first.start_with?("%") && !tokens.first.start_with?("@")
            value_token = tokens.shift
            if value_token.match?(/\A-?\d+\z/)
              trailing_directives << OdinDirective.new(directive_name, value_token.to_i)
            elsif value_token.match?(/\A-?\d+\.\d+\z/)
              trailing_directives << OdinDirective.new(directive_name, value_token.to_f)
            elsif value_token.start_with?('"') && value_token.end_with?('"')
              trailing_directives << OdinDirective.new(directive_name, value_token[1...-1])
            else
              trailing_directives << OdinDirective.new(directive_name, value_token)
            end
          else
            trailing_directives << OdinDirective.new(directive_name, true)
          end
        end

        [CopyExpr.new(path, directives: trailing_directives), tokens]
      end

      def parse_literal_expr(tokens)
        token = tokens.shift
        value = parse_literal_value(token)
        [LiteralExpr.new(value), tokens]
      end

      def parse_literal_value(token)
        case token
        when "~" then Types::DynValue.of_null
        when "true", "?true" then Types::DynValue.of_bool(true)
        when "false", "?false" then Types::DynValue.of_bool(false)
        when /\A##(-?\d+)\z/
          Types::DynValue.of_integer($1.to_i)
        when /\A#\$(.+)\z/
          parse_currency_literal($1)
        when /\A#%(.+)\z/
          Types::DynValue.of_percent($1.to_f)
        when /\A#(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\z/
          Types::DynValue.of_float($1.to_f)
        when /\A"(.*)"\z/m
          Types::DynValue.of_string(unescape_string($1))
        else
          Types::DynValue.of_string(token)
        end
      end

      def parse_currency_literal(raw)
        if raw =~ /\A(.+):([A-Z]{3})\z/
          Types::DynValue.of_currency($1.to_f, 2, $2)
        else
          Types::DynValue.of_currency(raw.to_f)
        end
      end

      # ── Directive Parsing ──

      def parse_directives(tokens)
        directives = []
        return directives if tokens.nil? || tokens.empty?

        i = 0
        while i < tokens.length
          token = tokens[i]
          if token.start_with?(":")
            name = token[1..]
            if i + 1 < tokens.length && !tokens[i + 1].start_with?(":")
              value_token = tokens[i + 1]
              if value_token.start_with?('"') && value_token.end_with?('"')
                directives << OdinDirective.new(name, unescape_string(value_token[1...-1]))
              elsif value_token.match?(/\A-?\d+\z/)
                directives << OdinDirective.new(name, value_token.to_i)
              elsif value_token.match?(/\A-?\d+\.\d+\z/)
                directives << OdinDirective.new(name, value_token.to_f)
              else
                directives << OdinDirective.new(name, value_token)
              end
              i += 2
            else
              directives << OdinDirective.new(name, true)
              i += 1
            end
          else
            i += 1
          end
        end

        directives
      end

      # ── Helpers ──

      def unescape_string(s)
        s.gsub("\\n", "\n").gsub("\\r", "\r").gsub("\\t", "\t").gsub('\\"', '"').gsub("\\\\", "\\")
      end

      def unquote(val)
        return nil if val.nil?

        val = val.strip
        if val.start_with?('"') && val.end_with?('"') && val.length >= 2
          unescape_string(val[1...-1])
        else
          val
        end
      end

      def unquote_or_raw(val)
        return nil if val.nil?

        val = val.strip
        if val.start_with?('"') && val.end_with?('"') && val.length >= 2
          unescape_string(val[1...-1])
        else
          val
        end
      end

      def unquote_or_typed(val)
        return nil if val.nil?

        val.strip
      end

      def parse_raw_literal(raw)
        return Types::DynValue.of_null if raw.nil? || raw.strip.empty?

        raw = raw.strip
        case raw
        when "~" then Types::DynValue.of_null
        when "?true", "true" then Types::DynValue.of_bool(true)
        when "?false", "false" then Types::DynValue.of_bool(false)
        when /\A##(-?\d+)\z/ then Types::DynValue.of_integer($1.to_i)
        when /\A#\$(.+)\z/ then Types::DynValue.of_currency($1.to_f)
        when /\A#(-?\d+(?:\.\d+)?)\z/ then Types::DynValue.of_float($1.to_f)
        when /\A"(.*)"\z/m then Types::DynValue.of_string(unescape_string($1))
        else Types::DynValue.of_string(raw)
        end
      end

      def parse_int_literal(raw)
        return nil if raw.nil?

        raw = raw.strip
        if raw =~ /\A##(-?\d+)\z/
          $1.to_i
        elsif raw =~ /\A(-?\d+)\z/
          $1.to_i
        elsif raw.start_with?('"') && raw.end_with?('"')
          raw[1...-1].to_i
        else
          raw.to_i
        end
      end

      def strip_comment(raw)
        in_quotes = false
        escaped = false
        raw.each_char.with_index do |ch, i|
          if escaped
            escaped = false
            next
          end
          escaped = true if ch == "\\"
          if ch == '"'
            in_quotes = !in_quotes
            next
          end
          if ch == ";" && !in_quotes
            return raw[0...i].rstrip
          end
        end
        raw
      end
    end
  end
end
