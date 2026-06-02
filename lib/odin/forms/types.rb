# frozen_string_literal: true

module Odin
  module Forms
    # Element type discriminators for form elements.
    module ElementType
      LINE = "line"
      RECT = "rect"
      CIRCLE = "circle"
      ELLIPSE = "ellipse"
      POLYGON = "polygon"
      POLYLINE = "polyline"
      PATH = "path"
      TEXT = "text"
      IMG = "img"
      BARCODE = "barcode"
      FIELD_TEXT = "field.text"
      FIELD_CHECKBOX = "field.checkbox"
      FIELD_RADIO = "field.radio"
      FIELD_SELECT = "field.select"
      FIELD_MULTISELECT = "field.multiselect"
      FIELD_DATE = "field.date"
      FIELD_SIGNATURE = "field.signature"
      REGION = "region"

      FIELD_TYPES = [
        FIELD_TEXT, FIELD_CHECKBOX, FIELD_RADIO, FIELD_SELECT,
        FIELD_MULTISELECT, FIELD_DATE, FIELD_SIGNATURE
      ].freeze

      def self.field?(type)
        FIELD_TYPES.include?(type)
      end
    end

    # A single form element. Backed by a property hash so optional attributes are
    # present only when set in the source document.
    class FormElement
      attr_reader :props

      def initialize(props)
        @props = props
      end

      def type
        @props[:type]
      end

      def name
        @props[:name]
      end

      def [](key)
        @props[key]
      end

      def key?(key)
        @props.key?(key)
      end

      def field?
        ElementType.field?(type)
      end
    end

    # An ordered list of elements forming one page.
    class FormPage
      attr_reader :elements

      def initialize(elements)
        @elements = elements
      end
    end

    # A page template instantiated for region overflow continuation pages.
    class PageTemplate
      attr_reader :name, :page_template, :continues, :form_id, :elements

      def initialize(name:, page_template:, continues:, form_id:, elements:)
        @name = name
        @page_template = page_template
        @continues = continues
        @form_id = form_id
        @elements = elements
      end
    end

    # Root parsed form document.
    class OdinForm
      attr_reader :metadata, :page_defaults, :screen, :i18n, :pages, :templates

      def initialize(metadata:, page_defaults:, screen:, i18n:, pages:, templates:)
        @metadata = metadata
        @page_defaults = page_defaults
        @screen = screen
        @i18n = i18n
        @pages = pages
        @templates = templates
      end
    end
  end
end
