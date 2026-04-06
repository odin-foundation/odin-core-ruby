# frozen_string_literal: true

require "set"

module Odin
  module Resolver
    class ImportResolver
      MAX_IMPORT_DEPTH = 32
      MAX_TOTAL_IMPORTS = 1000

      def initialize(loader: nil)
        @loader = loader || method(:default_loader)
        @resolved_paths = Set.new
        @total_loaded = 0
      end

      # Resolve all imports in a schema, returning a flattened schema
      def resolve(schema, base_path: ".")
        return schema if schema.imports.empty?

        imported_schemas = []
        schema.imports.each do |imp|
          resolve_import(imp, base_path, imported_schemas, depth: 0)
        end

        flatten(schema, imported_schemas)
      end

      private

      def resolve_import(imp, base_path, collected, depth:)
        if depth >= MAX_IMPORT_DEPTH
          raise Errors::OdinError.new(
            Errors::ValidationErrorCode::CIRCULAR_REFERENCE,
            "Maximum import depth (#{MAX_IMPORT_DEPTH}) exceeded"
          )
        end

        if @total_loaded >= MAX_TOTAL_IMPORTS
          raise Errors::OdinError.new(
            Errors::ValidationErrorCode::CIRCULAR_REFERENCE,
            "Maximum total imports (#{MAX_TOTAL_IMPORTS}) exceeded"
          )
        end

        abs_path = resolve_path(base_path, imp.path)

        if @resolved_paths.include?(abs_path)
          raise Errors::OdinError.new(
            Errors::ValidationErrorCode::CIRCULAR_REFERENCE,
            "Circular import detected: #{abs_path}"
          )
        end

        @resolved_paths.add(abs_path)
        @total_loaded += 1

        text = @loader.call(abs_path)
        imported_schema = Validation::SchemaParser.new.parse_schema(text)

        # Recursively resolve nested imports
        unless imported_schema.imports.empty?
          import_dir = File.dirname(abs_path)
          imported_schema.imports.each do |nested_imp|
            resolve_import(nested_imp, import_dir, collected, depth: depth + 1)
          end
        end

        collected << { schema: imported_schema, alias_name: imp.alias_name, path: abs_path }
      end

      def resolve_path(base_path, import_path)
        if import_path.start_with?("/") || import_path.match?(/\A[a-zA-Z]:/)
          import_path
        elsif import_path.start_with?("./") || import_path.start_with?("../")
          File.expand_path(import_path, base_path)
        else
          File.expand_path(import_path, base_path)
        end
      end

      def flatten(schema, imported)
        merged_types = {}
        merged_fields = {}
        merged_arrays = {}
        merged_constraints = {}

        # Imported schemas first (main overrides)
        imported.each do |entry|
          imp_schema = entry[:schema]
          alias_name = entry[:alias_name]

          imp_schema.types.each do |name, type_def|
            qualified = alias_name ? "#{alias_name}.#{name}" : name
            merged_types[qualified] = type_def
            # Also register unqualified for direct access
            merged_types[name] = type_def unless alias_name
          end

          imp_schema.fields.each do |path, field|
            qualified = alias_name ? "#{alias_name}.#{path}" : path
            merged_fields[qualified] = field
          end

          imp_schema.arrays.each do |path, arr|
            qualified = alias_name ? "#{alias_name}.#{path}" : path
            merged_arrays[qualified] = arr
          end

          imp_schema.object_constraints.each do |scope, constraints|
            qualified = alias_name ? "#{alias_name}.#{scope}" : scope
            merged_constraints[qualified] = constraints
          end
        end

        # Main schema overrides
        merged_types.merge!(schema.types)
        merged_fields.merge!(schema.fields)
        merged_arrays.merge!(schema.arrays)
        merged_constraints.merge!(schema.object_constraints)

        Types::OdinSchema.new(
          metadata: schema.metadata,
          types: merged_types,
          fields: merged_fields,
          arrays: merged_arrays,
          imports: [], # resolved
          object_constraints: merged_constraints
        )
      end

      def default_loader(path)
        File.read(path, encoding: "UTF-8")
      end
    end
  end
end
