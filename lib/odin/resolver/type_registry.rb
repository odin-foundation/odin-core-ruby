# frozen_string_literal: true

module Odin
  module Resolver
    # Namespaced type registry for import resolution.
    class TypeRegistry
      def initialize
        @local_types = {}
        @namespaces = {}
      end

      # Register all types from a schema under an optional namespace (import alias).
      def register_all(types, namespace = nil)
        if namespace
          ns_map = (@namespaces[namespace] ||= {})
          types.each { |name, type_def| ns_map[name] = type_def }
        else
          types.each { |name, type_def| @local_types[name] = type_def }
        end
      end

      # Look up a type by name: local first, then dot-namespaced "alias.name",
      # then any namespace for an unqualified name.
      def lookup(name)
        return @local_types[name] if @local_types.key?(name)

        if (dot = name.index("."))
          ns = name[0...dot]
          type_name = name[(dot + 1)..]
          ns_map = @namespaces[ns]
          return ns_map[type_name] if ns_map&.key?(type_name)
        end

        @namespaces.each_value do |ns_map|
          return ns_map[name] if ns_map.key?(name)
        end
        nil
      end

      def has?(name)
        !lookup(name).nil?
      end

      # All type names, namespaced names rendered as "alias.name".
      def all_type_names
        names = @local_types.keys.dup
        @namespaces.each do |ns, ns_map|
          ns_map.each_key { |n| names << "#{ns}.#{n}" }
        end
        names
      end
    end
  end
end
