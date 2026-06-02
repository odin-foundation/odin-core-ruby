# frozen_string_literal: true

require_relative "forms/types"
require_relative "forms/units"
require_relative "forms/accessibility"
require_relative "forms/css"
require_relative "forms/parser"
require_relative "forms/renderer"

module Odin
  # ODIN Forms — parse and render declarative form definitions.
  module Forms
    class << self
      # Parse ODIN forms text into a typed OdinForm.
      def parse_form(text)
        text = text.encode("UTF-8") if text.is_a?(String) && text.encoding != Encoding::UTF_8
        Parser.new.parse(text)
      end

      # Render an OdinForm to a complete HTML string. +data+ is an optional
      # OdinDocument bound to field values; +options+ accepts :className.
      def render_form(form, data = nil, options = nil)
        Renderer.new.render(form, data, options)
      end

      def generate_form_css
        Css.generate_form_css
      end

      def generate_print_css
        Css.generate_print_css
      end

      def to_pixels(value, unit)
        Units.to_pixels(value, unit)
      end

      def from_pixels(px, unit)
        Units.from_pixels(px, unit)
      end

      def generate_field_id(element_name, page_index)
        Accessibility.generate_field_id(element_name, page_index)
      end

      def contrast_ratio(fg, bg)
        Accessibility.contrast_ratio(fg, bg)
      end

      def meets_contrast_aa(fg, bg, font_size)
        Accessibility.meets_contrast_aa(fg, bg, font_size)
      end
    end
  end
end
