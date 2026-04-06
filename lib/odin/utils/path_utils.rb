# frozen_string_literal: true

module Odin
  module Utils
    module PathUtils
      def self.build(*segments)
        segments.map(&:to_s).reject(&:empty?).join(".")
      end

      def self.split(path)
        path.scan(/[^.\[\]]+|\[\d+\]/)
      end

      def self.parent(path)
        idx = path.rindex(".")
        idx ? path[0...idx] : nil
      end

      def self.leaf(path)
        idx = path.rindex(".")
        idx ? path[(idx + 1)..] : path
      end
    end
  end
end
