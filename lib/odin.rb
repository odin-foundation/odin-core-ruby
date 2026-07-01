# frozen_string_literal: true

require_relative "odin/version"
require_relative "odin/types"
require_relative "odin/utils/path_utils"
require_relative "odin/utils/security_limits"
require_relative "odin/parsing/token_type"
require_relative "odin/parsing/token"
require_relative "odin/parsing/tokenizer"
require_relative "odin/parsing/value_parser"
require_relative "odin/parsing/parser"
require_relative "odin/utils/format_utils"
require_relative "odin/serialization/stringify"
require_relative "odin/serialization/canonicalize"
require_relative "odin/types/diff"
require_relative "odin/diff/differ"
require_relative "odin/diff/patcher"
require_relative "odin/types/schema"
require_relative "odin/validation/redos_protection"
require_relative "odin/validation/format_validators"
require_relative "odin/validation/schema_parser"
require_relative "odin/validation/invariant_evaluator"
require_relative "odin/validation/schema_definition_validator"
require_relative "odin/validation/validator"
require_relative "odin/validation/schema_serializer"
require_relative "odin/resolver/type_registry"
require_relative "odin/resolver/import_resolver"
require_relative "odin/transform/source_parsers"
require_relative "odin/transform/format_exporters"
require_relative "odin/transform/transform_types"
require_relative "odin/transform/transform_expr"
require_relative "odin/transform/verb_context"
require_relative "odin/transform/transform_parser"
require_relative "odin/transform/transform_engine"
require_relative "odin/transform/verbs/numeric_verbs"
require_relative "odin/transform/verbs/collection_verbs"
require_relative "odin/transform/verbs/datetime_verbs"
require_relative "odin/transform/verbs/financial_verbs"
require_relative "odin/transform/verbs/aggregation_verbs"
require_relative "odin/transform/verbs/object_verbs"
require_relative "odin/transform/verbs/geo_verbs"
require_relative "odin/transform/verbs/extra_verbs"
require_relative "odin/export"
require_relative "odin/forms"

module Odin
  class << self
    def parse(text, options = nil)
      text = text.encode("UTF-8") if text.is_a?(String) && text.encoding != Encoding::UTF_8
      Parsing::OdinParser.new.parse(text, options)
    end

    # Parse a chained document (one or more documents separated by ---) into
    # the full list of documents. A single document yields a one-element array.
    def parse_documents(text, options = nil)
      result = parse(text, options)
      result.respond_to?(:documents) ? result.documents : [result]
    end

    # Collapse a chained ODIN document into its computed current state.
    #
    # Later documents overlay earlier ones, a repeated path replaces the earlier
    # value, +field = ~+ removes the field and its descendants, and +field[] = ~+
    # clears the array. The result carries the final document's metadata.
    #
    # Accepts chained ODIN text or a pre-parsed list of documents.
    def collapse_chain(input, options = nil)
      docs = input.is_a?(Array) ? input : parse_documents(input, options)
      collapse_documents(docs)
    end

    private

    def collapse_documents(docs)
      assignments = {}
      modifiers = {}
      metadata = {}

      docs.each do |doc|
        metadata = doc.metadata.dup

        doc.paths.each do |path|
          value = doc.get(path)
          next if value.nil?

          if value.type == :null
            if path.end_with?("[]")
              clear_array(assignments, modifiers, path[0...-2])
            else
              remove_path(assignments, modifiers, path)
            end
            next
          end

          assignments[path] = value
          mods = doc.modifiers_for(path)
          if mods
            modifiers[path] = mods
          else
            modifiers.delete(path)
          end
        end
      end

      Types::OdinDocument.new(
        assignments: assignments,
        metadata: metadata,
        modifiers: modifiers,
        comments: {}
      )
    end

    # Remove a path and any nested descendants from the working maps.
    def remove_path(assignments, modifiers, path)
      assignments.keys.each do |key|
        if key == path || key.start_with?("#{path}.") || key.start_with?("#{path}[")
          assignments.delete(key)
          modifiers.delete(key)
        end
      end
    end

    # Clear all indexed elements of an array path from the working maps.
    def clear_array(assignments, modifiers, array_path)
      prefix = "#{array_path}["
      assignments.keys.each do |key|
        if key.start_with?(prefix)
          assignments.delete(key)
          modifiers.delete(key)
        end
      end
    end

    public

    def stringify(doc, options = {})
      Serialization::Stringify.new(options).stringify(doc)
    end

    def canonicalize(doc)
      Serialization::Canonicalize.new.canonicalize(doc)
    end

    def parse_schema(text)
      text = text.encode("UTF-8") if text.is_a?(String) && text.encoding != Encoding::UTF_8
      Validation::SchemaParser.new.parse_schema(text)
    end

    def validate(doc, schema, options = {}, registry = nil)
      Validation::Validator.new.validate(doc, schema, options, registry)
    end

    # Resolve a schema's imports into a type registry, then validate the document.
    def validate_with_imports(doc, schema, base_path, options = {}, resolver_options = {})
      _flattened, registry = Resolver::ImportResolver.new(**resolver_options)
                                                     .resolve_with_registry(schema, base_path: base_path)
      validate(doc, schema, options, registry)
    end

    def diff(a, b)
      Diff::Differ.new.compute_diff(a, b)
    end

    def patch(doc, diff_result)
      Diff::Patcher.new.apply_patch(doc, diff_result)
    end

    def builder
      Types::OdinDocumentBuilder.new
    end

    def parse_transform(text)
      text = text.encode("UTF-8") if text.is_a?(String) && text.encoding != Encoding::UTF_8
      Transform::TransformParser.new.parse(text)
    end

    def execute_transform(transform_def, source, import_resolver: nil,
                          max_transform_fuel: nil, transform_timeout_ms: nil, max_expression_depth: nil)
      Transform::TransformEngine.new.execute(
        transform_def, source, import_resolver: import_resolver,
        max_transform_fuel: max_transform_fuel,
        transform_timeout_ms: transform_timeout_ms,
        max_expression_depth: max_expression_depth
      )
    end

    def transform(transform_text, source)
      td = parse_transform(transform_text)
      execute_transform(td, source)
    end
  end
end
