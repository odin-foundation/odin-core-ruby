# frozen_string_literal: true

module Odin
  module Types
    class OrderedMap
      include Enumerable

      def initialize(hash = {})
        @store = hash.dup
      end

      def [](key)
        @store[key]
      end

      def []=(key, value)
        @store[key] = value
      end

      def delete(key)
        @store.delete(key)
      end

      def key?(key)
        @store.key?(key)
      end
      alias has_key? key?
      alias include? key?

      def keys
        @store.keys
      end

      def values
        @store.values
      end

      def size
        @store.size
      end
      alias length size

      def empty?
        @store.empty?
      end

      def each(&block)
        @store.each(&block)
      end

      def to_h
        @store.dup
      end

      def ==(other)
        case other
        when OrderedMap then @store == other.to_h
        when Hash then @store == other
        else false
        end
      end

      def freeze
        @store.freeze
        super
      end

      def dup
        self.class.new(@store)
      end

      def merge(other_hash)
        result = dup
        other_hash.each { |k, v| result[k] = v }
        result
      end
    end
  end
end
