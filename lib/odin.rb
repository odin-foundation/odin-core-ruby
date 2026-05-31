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
require_relative "odin/validation/validator"
require_relative "odin/validation/schema_serializer"
require_relative "odin/resolver/type_registry"
require_relative "odin/resolver/import_resolver"
require_relative "odin/transform/source_parsers"
require_relative "odin/transform/format_exporters"
require_relative "odin/transform/transform_types"
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
require_relative "odin/export"

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

    def execute_transform(transform_def, source)
      Transform::TransformEngine.new.execute(transform_def, source)
    end

    def transform(transform_text, source)
      td = parse_transform(transform_text)
      execute_transform(td, source)
    end
  end
end
