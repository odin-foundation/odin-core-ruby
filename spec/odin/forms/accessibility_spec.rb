# frozen_string_literal: true

require "spec_helper"

RSpec.describe Odin::Forms::Accessibility do
  describe ".generate_field_id" do
    it "builds a page-scoped id" do
      expect(described_class.generate_field_id("ssn", 0)).to eq("odin-field-0-ssn")
      expect(described_class.generate_field_id("name", 2)).to eq("odin-field-2-name")
    end
  end

  describe ".field_label_html" do
    it "associates the label with the input id" do
      html = described_class.field_label_html("Full Name", "odin-field-0-name")
      expect(html).to eq(%(<label for="odin-field-0-name" class="odin-form-label">Full Name</label>))
    end
  end

  describe ".field_aria_attrs" do
    let(:element) { Odin::Forms::FormElement.new(name: "name", label: "Full Name", required: true) }

    it "derives id and aria-label from the element" do
      attrs = described_class.field_aria_attrs(element, 0)
      expect(attrs["id"]).to eq("odin-field-0-name")
      expect(attrs["aria-label"]).to eq("Full Name")
      expect(attrs["aria-required"]).to eq("true")
    end

    it "prefers an explicit aria-label override and omits aria-required when not required" do
      el = Odin::Forms::FormElement.new(name: "n", label: "Label", :"aria-label" => "Override")
      attrs = described_class.field_aria_attrs(el, 1)
      expect(attrs["aria-label"]).to eq("Override")
      expect(attrs).not_to have_key("aria-required")
    end
  end

  describe ".field_group_html" do
    it "wraps content in a fieldset with legend" do
      html = described_class.field_group_html("gender", "Gender", "<input>")
      expect(html).to eq(
        %(<fieldset class="odin-form-fieldset"><legend class="odin-form-legend">Gender</legend><input></fieldset>)
      )
    end
  end

  describe ".skip_link_html" do
    it "targets the form content anchor" do
      html = described_class.skip_link_html("Application")
      expect(html).to include('href="#odin-form-content"')
      expect(html).to include("Skip to Application")
    end
  end

  describe ".tab_order_sort" do
    it "returns only fields in reading order" do
      a = Odin::Forms::FormElement.new(type: "field.text", name: "a", x: 1, y: 2)
      b = Odin::Forms::FormElement.new(type: "field.text", name: "b", x: 0, y: 1)
      c = Odin::Forms::FormElement.new(type: "rect", name: "c", x: 0, y: 0)
      d = Odin::Forms::FormElement.new(type: "field.text", name: "d", x: 0, y: 2)

      sorted = described_class.tab_order_sort([a, b, c, d])
      expect(sorted.map(&:name)).to eq(%w[b d a])
    end
  end

  describe ".contrast_ratio" do
    it "computes the maximum ratio for black on white" do
      expect(described_class.contrast_ratio("#000000", "#FFFFFF")).to be_within(0.01).of(21.0)
    end

    it "returns 1.0 for identical colours" do
      expect(described_class.contrast_ratio("#123456", "#123456")).to be_within(1e-9).of(1.0)
    end

    it "raises on malformed hex" do
      expect { described_class.contrast_ratio("#xyz", "#FFFFFF") }.to raise_error(ArgumentError)
    end
  end

  describe ".meets_contrast_aa" do
    it "passes black on white for normal and large text" do
      expect(described_class.meets_contrast_aa("#000000", "#FFFFFF", 12)).to be(true)
      expect(described_class.meets_contrast_aa("#000000", "#FFFFFF", 24)).to be(true)
    end

    it "fails low-contrast normal text" do
      expect(described_class.meets_contrast_aa("#777777", "#888888", 12)).to be(false)
    end
  end
end
