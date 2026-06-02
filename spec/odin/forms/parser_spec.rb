# frozen_string_literal: true

require "spec_helper"
require_relative "../../golden/golden_helper"

RSpec.describe Odin::Forms::Parser do
  def parse(text)
    Odin::Forms.parse_form(text)
  end

  describe "metadata and page defaults" do
    it "reads title, id, lang, version, dimensions, unit, and margins" do
      form = parse(<<~ODIN)
        {$}
        odin = "1.0.0"
        forms = "1.0.0"
        title = "Demo"
        id = "demo_form"
        lang = "es"

        {$.page}
        width = #8.5
        height = #11
        unit = "inch"
        margin.top = #0.5
        margin.left = #0.75
      ODIN

      expect(form.metadata[:title]).to eq("Demo")
      expect(form.metadata[:id]).to eq("demo_form")
      expect(form.metadata[:lang]).to eq("es")
      expect(form.metadata[:version]).to eq("1.0.0")
      expect(form.page_defaults[:width]).to eq(8.5)
      expect(form.page_defaults[:height]).to eq(11)
      expect(form.page_defaults[:unit]).to eq("inch")
      expect(form.page_defaults[:margin]).to eq({ top: 0.5, left: 0.75 })
    end

    it "falls back to inch for an unknown unit" do
      form = parse(<<~ODIN)
        {$}
        title = "U"
        {$.page}
        width = #210
        height = #297
        unit = "parsec"
      ODIN
      expect(form.page_defaults[:unit]).to eq("inch")
    end

    it "reads screen scale" do
      form = parse(<<~ODIN)
        {$}
        title = "S"
        {$.screen}
        scale = #1.5
        {page[0]}
        {.text.t}
        content = "x"
      ODIN
      expect(form.screen).to eq({ scale: 1.5 })
    end
  end

  describe "geometric elements" do
    it "parses stroke and fill mixins" do
      form = parse(<<~ODIN)
        {$}
        title = "G"
        {page[0]}
        {.circle.seal}
        cx = #2
        cy = #2
        r = #0.75
        stroke = "#003366"
        stroke-width = #0.02
        fill = "#e6f0ff"
      ODIN
      seal = form.pages[0].elements.first
      expect(seal.type).to eq("circle")
      expect(seal[:cx]).to eq(2)
      expect(seal[:r]).to eq(0.75)
      expect(seal[:stroke]).to eq("#003366")
      expect(seal[:"stroke-width"]).to eq(0.02)
      expect(seal[:fill]).to eq("#e6f0ff")
    end
  end

  describe "field elements" do
    it "parses text field inline value and input type" do
      form = parse(<<~ODIN)
        {$}
        title = "F"
        {page[0]}
        {.field.email}
        type = "text"
        x = #0
        y = #0
        w = #2
        h = #0.3
        label = "Email"
        value = "a@b.com"
        inputType = "email"
        bind = @user.email
      ODIN
      el = form.pages[0].elements.first
      expect(el.type).to eq("field.text")
      expect(el[:value]).to eq("a@b.com")
      expect(el[:inputType]).to eq("email")
      expect(el[:bind]).to eq("@user.email")
    end

    it "parses a select with a tabular options array" do
      form = parse(<<~ODIN)
        {$}
        title = "F"
        {page[0]}
        {.field.state}
        type = "select"
        label = "State"
        selected = "TX"
        bind = @addr.state
        {.field.state.options[] : ~}
        "AL"
        "TX"
      ODIN
      el = form.pages[0].elements.first
      expect(el.type).to eq("field.select")
      expect(el[:options]).to eq(%w[AL TX])
      expect(el[:selected]).to eq("TX")
    end

    it "parses date values preserving the raw form" do
      form = parse(<<~ODIN)
        {$}
        title = "F"
        {page[0]}
        {.field.dob}
        type = "date"
        label = "DOB"
        value = 1985-03-15
        min = 1900-01-01
        bind = @p.dob
      ODIN
      el = form.pages[0].elements.first
      expect(el[:value]).to eq("1985-03-15")
      expect(el[:min]).to eq("1900-01-01")
    end

    it "reconstructs a binary signature literal" do
      form = parse(<<~ODIN)
        {$}
        title = "F"
        {page[0]}
        {.field.sig}
        type = "signature"
        label = "Sign"
        value = ^png:iVBORw0KGgo=
        bind = @p.sig
      ODIN
      el = form.pages[0].elements.first
      expect(el.type).to eq("field.signature")
      expect(el[:value]).to eq("^png:iVBORw0KGgo=")
    end
  end

  describe "i18n labels" do
    it "resolves an @\\$.i18n reference to the dictionary value" do
      form = parse(<<~ODIN)
        {$}
        title = "I"
        {$.i18n}
        en.name = "Full Legal Name"
        {page[0]}
        {.field.name}
        type = "text"
        label = @$.i18n.en.name
        bind = @p.name
      ODIN
      expect(form.i18n["en.name"]).to eq("Full Legal Name")
      expect(form.pages[0].elements.first[:label]).to eq("Full Legal Name")
    end
  end

  describe "regions and templates" do
    let(:form) { parse(File.read(File.join(forms_fixtures_dir, "page-template.odin"))) }

    it "parses the bound region with children and overflow target" do
      region = form.pages[0].elements.find { |e| e.name == "vehicles" }
      expect(region.type).to eq("region")
      expect(region[:bind]).to eq("@policy.vehicles")
      expect(region[:max]).to eq(3)
      expect(region[:overflow]).to eq("@tpl_vehicles_continued")
      expect(region[:children].length).to eq(1)
      expect(region[:children].first.type).to eq("field.text")
    end

    it "parses the page template metadata" do
      tpl = form.templates["tpl_vehicles_continued"]
      expect(tpl.page_template).to be(true)
      expect(tpl.continues).to eq("region.vehicles")
      expect(tpl.form_id).to eq("PA (Cont)")
      expect(tpl.elements.map(&:type)).to eq(%w[text region])
    end
  end

  def forms_fixtures_dir
    File.join(__dir__, "fixtures")
  end
end
