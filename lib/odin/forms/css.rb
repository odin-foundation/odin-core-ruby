# frozen_string_literal: true

module Odin
  module Forms
    # Scoped CSS generation for the form HTML renderer.
    module Css
      module_function

      # Base stylesheet scoped under .odin-form.
      def generate_form_css
        [
          ".odin-form { position: relative; font-family: Helvetica, Arial, sans-serif; }",
          ".odin-form-page { position: relative; background: white; overflow: hidden; box-sizing: border-box; margin: 0 auto; }",
          ".odin-form-element { position: absolute; box-sizing: border-box; }",
          ".odin-form-label { display: block; font-size: 8pt; color: #666; margin-bottom: 1px; }",
          ".odin-form-input { width: 100%; height: 100%; box-sizing: border-box; border: 1px solid #999; padding: 2px 4px; font-family: inherit; font-size: inherit; background: transparent; }",
          ".odin-form-input:focus { outline: 2px solid #34A3F5; border-color: #34A3F5; }",
          ".odin-form-checkbox, .odin-form-radio { width: auto; height: auto; }",
          ".odin-form-select { width: 100%; height: 100%; }",
          ".odin-form-signature { border: none; border-bottom: 1px solid #000; background: transparent; }",
          ".odin-form-fieldset { border: none; padding: 0; margin: 0; position: absolute; }",
          ".odin-form-legend { font-size: 8pt; color: #666; }",
          ".odin-form-sr-only { position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip: rect(0,0,0,0); white-space: nowrap; border: 0; }",
          ".odin-form-skip:focus { position: static; width: auto; height: auto; clip: auto; overflow: visible; margin: 0; padding: 4px 8px; }",
        ].join("\n")
      end

      # @media print block optimising the form for printing.
      def generate_print_css
        [
          "@media print {",
          "  .odin-form-page { page-break-after: always; margin: 0; box-shadow: none; }",
          "  .odin-form-page:last-child { page-break-after: auto; }",
          "  .odin-form-input { border: none; border-bottom: 1px solid #000; background: transparent; }",
          "  .odin-form-skip { display: none; }",
          "  .odin-form-sr-only { display: none; }",
          "}",
        ].join("\n")
      end
    end
  end
end
