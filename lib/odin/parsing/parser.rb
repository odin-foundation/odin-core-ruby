# frozen_string_literal: true

module Odin
  module Parsing
    class OdinParser
      MAX_NESTING_DEPTH = Utils::SecurityLimits::MAX_DEPTH
      MAX_ARRAY_INDEX = Utils::SecurityLimits::MAX_ARRAY_INDEX

      def parse(text, options = nil)
        text = text.encode("UTF-8") if text.is_a?(String) && text.encoding != Encoding::UTF_8
        tokens = Tokenizer.new(text).tokenize
        build_document(tokens, text, options)
      end

      private

      def build_document(tokens, source, options)
        @tokens = tokens
        @source = source
        @pos = 0

        # State
        @context = ""
        @previous_context = ""
        @metadata_mode = false
        @assigned_paths = {}
        @array_indices = {}

        # Tabular state
        @tabular_mode = false
        @tabular_primitive = false
        @tabular_columns = []
        @tabular_array_path = ""
        @tabular_row_index = 0

        # Document chaining
        @documents = []
        @current_builder = Types::OdinDocumentBuilder.new
        @current_metadata = {}
        @current_modifiers = {}
        @current_comments = {}

        # Directives
        @directives = []

        while @pos < @tokens.length
          token = @tokens[@pos]

          case token.type
          when TokenType::EOF
            break
          when TokenType::NEWLINE
            @pos += 1
            # Blank line after {$} metadata exits metadata mode (Java parity)
            if @metadata_mode && @context.empty?
              nt = @tokens[@pos]
              if nt && nt.type == TokenType::NEWLINE
                @metadata_mode = false
              end
            end
            next
          when TokenType::COMMENT
            @pos += 1
            next
          when TokenType::HEADER_OPEN
            exit_tabular_mode!
            parse_header
            next
          when TokenType::REFERENCE
            # Check for @import, @schema, @if directives
            if %w[import schema if].include?(token.value)
              parse_at_directive_from_ref(token)
              next
            end
            # Check for invalid @directive
            if token.value.empty? || !token.value.match?(/\A[a-zA-Z]/)
              # Bare @ or @unknown at line start — check if followed by =
              nt = peek_token
              if nt&.type == TokenType::EQUALS
                raise Errors::ParseError.new(
                  Errors::ParseErrorCode::UNEXPECTED_CHARACTER,
                  token.line, token.column,
                  "@ cannot be used as a path on the left side of assignment"
                )
              end
              # Unknown @directive
              raise Errors::ParseError.new(
                Errors::ParseErrorCode::UNEXPECTED_CHARACTER,
                token.line, token.column,
                "Invalid directive: @#{token.value}"
              )
            end
            # Otherwise fall through to tabular/assignment handling
            if @tabular_mode
              parse_tabular_row
              next
            end
            @pos += 1
            next
          when TokenType::PATH
            if token.value.start_with?("---")
              handle_doc_separator
              next
            end
            # Check for @directive at document level
            if token.value.start_with?("@")
              parse_at_directive(token)
              next
            end
            exit_tabular_mode!
            parse_assignment
            next
          when TokenType::PIPE
            # Pipe-based tabular (not used in current golden tests, but handle)
            skip_to_newline
            next
          when TokenType::ERROR
            handle_error_token(token)
            next
          else
            # In tabular mode, data rows start with a value token
            if @tabular_mode
              parse_tabular_row
              next
            end

            # Check for --- separator as standalone token
            if token.type == TokenType::MODIFIER && token.value == "-"
              if peek_is_doc_separator?
                handle_doc_separator
                next
              end
            end

            @pos += 1
          end
        end

        validate_array_contiguity!
        finalize_documents
      end

      def current_token
        @tokens[@pos]
      end

      def peek_token(offset = 1)
        p = @pos + offset
        p < @tokens.length ? @tokens[p] : nil
      end

      def advance
        t = @tokens[@pos]
        @pos += 1
        t
      end

      def expect(type)
        t = current_token
        if t.nil? || t.type != type
          line = t&.line || 0
          col = t&.column || 0
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::UNEXPECTED_CHARACTER,
            line, col,
            "Expected #{type}, got #{t&.type}"
          )
        end
        advance
      end

      def skip_newlines
        while @pos < @tokens.length && @tokens[@pos].type == TokenType::NEWLINE
          @pos += 1
        end
      end

      def skip_to_newline
        while @pos < @tokens.length
          break if @tokens[@pos].type == TokenType::NEWLINE || @tokens[@pos].type == TokenType::EOF
          @pos += 1
        end
        @pos += 1 if @pos < @tokens.length && @tokens[@pos].type == TokenType::NEWLINE
      end

      # --- Header Parsing ---

      def parse_header
        open_token = advance  # consume HEADER_OPEN

        # Collect the path content between { and }
        if current_token&.type == TokenType::HEADER_CLOSE
          # Empty header {} - reset to root
          advance
          @context = ""
          @previous_context = ""
          @metadata_mode = false
          return
        end

        if current_token&.type == TokenType::PATH
          path_token = advance
          raw_path = path_token.value.strip

          # Expect HEADER_CLOSE
          if current_token&.type == TokenType::HEADER_CLOSE
            advance
          else
            raise Errors::ParseError.new(
              Errors::ParseErrorCode::INVALID_HEADER_SYNTAX,
              open_token.line, open_token.column,
              "Missing closing brace"
            )
          end

          validate_header_path!(raw_path, path_token)
          resolve_header_path(raw_path, path_token)
        else
          # Try to read whatever is there until HEADER_CLOSE
          if current_token&.type == TokenType::HEADER_CLOSE
            advance
            @context = ""
            @metadata_mode = false
          else
            raise Errors::ParseError.new(
              Errors::ParseErrorCode::INVALID_HEADER_SYNTAX,
              open_token.line, open_token.column,
              "Invalid header"
            )
          end
        end
      end

      def resolve_header_path(raw_path, token)
        # Check for metadata header
        if raw_path == "$"
          @context = ""
          @metadata_mode = true
          return
        end

        # Check for metadata sub-path: $key or $.key
        if raw_path.start_with?("$")
          @metadata_mode = true
          sub = raw_path[1..]
          sub = sub[1..] if sub.start_with?(".")
          @context = sub || ""
          return
        end

        @metadata_mode = false

        # Check for tabular: path[] : col1, col2
        if raw_path =~ /\A(.+)\[\]\s*:\s*(.+)\z/
          array_path = $1
          columns_str = $2
          setup_tabular(array_path, columns_str, token)
          return
        end

        # Check for relative header
        if raw_path.start_with?(".")
          relative = raw_path[1..]
          if @previous_context.empty?
            @context = relative
          else
            @context = "#{@previous_context}.#{relative}"
          end
        else
          @context = raw_path
          @previous_context = raw_path
        end

        # Validate depth
        validate_depth!(@context, token)

        # Validate array indices in header path
        validate_path_indices!(@context, token)
      end

      def setup_tabular(array_path, columns_str, token)
        # Relative paths (starting with .) resolve relative to previous context
        # Absolute paths are used as-is (same logic as resolve_header_path)
        resolved_path = if array_path.start_with?(".")
                          if @previous_context.empty?
                            array_path[1..]
                          else
                            "#{@previous_context}#{array_path}"
                          end
                        else
                          array_path
                        end
        # Update previous_context for non-relative paths (same as resolve_header_path)
        @previous_context = resolved_path unless array_path.start_with?(".")

        @tabular_mode = true
        @tabular_array_path = resolved_path
        @tabular_row_index = 0

        columns_str = columns_str.strip
        if columns_str == "~"
          @tabular_primitive = true
          @tabular_columns = []
        else
          @tabular_primitive = false
          raw_cols = columns_str.split(",").map(&:strip)
          @tabular_columns = resolve_tabular_columns(raw_cols)
        end

        @context = resolved_path
      end

      def resolve_tabular_columns(raw_cols)
        resolved = []
        last_context = ""

        raw_cols.each do |col|
          if col.start_with?(".")
            # Relative column: use last context prefix
            resolved << "#{last_context}#{col}"
          else
            resolved << col
            # Update context to the prefix of this column (everything before the last segment)
            if col.include?(".")
              last_context = col.sub(/\.[^.]+\z/, "")
            else
              last_context = ""
            end
          end
        end

        resolved
      end

      def exit_tabular_mode!
        return unless @tabular_mode
        @tabular_mode = false
        @tabular_primitive = false
        @tabular_columns = []
      end

      # --- Assignment Parsing ---

      def parse_assignment
        path_token = advance  # consume PATH

        # Validate error tokens from tokenizer
        check_for_error_before_equals!

        # Expect EQUALS
        eq = current_token
        unless eq&.type == TokenType::EQUALS
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::UNEXPECTED_CHARACTER,
            path_token.line, path_token.column,
            "Expected '=' after path"
          )
        end
        advance  # consume EQUALS

        # Parse modifiers
        mods = parse_modifiers

        # Parse value
        value = parse_value(path_token)

        # Parse trailing directives
        directives = parse_trailing_directives

        # Parse trailing comment
        comment = nil
        if current_token&.type == TokenType::COMMENT
          comment = current_token.value
          advance
        end

        # Apply modifiers to value
        value = value.with_modifiers(mods) if mods.any?

        # Apply directives to value
        value = value.with_directives(directives) unless directives.empty?

        # Resolve full path
        raw_path = path_token.value
        full_path = resolve_path(raw_path)

        # Normalize leading zeros in array indices: [007] -> [7]
        full_path = full_path.gsub(/\[(\d+)\]/) { |m| "[#{$1.to_i}]" }

        # Validate depth
        validate_depth!(full_path, path_token)

        # Track array indices
        track_array_index(full_path, path_token)

        if @metadata_mode
          # Check duplicate in metadata
          if @current_metadata.key?(full_path)
            raise Errors::ParseError.new(
              Errors::ParseErrorCode::DUPLICATE_PATH_ASSIGNMENT,
              path_token.line, path_token.column,
              "Duplicate metadata key: #{full_path}"
            )
          end
          @current_metadata[full_path] = value
        else
          # Check duplicate
          if @assigned_paths.key?(full_path)
            raise Errors::ParseError.new(
              Errors::ParseErrorCode::DUPLICATE_PATH_ASSIGNMENT,
              path_token.line, path_token.column,
              "Duplicate path: #{full_path}"
            )
          end
          @assigned_paths[full_path] = true
          @current_builder.set(full_path, value, modifiers: mods.any? ? mods : nil, comment: comment)
          @current_modifiers[full_path] = mods if mods.any?
        end
      end

      def check_for_error_before_equals!
        if current_token&.type == TokenType::ERROR
          err_token = current_token
          val = err_token.value

          if val == "@#"
            raise Errors::ParseError.new(
              Errors::ParseErrorCode::UNEXPECTED_CHARACTER,
              err_token.line, err_token.column,
              "@# is invalid"
            )
          end

          raise Errors::ParseError.new(
            Errors::ParseErrorCode::UNEXPECTED_CHARACTER,
            err_token.line, err_token.column,
            val
          )
        end
      end

      def resolve_path(raw_path)
        if @context.empty?
          raw_path
        else
          "#{@context}.#{raw_path}"
        end
      end

      def parse_modifiers
        req = false
        conf = false
        depr = false

        while current_token&.type == TokenType::MODIFIER
          case current_token.value
          when "!" then req = true
          when "*" then conf = true
          when "-" then depr = true
          end
          advance
        end

        if req || conf || depr
          Types::OdinModifiers.new(required: req, confidential: conf, deprecated: depr)
        else
          Types::OdinModifiers::NONE
        end
      end

      def parse_value(context_token, allow_bare: false)
        t = current_token

        if t.nil? || t.type == TokenType::NEWLINE || t.type == TokenType::EOF
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::UNEXPECTED_CHARACTER,
            context_token.line, context_token.column,
            "Expected value"
          )
        end

        if t.type == TokenType::ERROR
          handle_error_token(t)
        end

        # Check for bare strings (unquoted) — raise P002 unless in verb arg context
        if !allow_bare && t.type == TokenType::STRING && t.raw == "bare"
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::BARE_STRING_NOT_ALLOWED,
            t.line, t.column,
            "Strings must be quoted"
          )
        end

        advance
        ValueParser.parse_value(t)
      end

      def parse_trailing_directives
        directives = []
        while current_token&.type == TokenType::DIRECTIVE
          dir_token = advance
          dir_name = dir_token.value

          # Check if next token is a directive value (string)
          dir_value = nil
          if current_token&.type == TokenType::STRING
            dir_value = current_token.value
            advance
          end

          directives << Types::OdinDirective.new(dir_name, dir_value)
        end
        directives
      end

      # --- Tabular Row Parsing ---

      def parse_tabular_row
        if @tabular_primitive
          parse_tabular_primitive_row
        else
          parse_tabular_object_row
        end
      end

      def parse_tabular_primitive_row
        # Single value per row
        t = current_token
        return skip_to_newline if t.nil? || t.type == TokenType::NEWLINE || t.type == TokenType::EOF

        value = parse_tabular_cell_value
        full_path = "#{@tabular_array_path}[#{@tabular_row_index}]"

        track_array_index(full_path, t)

        if @assigned_paths.key?(full_path)
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::DUPLICATE_PATH_ASSIGNMENT,
            t.line, t.column,
            "Duplicate path: #{full_path}"
          )
        end

        @assigned_paths[full_path] = true
        @current_builder.set(full_path, value)

        @tabular_row_index += 1
        skip_to_newline
      end

      def parse_tabular_object_row
        row_token = current_token
        col_idx = 0
        row_idx = @tabular_row_index

        while col_idx < @tabular_columns.length
          t = current_token
          break if t.nil? || t.type == TokenType::NEWLINE || t.type == TokenType::EOF || t.type == TokenType::HEADER_OPEN

          # Check for comma (separator between cells)
          # An absent cell is indicated by consecutive commas or trailing comma

          if is_value_token?(t)
            value = parse_tabular_cell_value
            col_name = @tabular_columns[col_idx]
            full_path = "#{@tabular_array_path}[#{row_idx}].#{col_name}"

            track_array_index(full_path, row_token)

            @assigned_paths[full_path] = true
            @current_builder.set(full_path, value)
          end
          # else: absent cell, skip

          col_idx += 1

          # Skip comma separator
          # After a value or absent cell, look for comma
          t = current_token
          if t&.type == TokenType::PATH && t.value == ","
            advance
          elsif t&.type == TokenType::COMMENT
            break
          elsif t&.type == TokenType::NEWLINE || t&.type == TokenType::EOF
            break
          end
        end

        @tabular_row_index += 1
        skip_to_newline
      end

      def is_value_token?(t)
        case t.type
        when TokenType::STRING, TokenType::NUMBER, TokenType::INTEGER,
             TokenType::CURRENCY, TokenType::PERCENT, TokenType::BOOLEAN,
             TokenType::NULL, TokenType::REFERENCE, TokenType::BINARY,
             TokenType::DATE, TokenType::TIMESTAMP, TokenType::TIME,
             TokenType::DURATION, TokenType::VERB, TokenType::MODIFIER
          true
        when TokenType::PATH
          # Bare booleans in tabular context
          t.value == "true" || t.value == "false"
        else
          false
        end
      end

      def parse_tabular_cell_value
        t = current_token
        return Types::NULL if t.nil?

        # Handle modifiers on cell values
        mods = parse_modifiers

        t = current_token
        return Types::NULL if t.nil? || t.type == TokenType::NEWLINE

        # Handle PATH tokens that are bare booleans (true/false) in tabular context
        if t.type == TokenType::PATH && (t.value == "true" || t.value == "false")
          advance
          value = t.value == "true" ? Types::TRUE_VAL : Types::FALSE_VAL
          value = value.with_modifiers(mods) if mods.any?
          return value
        end

        advance
        value = ValueParser.parse_value(t)
        value = value.with_modifiers(mods) if mods.any?
        value
      end

      # --- At-Directive Parsing (@import, @schema, @if) ---

      def parse_at_directive(token)
        directive_text = token.value
        advance  # consume the PATH token

        case directive_text
        when "@import"
          parse_import_directive(token)
        when "@schema"
          parse_schema_directive(token)
        when "@if"
          parse_if_directive(token)
        else
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::UNEXPECTED_CHARACTER,
            token.line, token.column,
            "Invalid directive: #{directive_text}"
          )
        end
      end

      # Handle @import/@schema/@if when tokenized as REFERENCE tokens
      def parse_at_directive_from_ref(token)
        directive_name = token.value  # "import", "schema", "if"
        advance  # consume the REFERENCE token

        case directive_name
        when "import"
          parse_import_directive_from_tokens(token)
        when "schema"
          parse_schema_directive(token)
        when "if"
          parse_if_directive(token)
        else
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::UNEXPECTED_CHARACTER,
            token.line, token.column,
            "Invalid directive: @#{directive_name}"
          )
        end
      end

      def parse_import_directive_from_tokens(token)
        # Collect all remaining tokens on this line as the import path
        parts = []
        alias_name = nil

        while current_token && current_token.type != TokenType::NEWLINE &&
              current_token.type != TokenType::EOF && current_token.type != TokenType::COMMENT
          t = advance
          parts << t.value.to_s
        end

        # Skip trailing comment
        advance if current_token&.type == TokenType::COMMENT

        if parts.empty?
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::INVALID_DIRECTIVE,
            token.line, token.column,
            "Import directive requires a path"
          )
        end

        # Reconstruct the import path, handling "as" alias
        # The path was split across multiple tokens. We need to rejoin them.
        # Look for "as" keyword
        full_text = parts.join("")

        # Check for "as" in the token values
        as_idx = nil
        parts.each_with_index do |p, i|
          if p == "as" && i > 0
            as_idx = i
            break
          end
        end

        if as_idx
          # Path is everything before "as", alias is everything after
          import_path = parts[0...as_idx].join("")
          remaining = parts[as_idx + 1..]
          if remaining.empty? || remaining.join("").strip.empty?
            raise Errors::ParseError.new(
              Errors::ParseErrorCode::INVALID_DIRECTIVE,
              token.line, token.column,
              "Import alias requires identifier"
            )
          end
          alias_name = remaining.join("").strip
          import_path = import_path.strip
        else
          import_path = full_text.strip
        end

        # Handle path reconstruction: tokenizer splits "./other.odin" into multiple tokens
        # We may need to add dots/slashes back
        @directives << { type: "import", path: import_path, alias: alias_name }
      end

      def parse_import_directive(token)
        # Expect: PATH (file path) [PATH("as") PATH(alias)]
        # The tokenizer puts the rest of the line as subsequent tokens
        # We need to collect the import path
        path_parts = []
        alias_name = nil

        # Read tokens until newline/EOF/comment
        while current_token && current_token.type != TokenType::NEWLINE &&
              current_token.type != TokenType::EOF && current_token.type != TokenType::COMMENT
          t = advance
          if t.type == TokenType::PATH || t.type == TokenType::STRING
            path_parts << t.value
          elsif t.type == TokenType::EQUALS
            path_parts << "="
          else
            path_parts << t.value.to_s
          end
        end

        # Skip trailing comment
        advance if current_token&.type == TokenType::COMMENT

        if path_parts.empty?
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::INVALID_DIRECTIVE,
            token.line, token.column,
            "Import directive requires a path"
          )
        end

        # Check for alias: "path as alias"
        as_idx = path_parts.index("as")
        if as_idx
          import_path = path_parts[0...as_idx].join(" ")
          if as_idx + 1 < path_parts.length
            alias_name = path_parts[as_idx + 1]
          else
            raise Errors::ParseError.new(
              Errors::ParseErrorCode::INVALID_DIRECTIVE,
              token.line, token.column,
              "Invalid import alias syntax"
            )
          end
        else
          import_path = path_parts.join(" ")
        end

        @directives << { type: "import", path: import_path, alias: alias_name }
      end

      def parse_schema_directive(token)
        parts = []
        while current_token && current_token.type != TokenType::NEWLINE &&
              current_token.type != TokenType::EOF && current_token.type != TokenType::COMMENT
          parts << advance.value.to_s
        end
        advance if current_token&.type == TokenType::COMMENT

        if parts.empty?
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::INVALID_DIRECTIVE,
            token.line, token.column,
            "Schema directive requires a URL"
          )
        end

        @directives << { type: "schema", url: parts.join("") }
      end

      def parse_if_directive(token)
        parts = []
        while current_token && current_token.type != TokenType::NEWLINE &&
              current_token.type != TokenType::EOF && current_token.type != TokenType::COMMENT
          t = advance
          parts << t.value.to_s
        end
        advance if current_token&.type == TokenType::COMMENT

        if parts.empty?
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::INVALID_DIRECTIVE,
            token.line, token.column,
            "If directive requires a condition"
          )
        end

        # Reconstruct condition with proper spacing
        condition = parts.join(" ")
        @directives << { type: "if", condition: condition }
      end

      # --- Document Chaining ---

      def handle_doc_separator
        # Skip --- tokens
        skip_to_newline

        # Finalize current document
        finalize_current_document

        # Reset state for next document
        @context = ""
        @previous_context = ""
        @metadata_mode = false
        @assigned_paths = {}
        @array_indices = {}
        @current_builder = Types::OdinDocumentBuilder.new
        @current_metadata = {}
        @current_modifiers = {}
        @current_comments = {}
        @directives = []
      end

      def peek_is_doc_separator?
        # Check if current position has --- pattern
        # This is already handled by the tokenizer PATH token
        false
      end

      def finalize_current_document
        validate_array_contiguity!

        doc_data = {
          metadata: @current_metadata.dup,
          assignments: @current_builder.instance_variable_get(:@assignments).dup,
          modifiers: @current_modifiers.dup,
          directives: @directives.dup
        }
        @documents << doc_data
      end

      def finalize_documents
        if @documents.empty?
          # Single document
          build_single_document
        else
          # We have chained documents, finalize the last one
          finalize_current_document
          build_chained_result
        end
      end

      def build_single_document
        # Build OdinDocument from accumulated state
        assignments = @current_builder.instance_variable_get(:@assignments)
        comments = @current_builder.instance_variable_get(:@comments)
        Types::OdinDocument.new(
          assignments: assignments,
          metadata: @current_metadata,
          modifiers: @current_modifiers,
          comments: comments
        )
      end

      def build_chained_result
        # For chained documents, return a special result
        # The first document is the "primary" one
        # Return it as an OdinDocument with chained_documents attribute
        primary = @documents[0]

        doc = Types::OdinDocument.new(
          assignments: primary[:assignments],
          metadata: primary[:metadata],
          modifiers: primary[:modifiers],
          comments: {}
        )

        # Store chained documents in instance variable
        chained = @documents.map do |d|
          Types::OdinDocument.new(
            assignments: d[:assignments],
            metadata: d[:metadata],
            modifiers: d[:modifiers],
            comments: {}
          )
        end

        # Use a wrapper that includes chained docs
        ParseResult.new(doc, chained, @documents)
      end

      # --- Validation ---

      def validate_header_path!(raw_path, token)
        # Check for malformed array indices in header: [, [}, [abc], etc.
        if raw_path =~ /\[/
          # Validate all bracket pairs
          raw_path.scan(/\[([^\]]*)\]?/).each do |match|
            content = match[0]
            # Check if bracket is properly closed
            unless raw_path.include?("[#{content}]")
              raise Errors::ParseError.new(
                Errors::ParseErrorCode::INVALID_ARRAY_INDEX,
                token.line, token.column,
                "Invalid array index in header"
              )
            end
            # If it has content, validate it's a valid index (digits or empty for tabular)
            unless content.empty? || content.match?(/\A\d+\z/)
              # Allow tabular syntax: path[] : cols
              next if content.strip.empty?
              raise Errors::ParseError.new(
                Errors::ParseErrorCode::INVALID_ARRAY_INDEX,
                token.line, token.column,
                "Invalid array index: #{content}"
              )
            end
          end
        end
      end

      def validate_depth!(path, token)
        depth = path_depth(path)
        if depth > MAX_NESTING_DEPTH
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::MAXIMUM_DEPTH_EXCEEDED,
            token.line, token.column,
            "Path depth #{depth} exceeds maximum #{MAX_NESTING_DEPTH}"
          )
        end
      end

      def path_depth(path)
        depth = 1
        path.each_char do |c|
          depth += 1 if c == "." || c == "["
        end
        depth
      end

      def validate_path_indices!(path, token)
        path.scan(/\[(\d+)\]/).each do |match|
          idx = match[0].to_i
          if idx > MAX_ARRAY_INDEX
            raise Errors::ParseError.new(
              Errors::ParseErrorCode::ARRAY_INDEX_OUT_OF_RANGE,
              token.line, token.column,
              "Array index #{idx} exceeds maximum"
            )
          end
        end

        # Check for negative index
        if path =~ /\[-/
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::INVALID_ARRAY_INDEX,
            token.line, token.column,
            "Negative array index"
          )
        end
      end

      def track_array_index(full_path, token)
        # Check for array index range
        cumulative = 0
        full_path.scan(/\[(\-?\d+)\]/).each do |match|
          idx_str = match[0]
          idx = idx_str.to_i

          if idx < 0
            raise Errors::ParseError.new(
              Errors::ParseErrorCode::INVALID_ARRAY_INDEX,
              token.line, token.column,
              "Negative array index: #{idx}"
            )
          end

          if idx > MAX_ARRAY_INDEX
            raise Errors::ParseError.new(
              Errors::ParseErrorCode::ARRAY_INDEX_OUT_OF_RANGE,
              token.line, token.column,
              "Array index #{idx} out of range"
            )
          end

          cumulative += idx
          if cumulative > MAX_ARRAY_INDEX
            raise Errors::ParseError.new(
              Errors::ParseErrorCode::ARRAY_INDEX_OUT_OF_RANGE,
              token.line, token.column,
              "Cumulative array index #{cumulative} out of range"
            )
          end
        end

        # Track first array index for contiguity check
        if full_path =~ /\A([^\[]*)\[(\d+)\]/
          array_base = $1
          idx = $2.to_i
          @array_indices[array_base] ||= []
          @array_indices[array_base] << idx unless @array_indices[array_base].include?(idx)
        end
      end

      def validate_array_contiguity!
        @array_indices.each do |path, indices|
          next if indices.empty?
          sorted = indices.sort
          if sorted[0] != 0
            raise Errors::ParseError.new(
              Errors::ParseErrorCode::NON_CONTIGUOUS_ARRAY_INDICES,
              0, 0,
              "Array '#{path}' does not start at index 0"
            )
          end
          sorted.each_with_index do |idx, i|
            if idx != i
              raise Errors::ParseError.new(
                Errors::ParseErrorCode::NON_CONTIGUOUS_ARRAY_INDICES,
                0, 0,
                "Non-contiguous array indices for '#{path}': expected #{i}, got #{idx}"
              )
            end
          end
        end
      end

      # --- Error Handling ---

      def handle_error_token(token)
        val = token.value

        case val
        when "@#"
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::UNEXPECTED_CHARACTER,
            token.line, token.column,
            "@# is invalid"
          )
        when /\AUnterminated string/
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::UNTERMINATED_STRING,
            token.line, token.column,
            val
          )
        when /\AUnterminated/
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::UNTERMINATED_STRING,
            token.line, token.column,
            val
          )
        when /\AInvalid escape/
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::INVALID_ESCAPE_SEQUENCE,
            token.line, token.column,
            val
          )
        when /\AInvalid boolean/, /\AInvalid numeric/
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::INVALID_TYPE_PREFIX,
            token.line, token.column,
            val
          )
        when /\AInvalid unicode/
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::INVALID_ESCAPE_SEQUENCE,
            token.line, token.column,
            val
          )
        when /\AUnterminated header/
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::INVALID_HEADER_SYNTAX,
            token.line, token.column,
            val
          )
        when /\AEmpty directive/
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::INVALID_DIRECTIVE,
            token.line, token.column,
            val
          )
        when /\AEmpty verb/
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::UNEXPECTED_CHARACTER,
            token.line, token.column,
            val
          )
        else
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::UNEXPECTED_CHARACTER,
            token.line, token.column,
            val
          )
        end
      end
    end

    # Result wrapper for chained documents
    class ParseResult
      attr_reader :metadata, :assignments, :modifiers, :chained_documents, :raw_documents

      def initialize(primary_doc, chained_docs, raw_docs)
        @primary = primary_doc
        @chained_documents = chained_docs
        @raw_documents = raw_docs
        @assignments = primary_doc.assignments
        @metadata = primary_doc.metadata
        @modifiers = primary_doc.all_modifiers
      end

      def get(path)
        @primary.get(path)
      end

      def [](path)
        get(path)
      end

      def include?(path)
        @primary.include?(path)
      end

      def size
        @primary.size
      end

      def paths
        @primary.paths
      end

      def empty?
        @primary.empty?
      end

      def each_assignment(&block)
        @primary.each_assignment(&block)
      end

      def each_metadata(&block)
        @primary.each_metadata(&block)
      end

      def modifiers_for(path)
        @primary.modifiers_for(path)
      end

      def all_modifiers
        @primary.all_modifiers
      end

      def comment_for(path)
        @primary.comment_for(path)
      end

      def all_comments
        @primary.all_comments
      end

      def metadata_value(key)
        @metadata[key]
      end

      def documents
        @chained_documents
      end
    end
  end
end
