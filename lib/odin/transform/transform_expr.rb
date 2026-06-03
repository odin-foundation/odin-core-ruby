# frozen_string_literal: true

module Odin
  module Transform
    # Compiles an infix arithmetic formula string into a tree of existing verbs
    # at parse time. No runtime evaluator: the result is an ordinary verb
    # expression, so arithmetic runs through the deterministic verbs (add,
    # subtract, multiply, divide, mod, negate, pow, and a whitelist of numeric
    # functions). Variables resolve under an explicit bindings object passed as
    # the second argument: in %expr "a + b" @.vars, the name a reads @.vars.a.
    #
    # Precedence, high to low:
    #   1. parentheses, function call
    #   2. ^ power (right-associative)
    #   3. unary - / +   (looser than ^, so -2^2 = -(2^2) = -4; (-2)^2 = 4)
    #   4. * / %  (left-associative)
    #   5. + -    (left-associative)
    module Expr
      class ExprSyntaxError < StandardError
        attr_reader :code

        def initialize(message)
          @code = "T015"
          super("Invalid %expr formula: #{message}")
        end
      end

      BINARY_OP = { "+" => "add", "-" => "subtract", "*" => "multiply", "/" => "divide", "%" => "mod" }.freeze

      FUNCTIONS = {
        "abs" => { verb: "abs", min: 1, max: 1 },
        "floor" => { verb: "floor", min: 1, max: 1 },
        "ceil" => { verb: "ceil", min: 1, max: 1 },
        "trunc" => { verb: "trunc", min: 1, max: 1 },
        "sqrt" => { verb: "sqrt", min: 1, max: 1 },
        "round" => { verb: "round", min: 1, max: 2 },
        "pow" => { verb: "pow", min: 2, max: 2 },
        "min" => { verb: "minOf", min: 1, max: Float::INFINITY },
        "max" => { verb: "maxOf", min: 1, max: Float::INFINITY }
      }.freeze

      Token = Struct.new(:kind, :value, :is_float)

      module_function

      def compile(formula, binding_path = nil)
        Parser.new(tokenize(formula), binding_path).parse
      end

      def tokenize(src)
        tokens = []
        i = 0
        len = src.length
        while i < len
          c = src[i]
          if c =~ /\s/
            i += 1
            next
          end
          if c =~ /[0-9]/
            j = i
            is_float = false
            j += 1 while j < len && src[j] =~ /[0-9]/
            if src[j] == "."
              is_float = true
              j += 1
              j += 1 while j < len && src[j] =~ /[0-9]/
            end
            if src[j] == "e" || src[j] == "E"
              is_float = true
              j += 1
              j += 1 if src[j] == "+" || src[j] == "-"
              j += 1 while j < len && src[j] =~ /[0-9]/
            end
            tokens << Token.new(:num, src[i...j], is_float)
            i = j
            next
          end
          if c =~ /[A-Za-z_]/
            j = i
            j += 1 while j < len && src[j] =~ /[A-Za-z0-9_.]/
            tokens << Token.new(:ident, src[i...j], false)
            i = j
            next
          end
          case c
          when "(" then tokens << Token.new(:lparen, c, false)
          when ")" then tokens << Token.new(:rparen, c, false)
          when "," then tokens << Token.new(:comma, c, false)
          when "+", "-", "*", "/", "%", "^" then tokens << Token.new(:op, c, false)
          else raise ExprSyntaxError, "unexpected character '#{c}'"
          end
          i += 1
        end
        tokens
      end

      def literal(text, is_float)
        value = is_float ? Types::DynValue.of_float(text.to_f) : Types::DynValue.of_integer(text.to_i)
        LiteralExpr.new(value)
      end

      def verb_node(verb, args)
        VerbExpr.new(verb, args, custom: false)
      end

      class Parser
        def initialize(tokens, binding_path)
          @tokens = tokens
          @binding_path = binding_path
          @pos = 0
        end

        def parse
          raise ExprSyntaxError, "empty formula" if @tokens.empty?
          expr = parse_additive
          raise ExprSyntaxError, "unexpected token '#{peek.value}'" if @pos < @tokens.length
          expr
        end

        private

        def peek
          @tokens[@pos]
        end

        def advance
          t = @tokens[@pos]
          @pos += 1
          t
        end

        def parse_additive
          left = parse_multiplicative
          while peek&.kind == :op && (peek.value == "+" || peek.value == "-")
            op = advance.value
            right = parse_multiplicative
            left = Expr.verb_node(BINARY_OP[op], [left, right])
          end
          left
        end

        def parse_multiplicative
          left = parse_unary
          while peek&.kind == :op && %w[* / %].include?(peek.value)
            op = advance.value
            right = parse_unary
            left = Expr.verb_node(BINARY_OP[op], [left, right])
          end
          left
        end

        def parse_unary
          t = peek
          if t&.kind == :op && (t.value == "-" || t.value == "+")
            advance
            operand = parse_unary
            return t.value == "-" ? Expr.verb_node("negate", [operand]) : operand
          end
          parse_power
        end

        def parse_power
          base = parse_primary
          if peek&.kind == :op && peek.value == "^"
            advance
            exponent = parse_unary
            return Expr.verb_node("pow", [base, exponent])
          end
          base
        end

        def parse_primary
          t = advance
          raise ExprSyntaxError, "unexpected end of formula" if t.nil?

          case t.kind
          when :num
            Expr.literal(t.value, t.is_float)
          when :lparen
            inner = parse_additive
            close = advance
            raise ExprSyntaxError, "missing closing parenthesis" if close.nil? || close.kind != :rparen
            inner
          when :ident
            return parse_call(t.value) if peek&.kind == :lparen
            if @binding_path.nil?
              raise ExprSyntaxError, "variable '#{t.value}' requires a bindings object, e.g. %expr \"...\" @.vars"
            end
            CopyExpr.new("#{@binding_path}.#{t.value}")
          else
            raise ExprSyntaxError, "unexpected token '#{t.value}'"
          end
        end

        def parse_call(name)
          fn = FUNCTIONS[name]
          raise ExprSyntaxError, "unknown function '#{name}'" if fn.nil?

          advance # consume '('
          args = []
          if peek&.kind != :rparen
            args << parse_additive
            while peek&.kind == :comma
              advance
              args << parse_additive
            end
          end
          close = advance
          raise ExprSyntaxError, "missing ) after #{name}(" if close.nil? || close.kind != :rparen

          if args.length < fn[:min] || args.length > fn[:max]
            bound = fn[:min] == fn[:max] ? fn[:min].to_s : "#{fn[:min]}-#{fn[:max]}"
            raise ExprSyntaxError, "#{name}() takes #{bound} arguments, got #{args.length}"
          end
          args << LiteralExpr.new(Types::DynValue.of_integer(0)) if name == "round" && args.length == 1
          Expr.verb_node(fn[:verb], args)
        end
      end
    end
  end
end
