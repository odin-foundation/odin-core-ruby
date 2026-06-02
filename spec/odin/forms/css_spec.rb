# frozen_string_literal: true

require "spec_helper"

RSpec.describe Odin::Forms::Css do
  describe ".generate_form_css" do
    let(:css) { described_class.generate_form_css }

    it "scopes every rule under .odin-form" do
      css.each_line do |line|
        line = line.strip
        next if line.empty?

        expect(line).to start_with(".odin-form")
      end
    end

    it "includes the core element and field classes" do
      expect(css).to include(".odin-form-page")
      expect(css).to include(".odin-form-input")
      expect(css).to include(".odin-form-sr-only")
    end

    it "is exposed through the module facade" do
      expect(Odin::Forms.generate_form_css).to eq(css)
    end
  end

  describe ".generate_print_css" do
    let(:css) { described_class.generate_print_css }

    it "emits a @media print block with page-break rules" do
      expect(css).to include("@media print {")
      expect(css).to include("page-break-after: always;")
      expect(css).to include(".odin-form-skip { display: none; }")
    end

    it "is exposed through the module facade" do
      expect(Odin::Forms.generate_print_css).to eq(css)
    end
  end
end
