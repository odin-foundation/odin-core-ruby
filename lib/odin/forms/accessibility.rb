# frozen_string_literal: true

module Odin
  module Forms
    # Pure helpers for generating accessible markup and computing WCAG contrast.
    module Accessibility
      module_function

      # Unique, stable HTML element id for a field.
      def generate_field_id(element_name, page_index)
        "odin-field-#{page_index}-#{element_name}"
      end

      # A <label> associated with the given input id.
      def field_label_html(label, input_id)
        %(<label for="#{input_id}" class="odin-form-label">#{label}</label>)
      end

      # ARIA and id attributes for a field element.
      def field_aria_attrs(element, page_index)
        attrs = {
          "id" => generate_field_id(element.name, page_index),
          "aria-label" => element[:"aria-label"] || element[:label],
        }
        attrs["aria-required"] = "true" if element[:required]
        attrs
      end

      # Wrap content in a <fieldset>/<legend> for grouped controls.
      def field_group_html(_group_name, legend, content)
        %(<fieldset class="odin-form-fieldset">) +
          %(<legend class="odin-form-legend">#{legend}</legend>) +
          content +
          "</fieldset>"
      end

      # Skip-navigation link targeting the form content anchor.
      def skip_link_html(form_title)
        %(<a class="odin-form-sr-only odin-form-skip" href="#odin-form-content">) +
          "Skip to #{form_title}" +
          "</a>"
      end

      # Visually-hidden text that remains announced to screen readers.
      def sr_only_html(text)
        %(<span class="odin-form-sr-only">#{text}</span>)
      end

      # Field elements only, sorted by reading order (top-to-bottom, left-to-right).
      def tab_order_sort(elements)
        elements.select(&:field?).sort do |a, b|
          ay = a[:y] || 0
          by = b[:y] || 0
          if ay != by
            ay <=> by
          else
            (a[:x] || 0) <=> (b[:x] || 0)
          end
        end
      end

      # ── WCAG contrast ──────────────────────────────────────────────────────

      def contrast_ratio(fg, bg)
        l1 = relative_luminance(fg)
        l2 = relative_luminance(bg)
        lighter = [l1, l2].max
        darker = [l1, l2].min
        (lighter + 0.05) / (darker + 0.05)
      end

      def meets_contrast_aa(fg, bg, font_size)
        ratio = contrast_ratio(fg, bg)
        font_size >= 18 ? ratio >= 3.0 : ratio >= 4.5
      end

      def linearize(channel)
        srgb = channel / 255.0
        srgb <= 0.04045 ? srgb / 12.92 : (((srgb + 0.055) / 1.055)**2.4)
      end

      def parse_hex(hex)
        clean = hex.start_with?("#") ? hex[1..] : hex
        raise ArgumentError, %(Invalid hex colour: "#{hex}") unless clean.match?(/\A[0-9a-fA-F]{6}\z/)

        [clean[0, 2].to_i(16), clean[2, 2].to_i(16), clean[4, 2].to_i(16)]
      end

      def relative_luminance(hex)
        r, g, b = parse_hex(hex)
        (0.2126 * linearize(r)) + (0.7152 * linearize(g)) + (0.0722 * linearize(b))
      end
    end
  end
end
