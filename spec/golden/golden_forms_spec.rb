# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "golden_helper"

RSpec.describe "Golden Forms Tests" do
  FORMS_DIR = File.join(find_golden_dir, "forms")

  def self.load_forms_tests
    manifest_path = File.join(FORMS_DIR, "manifest.json")
    return [] unless File.exist?(manifest_path)

    suite = JSON.parse(File.read(manifest_path))
    (suite["tests"] || []).map { |t| [t["id"], t] }
  end

  def form_text(test_case)
    File.read(File.join(FORMS_DIR, test_case["formFile"]))
  end

  def page_for(form, key)
    return form.templates[key.to_s.sub("template:", "")] if key.to_s.start_with?("template:")

    idx = key.to_s.sub("page", "").to_i
    form.pages[idx]
  end

  def element_named(container, name)
    container.elements.find { |e| e.name == name }
  end

  load_forms_tests.each do |id, test_case|
    it "golden forms: #{id}" do
      form = Odin::Forms.parse_form(form_text(test_case))

      assert_parse(form, test_case["expectParse"]) if test_case["expectParse"]

      if test_case["renderContains"] || test_case["renderNotContains"]
        data = test_case["renderData"] ? Odin.parse(test_case["renderData"]) : nil
        html = Odin::Forms.render_form(form, data)
        (test_case["renderContains"] || []).each do |needle|
          expect(html).to include(needle), "Expected render to contain: #{needle}"
        end
        (test_case["renderNotContains"] || []).each do |needle|
          expect(html).not_to include(needle), "Expected render to omit: #{needle}"
        end
      end
    end
  end

  private

  def assert_parse(form, expect)
    expect(form.pages.length).to eq(expect["pages"]) if expect.key?("pages")
    assert_margins(form, expect["margins"]) if expect["margins"]
    assert_templates(form, expect["templates"]) if expect["templates"]

    expect.each do |key, value|
      next unless key.match?(/\Apage\d+\z/)

      idx = key.sub("page", "").to_i
      assert_page(form.pages[idx], value)
    end
  end

  def assert_margins(form, margins)
    actual = form.page_defaults && form.page_defaults[:margin]
    expect(actual).not_to be_nil, "Expected page margins"
    margins.each do |side, val|
      expect(actual[side.to_sym]).to eq(val), "margin.#{side}"
    end
  end

  def assert_templates(form, templates)
    expect(form.templates).not_to be_nil, "Expected templates"
    templates.each do |tpl_name, spec|
      tpl = form.templates[tpl_name]
      expect(tpl).not_to be_nil, "Missing template #{tpl_name}"
      expect(tpl.page_template).to eq(spec["pageTemplate"]) if spec.key?("pageTemplate")
      expect(tpl.continues).to eq(spec["continues"]) if spec.key?("continues")
      expect(tpl.form_id).to eq(spec["formId"]) if spec.key?("formId")
      expect(tpl.elements.map(&:type)).to eq(spec["elementTypes"]) if spec.key?("elementTypes")
    end
  end

  def assert_page(page, spec)
    expect(page).not_to be_nil, "Missing page"
    expect(page.elements.map(&:type)).to eq(spec["elementTypes"]) if spec.key?("elementTypes")

    (spec["elements"] || {}).each do |name, props|
      el = page.elements.find { |e| e.name == name }
      expect(el).not_to be_nil, "Missing element #{name}"
      assert_element(el, props, name)
    end
  end

  def assert_element(el, props, name)
    props.each do |key, expected|
      actual =
        case key
        when "type" then el.type
        when "childCount" then (el[:children] || []).length
        else el[normalize_key(key)]
        end
      expect(actual).to eq(expected), "#{name}.#{key}: expected #{expected.inspect}, got #{actual.inspect}"
    end
  end

  def normalize_key(key)
    key.to_sym
  end
end
