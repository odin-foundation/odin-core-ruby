# frozen_string_literal: true

require "strscan"

module Odin
  module Parsing
    class Tokenizer
      MAX_DOCUMENT_SIZE = Utils::SecurityLimits::MAX_DOCUMENT_SIZE

      # Pre-compiled regex patterns for StringScanner (all frozen)
      RE_WHITESPACE       = /[ \t]+/
      RE_NEWLINE_CRLF     = /\r\n?/
      RE_IDENTIFIER       = /[a-zA-Z_][a-zA-Z0-9_\-]*/
      RE_IDENT_PATH       = /[a-zA-Z_][a-zA-Z0-9_\-.]*/
      RE_NUMERIC          = /[+\-]?[0-9eE.+\-]+/
      RE_CURRENCY_VAL     = /[+\-]?[0-9.]+(?:[eE][+\-]?\d+)?(?::[a-zA-Z0-9_\-]+)?/
      RE_WORD             = /[a-zA-Z0-9_.\-]+/
      RE_HEADER_CONTENT   = /[^}\r\n]*/
      RE_COMMENT_CONTENT  = /[^\r\n]*/
      RE_REF_PATH         = /[a-zA-Z0-9_.\[\]()?\-@']*/
      RE_BINARY_DATA      = /[^\s;\r\n]*/
      RE_BARE_VALUE       = /[^\s;:\r\n]+/
      RE_DATE_OR_NUM      = /[0-9eE.\-:+TZ]+/
      RE_DATE_PREFIX      = /\A\d{4}-\d{2}-\d{2}T/
      RE_DATE_EXACT       = /\A\d{4}-\d{2}-\d{2}\z/
      RE_DURATION         = /P[0-9YMWDTHS.]+/
      RE_TIME_VAL         = /T[0-9:.+\-Z]+/
      RE_ARRAY_INDEX      = /\[[^\]]*\]/

      ESCAPE_MAP = {
        '"'  => '"',
        '\\' => '\\',
        'n'  => "\n",
        't'  => "\t",
        'r'  => "\r",
        '0'  => "\0",
        '/'  => '/'
      }.freeze

      def initialize(text)
        @source = text
        @scanner = StringScanner.new(text)
        @line = 1
        @col = 1
        @tokens = Array.new(text.length / 10 + 16)
        @token_count = 0
      end

      def tokenize
        check_document_size!
        skip_bom
        scan_tokens
        emit(TokenType::EOF, "", @line, @col)
        @tokens.first(@token_count)
      end

      private

      def check_document_size!
        if @source.bytesize > MAX_DOCUMENT_SIZE
          raise Errors::ParseError.new(
            Errors::ParseErrorCode::MAXIMUM_DOCUMENT_SIZE_EXCEEDED,
            1, 1, "Document size #{@source.bytesize} exceeds limit #{MAX_DOCUMENT_SIZE}"
          )
        end
      end

      def skip_bom
        if @source.start_with?("\uFEFF")
          @scanner.pos = "\uFEFF".bytesize
          @col = 1
        elsif @source.bytesize >= 3 &&
              @source.getbyte(0) == 0xEF &&
              @source.getbyte(1) == 0xBB &&
              @source.getbyte(2) == 0xBF
          @scanner.pos = 3
          @col = 1
        end
      end

      def emit(type, value, line, col, raw: nil)
        @tokens[@token_count] = Token.new(type, value, line, col, raw: raw)
        @token_count += 1
      end

      # Track line/col after consuming text
      def track(text)
        i = 0
        len = text.length
        while i < len
          if text.getbyte(i) == 10 # \n
            @line += 1
            @col = 1
          else
            @col += 1
          end
          i += 1
        end
      end

      # Advance scanner by n bytes, updating line/col
      def skip_bytes(n)
        text = @scanner.peek(n)
        @scanner.pos += n
        track(text)
      end

      def scan_tokens
        s = @scanner

        until s.eos?
          # Skip horizontal whitespace
          if (ws = s.scan(RE_WHITESPACE))
            @col += ws.length
            next
          end

          line = @line
          col = @col

          byte = s.string.getbyte(s.pos)

          case byte
          when 10 # \n
            s.pos += 1
            emit(TokenType::NEWLINE, "\n", line, col)
            @line += 1
            @col = 1
          when 13 # \r
            if s.string.getbyte(s.pos + 1) == 10
              s.pos += 2
            else
              s.pos += 1
            end
            emit(TokenType::NEWLINE, "\n", line, col)
            @line += 1
            @col = 1
          when 59 # ;
            s.pos += 1
            @col += 1
            text = s.scan(RE_COMMENT_CONTENT) || ""
            emit(TokenType::COMMENT, text.strip, line, col)
            @col += text.length
          when 123 # {
            scan_header(line, col)
          when 61 # =
            s.pos += 1
            @col += 1
            emit(TokenType::EQUALS, "=", line, col)
            # Skip whitespace after =
            if (ws = s.scan(RE_WHITESPACE))
              @col += ws.length
            end
            scan_value_side
          when 124 # |
            s.pos += 1
            @col += 1
            emit(TokenType::PIPE, "|", line, col)
          when 35 # #
            scan_number_prefix(line, col)
          when 34 # "
            scan_string(line, col)
          when 63 # ?
            s.pos += 1
            @col += 1
            word = s.scan(RE_WORD) || ""
            @col += word.length
            if word == "true" || word == "false"
              emit(TokenType::BOOLEAN, word, line, col)
            else
              emit(TokenType::ERROR, "Invalid boolean: ?#{word}", line, col)
            end
          when 126 # ~
            s.pos += 1
            @col += 1
            emit(TokenType::NULL, "~", line, col)
          when 64 # @
            scan_reference(line, col)
          when 94 # ^
            scan_binary(line, col)
          when 37 # %
            scan_verb(line, col)
          when 44 # ,
            s.pos += 1
            @col += 1
            emit(TokenType::PATH, ",", line, col)
          when 33, 42 # ! *
            s.pos += 1
            @col += 1
            emit(TokenType::MODIFIER, byte == 33 ? "!" : "*", line, col)
          when 45 # -
            scan_identifier(line, col)
          when 58 # :
            scan_directive(line, col)
          when 46 # .
            scan_identifier(line, col)
          when 38 # &
            scan_identifier(line, col)
          when 91 # [
            scan_array_indexed_path(line, col)
          else
            if ident_start_byte?(byte)
              scan_identifier(line, col)
            elsif digit_byte?(byte)
              scan_date_or_number(line, col)
            else
              s.pos += 1
              @col += 1
              emit(TokenType::ERROR, byte.chr, line, col)
            end
          end
        end
      end

      def scan_value_side
        s = @scanner

        # Parse modifiers after =
        loop do
          break if s.eos?
          byte = s.string.getbyte(s.pos)
          break if byte == 10 || byte == 13 # newline

          case byte
          when 33 # !
            line = @line; col = @col
            s.pos += 1; @col += 1
            emit(TokenType::MODIFIER, "!", line, col)
            if (ws = s.scan(RE_WHITESPACE)) then @col += ws.length end
          when 42 # *
            line = @line; col = @col
            s.pos += 1; @col += 1
            emit(TokenType::MODIFIER, "*", line, col)
            if (ws = s.scan(RE_WHITESPACE)) then @col += ws.length end
          when 45 # -
            line = @line; col = @col
            s.pos += 1; @col += 1
            emit(TokenType::MODIFIER, "-", line, col)
            if (ws = s.scan(RE_WHITESPACE)) then @col += ws.length end
          else
            break
          end
        end

        # Now scan the actual value
        return if s.eos?
        byte = s.string.getbyte(s.pos)
        return if byte == 10 || byte == 13

        line = @line
        col = @col

        case byte
        when 35 # #
          scan_number_prefix(line, col)
        when 34 # "
          scan_string(line, col)
        when 63 # ?
          s.pos += 1; @col += 1
          word = s.scan(RE_WORD) || ""
          @col += word.length
          if word == "true" || word == "false"
            emit(TokenType::BOOLEAN, word, line, col)
          else
            emit(TokenType::ERROR, "Invalid boolean: ?#{word}", line, col)
          end
        when 126 # ~
          s.pos += 1; @col += 1
          emit(TokenType::NULL, "~", line, col)
        when 64 # @
          scan_reference(line, col)
        when 94 # ^
          scan_binary(line, col)
        when 37 # %
          scan_verb(line, col)
        when 59 # ;
          s.pos += 1; @col += 1
          text = s.scan(RE_COMMENT_CONTENT) || ""
          emit(TokenType::COMMENT, text.strip, line, col)
          @col += text.length
          return
        else
          if digit_byte?(byte)
            scan_date_or_number(line, col)
          elsif byte == 116 || byte == 102 # t, f
            scan_bare_boolean_or_identifier(line, col)
          elsif byte == 80 # P
            scan_possible_duration(line, col)
          elsif byte == 84 # T
            scan_possible_time(line, col)
          elsif ident_start_byte?(byte)
            scan_bare_string_value(line, col)
          else
            s.pos += 1; @col += 1
            emit(TokenType::ERROR, byte.chr, line, col)
            return
          end
        end

        # After value, check for directives and comments
        if (ws = s.scan(RE_WHITESPACE)) then @col += ws.length end
        return if s.eos?

        byte = s.string.getbyte(s.pos)
        if byte == 58 # :
          scan_directive(@line, @col)
          if (ws = s.scan(RE_WHITESPACE)) then @col += ws.length end
        end

        return if s.eos?
        byte = s.string.getbyte(s.pos)
        if byte == 59 # ;
          sl = @line; sc = @col
          s.pos += 1; @col += 1
          text = s.scan(RE_COMMENT_CONTENT) || ""
          emit(TokenType::COMMENT, text.strip, sl, sc)
          @col += text.length
        end
      end

      def scan_header(line, col)
        s = @scanner
        s.pos += 1; @col += 1 # skip {
        emit(TokenType::HEADER_OPEN, "{", line, col)

        if (ws = s.scan(RE_WHITESPACE)) then @col += ws.length end

        if !s.eos? && s.string.getbyte(s.pos) == 125 # }
          hline = @line; hcol = @col
          s.pos += 1; @col += 1
          emit(TokenType::HEADER_CLOSE, "}", hline, hcol)
          return
        end

        path_line = @line
        path_col = @col
        path = s.scan(RE_HEADER_CONTENT) || ""
        @col += path.length
        path = path.strip
        emit(TokenType::PATH, path, path_line, path_col) unless path.empty?

        if !s.eos? && s.string.getbyte(s.pos) == 125 # }
          hline = @line; hcol = @col
          s.pos += 1; @col += 1
          emit(TokenType::HEADER_CLOSE, "}", hline, hcol)
        else
          emit(TokenType::ERROR, "Unterminated header", line, col)
        end
      end

      def scan_number_prefix(line, col)
        s = @scanner
        s.pos += 1; @col += 1 # skip first #

        if s.eos?
          emit(TokenType::ERROR, "Invalid numeric format", line, col)
          return
        end
        byte = s.string.getbyte(s.pos)

        case byte
        when 35 # ## integer
          s.pos += 1; @col += 1
          val = scan_numeric_value
          if val.empty?
            emit(TokenType::ERROR, "Invalid numeric format", line, col)
          else
            emit(TokenType::INTEGER, val, line, col)
          end
        when 36 # #$ currency
          s.pos += 1; @col += 1
          val = scan_currency_value
          if val.empty?
            emit(TokenType::ERROR, "Invalid numeric format", line, col)
          else
            emit(TokenType::CURRENCY, val, line, col)
          end
        when 37 # #% percent
          s.pos += 1; @col += 1
          val = scan_numeric_value
          if val.empty?
            emit(TokenType::ERROR, "Invalid numeric format", line, col)
          else
            emit(TokenType::PERCENT, val, line, col)
          end
        else # # number
          val = scan_numeric_value
          if val.empty?
            emit(TokenType::ERROR, "Invalid numeric format", line, col)
          else
            emit(TokenType::NUMBER, val, line, col)
          end
        end
      end

      def scan_numeric_value
        val = @scanner.scan(RE_NUMERIC) || ""
        @col += val.length
        val
      end

      def scan_currency_value
        val = @scanner.scan(RE_CURRENCY_VAL) || ""
        @col += val.length
        val
      end

      def scan_string(line, col)
        s = @scanner
        s.pos += 1; @col += 1 # skip opening "

        # Check for multi-line """
        if !s.eos? && s.string.getbyte(s.pos) == 34 &&
           s.pos + 1 < s.string.bytesize && s.string.getbyte(s.pos + 1) == 34
          s.pos += 2; @col += 2
          scan_multiline_string(line, col)
          return
        end

        result = +""
        until s.eos?
          # Scan non-special characters in bulk
          chunk = s.scan(/[^"\\\r\n]+/)
          if chunk
            result << chunk
            @col += chunk.length
          end

          break if s.eos?
          byte = s.string.getbyte(s.pos)

          case byte
          when 92 # backslash
            s.pos += 1; @col += 1
            if s.eos?
              emit(TokenType::ERROR, "Unterminated escape sequence", line, col)
              return
            end
            esc_byte = s.string.getbyte(s.pos)
            if esc_byte == 110 then result << "\n"; s.pos += 1; @col += 1     # n
            elsif esc_byte == 116 then result << "\t"; s.pos += 1; @col += 1  # t
            elsif esc_byte == 114 then result << "\r"; s.pos += 1; @col += 1  # r
            elsif esc_byte == 34 then result << '"'; s.pos += 1; @col += 1    # "
            elsif esc_byte == 92 then result << '\\'; s.pos += 1; @col += 1   # \
            elsif esc_byte == 48 then result << "\0"; s.pos += 1; @col += 1   # 0
            elsif esc_byte == 47 then result << '/'; s.pos += 1; @col += 1    # /
            elsif esc_byte == 117 # u
              s.pos += 1; @col += 1
              result << scan_unicode_escape(line, col, 4)
            elsif esc_byte == 85 # U
              s.pos += 1; @col += 1
              result << scan_unicode_escape(line, col, 8)
            else
              # Read the actual character (may be multi-byte)
              esc_char = s.scan(/./) || "?"
              @col += 1
              emit(TokenType::ERROR, "Invalid escape: \\#{esc_char}", line, col)
              return
            end
          when 34 # closing "
            s.pos += 1; @col += 1
            emit(TokenType::STRING, result, line, col)
            return
          when 10, 13 # newline
            emit(TokenType::ERROR, "Unterminated string", line, col)
            return
          end
        end

        emit(TokenType::ERROR, "Unterminated string", line, col)
      end

      def scan_multiline_string(line, col)
        s = @scanner
        # Skip initial newline after opening """
        if !s.eos?
          byte = s.string.getbyte(s.pos)
          if byte == 10
            s.pos += 1; @line += 1; @col = 1
          elsif byte == 13
            s.pos += 1; @line += 1; @col = 1
            if !s.eos? && s.string.getbyte(s.pos) == 10
              s.pos += 1
            end
          end
        end

        result = +""
        until s.eos?
          # Check for closing """
          if s.string.getbyte(s.pos) == 34 &&
             s.pos + 2 < s.string.bytesize &&
             s.string.getbyte(s.pos + 1) == 34 &&
             s.string.getbyte(s.pos + 2) == 34
            s.pos += 3; @col += 3
            emit(TokenType::STRING, result, line, col)
            return
          end

          byte = s.string.getbyte(s.pos)
          if byte == 13 # \r
            result << "\n"
            s.pos += 1; @line += 1; @col = 1
            if !s.eos? && s.string.getbyte(s.pos) == 10
              s.pos += 1
            end
          elsif byte == 10 # \n
            result << "\n"
            s.pos += 1; @line += 1; @col = 1
          else
            # Scan non-special chars in bulk
            chunk = s.scan(/[^"\r\n]+/)
            if chunk
              result << chunk
              @col += chunk.length
            else
              # Single quote that isn't part of """
              result << s.string[s.pos]
              s.pos += 1; @col += 1
            end
          end
        end

        emit(TokenType::ERROR, "Unterminated multi-line string", line, col)
      end

      def scan_unicode_escape(line, col, num_digits)
        s = @scanner
        hex = s.peek(num_digits)
        unless hex.length == num_digits && hex.match?(/\A[0-9a-fA-F]+\z/)
          emit(TokenType::ERROR, "Invalid unicode escape", line, col)
          return ""
        end
        s.pos += num_digits; @col += num_digits
        codepoint = hex.to_i(16)

        # Check for surrogate pair
        if codepoint >= 0xD800 && codepoint <= 0xDBFF
          if !s.eos? && s.string.getbyte(s.pos) == 92 && # backslash
             s.pos + 1 < s.string.bytesize && s.string.getbyte(s.pos + 1) == 117 # u
            s.pos += 2; @col += 2
            low_hex = s.peek(4)
            unless low_hex.length == 4 && low_hex.match?(/\A[0-9a-fA-F]+\z/)
              emit(TokenType::ERROR, "Invalid surrogate pair", line, col)
              return ""
            end
            s.pos += 4; @col += 4
            low = low_hex.to_i(16)
            if low >= 0xDC00 && low <= 0xDFFF
              codepoint = 0x10000 + ((codepoint - 0xD800) << 10) + (low - 0xDC00)
            else
              emit(TokenType::ERROR, "Invalid low surrogate", line, col)
              return ""
            end
          else
            emit(TokenType::ERROR, "Expected low surrogate", line, col)
            return ""
          end
        end

        [codepoint].pack("U")
      end

      def scan_reference(line, col)
        s = @scanner
        s.pos += 1; @col += 1 # skip @

        if !s.eos? && s.string.getbyte(s.pos) == 35 # @#
          s.pos += 1; @col += 1
          emit(TokenType::ERROR, "@#", line, col)
          return
        end

        path = s.scan(RE_REF_PATH) || ""
        @col += path.length
        # Normalize leading zeros in array indices: [007] -> [7]
        path = path.gsub(/\[(\d+)\]/) { "[#{$1.to_i}]" }
        emit(TokenType::REFERENCE, path, line, col)
      end

      def scan_binary(line, col)
        s = @scanner
        s.pos += 1; @col += 1 # skip ^
        data = s.scan(RE_BINARY_DATA) || ""
        @col += data.length
        emit(TokenType::BINARY, data, line, col)
      end

      def scan_verb(line, col)
        s = @scanner
        s.pos += 1; @col += 1 # skip %

        if s.eos? || s.string.getbyte(s.pos) == 32 || s.string.getbyte(s.pos) == 9 ||
           s.string.getbyte(s.pos) == 10 || s.string.getbyte(s.pos) == 13
          emit(TokenType::ERROR, "Empty verb name", line, col)
          return
        end

        name = +""
        if !s.eos? && s.string.getbyte(s.pos) == 38 # &
          name << "&"
          s.pos += 1; @col += 1
        end

        word = s.scan(/[a-zA-Z0-9_.\-]+/) || ""
        name << word
        @col += word.length

        if name.empty?
          emit(TokenType::ERROR, "Invalid verb", line, col)
          return
        end

        emit(TokenType::VERB, name, line, col)
        scan_verb_arguments
      end

      def scan_verb_arguments
        s = @scanner
        until s.eos?
          if (ws = s.scan(RE_WHITESPACE)) then @col += ws.length end
          break if s.eos?

          byte = s.string.getbyte(s.pos)
          break if byte == 10 || byte == 13 || byte == 59 || byte == 58 # \n \r ; :

          line = @line
          col = @col

          case byte
          when 34 then scan_string(line, col)         # "
          when 35 then scan_number_prefix(line, col)   # #
          when 63 # ?
            s.pos += 1; @col += 1
            word = s.scan(RE_WORD) || ""
            @col += word.length
            if word == "true" || word == "false"
              emit(TokenType::BOOLEAN, word, line, col)
            else
              emit(TokenType::ERROR, "Invalid boolean: ?#{word}", line, col)
            end
          when 126 # ~
            s.pos += 1; @col += 1
            emit(TokenType::NULL, "~", line, col)
          when 64 then scan_reference(line, col)       # @
          when 94 then scan_binary(line, col)           # ^
          when 37 then scan_verb(line, col)             # %
          when 124 # |
            s.pos += 1; @col += 1
            emit(TokenType::PIPE, "|", line, col)
          else
            if digit_byte?(byte)
              scan_date_or_number(line, col)
            elsif byte == 116 || byte == 102 # t, f
              scan_bare_boolean_or_identifier(line, col)
            elsif byte == 80 # P
              scan_possible_duration(line, col)
            elsif byte == 84 # T
              scan_possible_time(line, col)
            elsif ident_start_byte?(byte)
              scan_bare_string_value(line, col)
            else
              break
            end
          end
        end
      end

      def scan_directive(line, col)
        s = @scanner
        s.pos += 1; @col += 1 # skip :
        name = s.scan(RE_WORD) || ""
        @col += name.length

        if name.empty?
          emit(TokenType::ERROR, "Empty directive", line, col)
          return
        end
        emit(TokenType::DIRECTIVE, name, line, col)

        # Directive may have a string value
        if (ws = s.scan(RE_WHITESPACE)) then @col += ws.length end
        return if s.eos?
        byte = s.string.getbyte(s.pos)
        return if byte == 10 || byte == 13 || byte == 59 # \n \r ;

        if byte == 34 # "
          scan_string(@line, @col)
        end
      end

      def scan_array_indexed_path(line, col)
        s = @scanner
        word = +""
        # Read [index]
        if (idx = s.scan(RE_ARRAY_INDEX))
          word << idx
          @col += idx.length
        end
        # Continue with identifier chars, dots, and more brackets
        loop do
          if (chunk = s.scan(/[a-zA-Z0-9_.\-]+/))
            word << chunk
            @col += chunk.length
          elsif (idx = s.scan(RE_ARRAY_INDEX))
            word << idx
            @col += idx.length
          else
            break
          end
        end
        emit(TokenType::PATH, word, line, col)
      end

      def scan_identifier(line, col)
        s = @scanner
        word = +""

        # Allow leading dot or &
        byte = s.string.getbyte(s.pos)
        if byte == 46 || byte == 38 # . or &
          word << s.string[s.pos]
          s.pos += 1; @col += 1
        end

        # Scan identifier body with dots and brackets
        loop do
          if (chunk = s.scan(/[a-zA-Z0-9_.\-]+/))
            word << chunk
            @col += chunk.length
          elsif (idx = s.scan(RE_ARRAY_INDEX))
            word << idx
            @col += idx.length
          elsif !s.eos? && s.string.getbyte(s.pos) == 38 # &
            word << "&"
            s.pos += 1; @col += 1
          else
            break
          end
        end

        emit(TokenType::PATH, word, line, col)
      end

      def scan_bare_boolean_or_identifier(line, col)
        s = @scanner
        word = s.scan(RE_WORD) || ""
        @col += word.length

        if word == "true" || word == "false"
          emit(TokenType::BOOLEAN, word, line, col)
        else
          # It's a bare string value — don't span multiple words
          emit(TokenType::STRING, word, line, col, raw: "bare")
        end
      end

      def scan_possible_duration(line, col)
        s = @scanner
        saved_pos = s.pos
        saved_col = @col
        saved_line = @line

        val = s.scan(RE_DURATION)
        if val && val.length > 1 && val.match?(/[0-9]/)
          @col += val.length
          emit(TokenType::DURATION, val, line, col)
        else
          s.pos = saved_pos
          @col = saved_col
          @line = saved_line
          scan_bare_string_value(line, col)
        end
      end

      def scan_possible_time(line, col)
        s = @scanner
        saved_pos = s.pos
        saved_col = @col
        saved_line = @line

        val = s.scan(RE_TIME_VAL)
        if val && val.length > 1
          @col += val.length
          emit(TokenType::TIME, val, line, col)
        else
          s.pos = saved_pos
          @col = saved_col
          @line = saved_line
          scan_bare_string_value(line, col)
        end
      end

      def scan_date_or_number(line, col)
        s = @scanner
        val = s.scan(RE_DATE_OR_NUM) || ""
        @col += val.length

        if val.match?(RE_DATE_PREFIX)
          emit(TokenType::TIMESTAMP, val, line, col)
        elsif val.match?(RE_DATE_EXACT)
          emit(TokenType::DATE, val, line, col)
        else
          emit(TokenType::NUMBER, val, line, col)
        end
      end

      def scan_bare_string_value(line, col)
        s = @scanner
        val = s.scan(RE_BARE_VALUE) || ""
        @col += val.length
        emit(TokenType::STRING, val, line, col, raw: "bare")
      end

      # Byte classification helpers (no allocation)
      def ident_start_byte?(b)
        (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 95
      end

      def digit_byte?(b)
        b >= 48 && b <= 57
      end
    end
  end
end
