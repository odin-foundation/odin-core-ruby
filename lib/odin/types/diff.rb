# frozen_string_literal: true

module Odin
  module Types
    class DiffEntry
      attr_reader :path, :value, :modifiers

      def initialize(path:, value:, modifiers: nil)
        @path = path.freeze
        @value = value
        @modifiers = modifiers
        freeze
      end

      def ==(other)
        other.is_a?(DiffEntry) && path == other.path &&
          value == other.value && modifiers == other.modifiers
      end
      alias eql? ==

      def hash
        [path, value, modifiers].hash
      end
    end

    class DiffChange
      attr_reader :path, :old_value, :new_value, :old_modifiers, :new_modifiers

      def initialize(path:, old_value:, new_value:, old_modifiers: nil, new_modifiers: nil)
        @path = path.freeze
        @old_value = old_value
        @new_value = new_value
        @old_modifiers = old_modifiers
        @new_modifiers = new_modifiers
        freeze
      end

      def ==(other)
        other.is_a?(DiffChange) && path == other.path &&
          old_value == other.old_value && new_value == other.new_value &&
          old_modifiers == other.old_modifiers && new_modifiers == other.new_modifiers
      end
      alias eql? ==

      def hash
        [path, old_value, new_value, old_modifiers, new_modifiers].hash
      end
    end

    class DiffMove
      attr_reader :from_path, :to_path, :value, :modifiers

      def initialize(from_path:, to_path:, value:, modifiers: nil)
        @from_path = from_path.freeze
        @to_path = to_path.freeze
        @value = value
        @modifiers = modifiers
        freeze
      end

      def ==(other)
        other.is_a?(DiffMove) && from_path == other.from_path &&
          to_path == other.to_path && value == other.value &&
          modifiers == other.modifiers
      end
      alias eql? ==

      def hash
        [from_path, to_path, value, modifiers].hash
      end
    end

    class OdinDiff
      attr_reader :added, :removed, :changed, :moved

      def initialize(added: [], removed: [], changed: [], moved: [])
        @added = added.freeze
        @removed = removed.freeze
        @changed = changed.freeze
        @moved = moved.freeze
        freeze
      end

      def empty?
        added.empty? && removed.empty? && changed.empty? && moved.empty?
      end
    end
  end
end
