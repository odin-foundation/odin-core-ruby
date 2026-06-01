# frozen_string_literal: true

require "set"

module Odin
  module Validation
    # Recursive-descent evaluator over the invariant grammar:
    #   expression     = logic_or
    #   logic_or       = logic_and , { "||" , logic_and }
    #   logic_and      = equality , { "&&" , equality }
    #   equality       = comparison , { ( "==" | "!=" | "=" ) , comparison }
    #   comparison     = additive , { ( ">" | "<" | ">=" | "<=" ) , additive }
    #   additive       = multiplicative , { ( "+" | "-" ) , multiplicative }
    #   multiplicative = unary , { ( "*" | "/" | "%" ) , unary }
    #   unary          = [ "!" ] , primary
    #   primary        = path | number | string | "(" , expression , ")"
    class InvariantEvaluator
      EPSILON = 1e-9
      MULTI_CHAR_OPS = %w[== != >= <= && ||].freeze
      SINGLE_CHAR_OPS = Set.new(%w[+ - * / % > < = !]).freeze
      BOOLEAN_LITERALS = { "true" => true, "false" => false }.freeze

      ParseError = Class.new(StandardError)

      Token = Struct.new(:kind, :text)

      # Result of evaluating an expression.
      #   value:        true/false when evaluable; nil when an operand is absent.
      #   null_operand: true if any referenced field is present but null.
      Result = Struct.new(:value, :null_operand)

      # resolver: a callable taking a field name, returning an OdinValue or nil.
      def initialize(resolver)
        @resolve = resolver
      end

      def evaluate(expr)
        @tokens = tokenize(expr)
        @pos = 0
        @absent_operand = false
        @null_operand = false

        final = parse_expression
        raise ParseError, "Unexpected trailing tokens" unless peek.nil?

        result =
          if @null_operand
            false
          elsif @absent_operand
            nil
          else
            to_bool(final)
          end

        Result.new(result, @null_operand)
      end

      private

      def tokenize(expr)
        tokens = []
        i = 0
        while i < expr.length
          c = expr[i]
          if c == " " || c == "\t"
            i += 1
            next
          end
          if c == "("
            tokens << Token.new(:lparen, "(")
            i += 1
            next
          end
          if c == ")"
            tokens << Token.new(:rparen, ")")
            i += 1
            next
          end
          if c == '"' || c == "'"
            quote = c
            j = i + 1
            text = +""
            while j < expr.length && expr[j] != quote
              text << expr[j]
              j += 1
            end
            raise ParseError, "Unterminated string literal" if j >= expr.length

            tokens << Token.new(:string, text)
            i = j + 1
            next
          end
          two = expr[i, 2]
          if MULTI_CHAR_OPS.include?(two)
            tokens << Token.new(:op, two)
            i += 2
            next
          end
          if SINGLE_CHAR_OPS.include?(c)
            tokens << Token.new(:op, c)
            i += 1
            next
          end
          if c >= "0" && c <= "9"
            j = i
            j += 1 while j < expr.length && expr[j].match?(/[0-9.]/)
            tokens << Token.new(:number, expr[i...j])
            i = j
            next
          end
          if c.match?(/[A-Za-z_]/)
            j = i
            j += 1 while j < expr.length && expr[j].match?(/[A-Za-z0-9_.]/)
            tokens << Token.new(:ident, expr[i...j])
            i = j
            next
          end
          raise ParseError, "Unexpected character '#{c}' in invariant expression"
        end
        tokens
      end

      def peek
        @tokens[@pos]
      end

      def advance
        tok = @tokens[@pos]
        @pos += 1
        tok
      end

      def parse_expression
        parse_logic_or
      end

      def parse_logic_or
        left = parse_logic_and
        while peek&.text == "||"
          advance
          right = parse_logic_and
          left = to_bool(left) || to_bool(right)
        end
        left
      end

      def parse_logic_and
        left = parse_equality
        while peek&.text == "&&"
          advance
          right = parse_equality
          left = to_bool(left) && to_bool(right)
        end
        left
      end

      def parse_equality
        left = parse_comparison
        while %w[== != =].include?(peek&.text)
          op = advance.text
          right = parse_comparison
          eq = loose_equals(left, right)
          left = op == "!=" ? !eq : eq
        end
        left
      end

      def parse_comparison
        left = parse_additive
        while %w[> < >= <=].include?(peek&.text)
          op = advance.text
          right = parse_additive
          left = compare(left, op, right)
        end
        left
      end

      def parse_additive
        left = parse_multiplicative
        while %w[+ -].include?(peek&.text)
          op = advance.text
          right = parse_multiplicative
          ln = to_num(left)
          rn = to_num(right)
          left = if ln.nil? || rn.nil?
                   Float::NAN
                 else
                   op == "+" ? ln + rn : ln - rn
                 end
        end
        left
      end

      def parse_multiplicative
        left = parse_unary
        while %w[* / %].include?(peek&.text)
          op = advance.text
          right = parse_unary
          ln = to_num(left)
          rn = to_num(right)
          left = if ln.nil? || rn.nil?
                   Float::NAN
                 elsif op == "*"
                   ln * rn
                 elsif op == "/"
                   rn.zero? ? Float::NAN : ln / rn
                 else
                   rn.zero? ? Float::NAN : ln % rn
                 end
        end
        left
      end

      def parse_unary
        if peek&.text == "!"
          advance
          operand = parse_unary
          return !to_bool(operand)
        end
        parse_primary
      end

      def parse_primary
        tok = advance
        raise ParseError, "Unexpected end of invariant expression" if tok.nil?

        case tok.kind
        when :lparen
          inner = parse_expression
          close = advance
          raise ParseError, "Expected closing parenthesis" if close.nil? || close.kind != :rparen

          inner
        when :number
          n = Float(tok.text)
          n
        when :string
          tok.text
        when :ident
          return BOOLEAN_LITERALS[tok.text] if BOOLEAN_LITERALS.key?(tok.text)

          value = @resolve.call(tok.text)
          if value.nil?
            @absent_operand = true
            return Float::NAN
          end
          if value.null?
            @null_operand = true
            return nil
          end
          operand_from_value(value)
        else
          raise ParseError, "Unexpected token '#{tok.text}'"
        end
      rescue ArgumentError, TypeError
        raise ParseError, "Invalid number"
      end

      def operand_from_value(value)
        if value.numeric?
          value.value.to_f
        elsif value.string?
          value.value
        elsif value.boolean?
          value.value
        elsif value.date? || value.timestamp?
          temporal_to_number(value)
        else
          Float::NAN
        end
      end

      def temporal_to_number(value)
        v = value.value
        if v.respond_to?(:to_time)
          v.to_time.to_f * 1000.0
        elsif v.respond_to?(:to_f)
          v.to_f
        else
          Float::NAN
        end
      end

      def to_num(v)
        if v.is_a?(Numeric)
          return nil if v.respond_to?(:nan?) && v.nan?

          v.to_f
        elsif v == true
          1.0
        elsif v == false
          0.0
        end
      end

      def to_bool(v)
        return v if v == true || v == false
        if v.is_a?(Numeric)
          return false if v.respond_to?(:nan?) && v.nan?

          return v != 0
        end
        return !v.empty? if v.is_a?(String)

        false
      end

      def loose_equals(a, b)
        if a.is_a?(Numeric) && b.is_a?(Numeric)
          return (a - b).abs < EPSILON
        end
        return a == b if a.is_a?(String) && b.is_a?(String)
        return a == b if (a == true || a == false) && (b == true || b == false)

        an = to_num(a)
        bn = to_num(b)
        return (an - bn).abs < EPSILON if an && bn

        a == b
      end

      def compare(a, op, b)
        an = to_num(a)
        bn = to_num(b)
        if an && bn
          case op
          when ">" then return an > bn
          when "<" then return an < bn
          when ">=" then return an >= bn
          when "<=" then return an <= bn
          end
        end
        if a.is_a?(String) && b.is_a?(String)
          case op
          when ">" then return a > b
          when "<" then return a < b
          when ">=" then return a >= b
          when "<=" then return a <= b
          end
        end
        false
      end
    end
  end
end
