# frozen_string_literal: true

require "spec_helper"
require_relative "../../golden/golden_helper"

RSpec.describe Odin::Forms::Renderer do
  def render(odin, data = nil)
    form = Odin::Forms.parse_form(odin)
    Odin::Forms.render_form(form, data)
  end

  it "wraps the form with role, label, skip link, and styles" do
    html = render(<<~ODIN)
      {$}
      title = "My Form"
      {page[0]}
      {.text.t}
      content = "Hi"
    ODIN
    expect(html).to include(%(<form role="form" aria-label="My Form" class="odin-form">))
    expect(html).to include('href="#odin-form-content"')
    expect(html).to include("<style>")
    expect(html).to include(%(<div class="odin-form-page" id="odin-form-content" data-page="1"))
  end

  it "renders geometric SVG shapes with converted coordinates" do
    html = render(<<~ODIN)
      {$}
      title = "G"
      {$.page}
      width = #8.5
      height = #11
      unit = "inch"
      {page[0]}
      {.circle.seal}
      cx = #2
      cy = #2
      r = #0.75
      stroke = "#003366"
      stroke-width = #0.02
    ODIN
    expect(html).to include(%(<circle cx="192" cy="192" r="72" stroke="#003366" stroke-width="1.92" fill="none"/>))
  end

  it "renders a background image with the lowest z-index and data URI" do
    html = render(<<~ODIN)
      {$}
      title = "C"
      {page[0]}
      {.img.bg}
      x = #0
      y = #0
      w = #8.5
      h = #11
      src = ^png:iVBORw0KGgo=
      alt = "template"
      background = ?true
    ODIN
    expect(html).to include("z-index:0;")
    expect(html).to include("data:image/png;base64,iVBORw0KGgo=")
  end

  it "binds a field value from a data document" do
    form = Odin::Forms.parse_form(<<~ODIN)
      {$}
      title = "B"
      {page[0]}
      {.field.name}
      type = "text"
      x = #0
      y = #0
      w = #2
      h = #0.3
      label = "Name"
      bind = @user.name
    ODIN
    data = Odin.parse(%({user}\nname = "Jane"))
    html = Odin::Forms.render_form(form, data)
    expect(html).to include(%(value="Jane"))
  end

  it "marks the bound radio option as checked and leaves others unchecked" do
    form = Odin::Forms.parse_form(File.read(File.join(forms_fixtures_dir, "signature-radio.odin")))
    data = Odin.parse(%({applicant}\ngender = "F"))
    html = Odin::Forms.render_form(form, data)
    expect(html).to include(%(value="F" aria-label="Female" checked>))
    expect(html).not_to include(%(value="M" aria-label="Male" checked))
  end

  it "escapes HTML in text content" do
    html = render(<<~ODIN)
      {$}
      title = "E"
      {page[0]}
      {.text.t}
      content = "a < b & c"
    ODIN
    expect(html).to include("a &lt; b &amp; c")
  end

  describe "region overflow" do
    let(:form) { Odin::Forms.parse_form(File.read(File.join(forms_fixtures_dir, "page-template.odin"))) }

    it "renders a single page without data" do
      html = Odin::Forms.render_form(form)
      expect(html).to include(%(data-page="1"))
      expect(html).not_to include(%(data-page="2"))
    end

    it "generates a continuation page and interpolates page tokens when data overflows" do
      data = Odin.parse(
        %({policy}\n{.vehicles[0]}\nvin = "V0"\n{.vehicles[1]}\nvin = "V1"\n) +
        %({.vehicles[2]}\nvin = "V2"\n{.vehicles[3]}\nvin = "V3"\n{.vehicles[4]}\nvin = "V4")
      )
      html = Odin::Forms.render_form(form, data)
      expect(html).to include("Page 1 of 2")
      expect(html).to include("Page 2 of 2")
      expect(html).to include(%(value="V0"))
      expect(html).to include(%(value="V4"))
      expect(html).not_to include("{@odin.page}")
    end
  end

  def forms_fixtures_dir
    File.join(__dir__, "fixtures")
  end
end
