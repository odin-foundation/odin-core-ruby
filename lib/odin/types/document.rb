# frozen_string_literal: true

module Odin
  module Types
    class OdinDocument
      def initialize(assignments:, metadata:, modifiers:, comments:)
        @assignments = assignments.freeze
        @metadata = metadata.freeze
        @modifiers = modifiers.freeze
        @comments = comments.freeze
        freeze
      end

      def get(path)
        @assignments[path]
      end

      def [](path)
        get(path)
      end

      def paths
        @assignments.keys
      end

      def include?(path)
        @assignments.key?(path)
      end
      alias has_path? include?

      def size
        @assignments.size
      end
      alias length size

      def assignments
        @assignments
      end

      def metadata
        @metadata
      end

      def metadata_value(key)
        @metadata[key]
      end

      def modifiers_for(path)
        @modifiers[path]
      end

      def all_modifiers
        @modifiers
      end

      def comment_for(path)
        @comments[path]
      end

      def all_comments
        @comments
      end

      def empty?
        @assignments.empty? && @metadata.empty?
      end

      def each_assignment(&block)
        @assignments.each(&block)
      end

      def each_metadata(&block)
        @metadata.each(&block)
      end

      def ==(other)
        other.is_a?(OdinDocument) &&
          assignments == other.assignments &&
          metadata == other.metadata
      end
      alias eql? ==

      def hash
        [assignments, metadata].hash
      end

      def self.empty
        new(assignments: {}, metadata: {}, modifiers: {}, comments: {})
      end
    end
  end
end
