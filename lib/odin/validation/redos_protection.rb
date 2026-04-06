# frozen_string_literal: true

module Odin
  module Validation
    module ReDoSProtection
      MAX_PATTERN_LENGTH = 1000
      MAX_QUANTIFIER_NESTING = 3
      MAX_PATTERN_STRING_LENGTH = 10_000

      # Check if a regex pattern is potentially dangerous
      # Returns :safe, :too_long, :nested_quantifiers, or :dangerous
      def self.check_pattern(pattern)
        return :too_long if pattern.length > MAX_PATTERN_LENGTH
        return :nested_quantifiers if nested_quantifier_depth(pattern) > MAX_QUANTIFIER_NESTING
        return :dangerous if dangerous_pattern?(pattern)
        :safe
      end

      def self.safe?(pattern)
        check_pattern(pattern) == :safe
      end

      # Compile a pattern after safety check, or raise
      def self.compile_safe(pattern)
        status = check_pattern(pattern)
        unless status == :safe
          raise Errors::OdinError.new(
            "REDOS",
            "Potentially dangerous regex pattern rejected: #{status}"
          )
        end
        Regexp.new(pattern)
      end

      # Test a regex against a value with length protection
      def self.safe_test(regex, value)
        return { matched: false, reason: :value_too_long } if value.length > MAX_PATTERN_STRING_LENGTH
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        matched = regex.match?(value)
        elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
        { matched: matched, timed_out: elapsed_ms > 100, execution_time_ms: elapsed_ms }
      end

      def self.nested_quantifier_depth(pattern)
        max_depth = 0
        current_depth = 0
        i = 0
        in_char_class = false

        while i < pattern.length
          ch = pattern[i]

          # Skip escaped characters
          if ch == "\\"
            i += 2
            next
          end

          if ch == "[" && !in_char_class
            in_char_class = true
          elsif ch == "]" && in_char_class
            in_char_class = false
          elsif !in_char_class
            case ch
            when "("
              current_depth += 1
            when ")"
              # Check if followed by quantifier
              next_i = i + 1
              if next_i < pattern.length && quantifier_char?(pattern[next_i])
                max_depth = [max_depth, current_depth].max
              end
              current_depth -= 1
              current_depth = 0 if current_depth < 0
            end
          end

          i += 1
        end
        max_depth
      end

      def self.dangerous_pattern?(pattern)
        # Nested quantifiers on groups: (X+)+ or (X*)+
        return true if pattern.match?(/\([^)]*[+*]\)\s*[+*]/)
        # Overlapping alternations with quantifier: (a|a)+
        return true if pattern.match?(/\([^)]*\|[^)]*\)\s*[+*]/)
        # Greedy dot-star repeated: (.*)+
        return true if pattern.match?(/\(\.\*\)\s*[+*]/)
        # Group with quantifier inside + bounded outer: (a+){N}
        return true if pattern.match?(/\([^)]*[+*]\)\s*\{/)
        false
      end

      def self.quantifier_char?(ch)
        ch == "*" || ch == "+" || ch == "?" || ch == "{"
      end

      private_class_method :nested_quantifier_depth, :dangerous_pattern?, :quantifier_char?
    end
  end
end
