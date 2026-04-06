# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe "Format Output Integration" do
  let(:parser) { Odin::Transform::TransformParser.new }
  let(:engine) { Odin::Transform::TransformEngine.new }

  it "produces valid JSON for json target" do
    transform_text = <<~ODIN
      {$}
      odin = "1.0.0"
      transform = "1.0.0"
      direction = "json->json"
      target.format = "json"

      {}
      name = @.name
      age = @.age
    ODIN

    transform_def = parser.parse(transform_text)
    result = engine.execute(transform_def, { "name" => "Alice", "age" => 30 })

    expect(result.formatted).not_to be_nil
    parsed = JSON.parse(result.formatted)
    expect(parsed["name"]).to eq("Alice")
    expect(parsed["age"]).to eq(30)
  end

  it "produces valid ODIN for odin target" do
    transform_text = <<~ODIN
      {$}
      odin = "1.0.0"
      transform = "1.0.0"
      direction = "json->odin"
      target.format = "odin"

      {}
      name = @.name
      active = @.active
      count = @.count
    ODIN

    transform_def = parser.parse(transform_text)
    result = engine.execute(transform_def, { "name" => "Bob", "active" => true, "count" => 42 })

    expect(result.formatted).not_to be_nil
    expect(result.formatted).to include("name =")
    expect(result.formatted).to include("active =")
    expect(result.formatted).to include("count =")
  end

  it "produces valid CSV for csv target" do
    transform_text = <<~ODIN
      {$}
      odin = "1.0.0"
      transform = "1.0.0"
      direction = "json->csv"
      target.format = "csv"

      {rows[]}
      _loop = "@.items"
      name = @.name
      price = @.price
    ODIN

    transform_def = parser.parse(transform_text)
    result = engine.execute(transform_def, {
      "items" => [
        { "name" => "Widget", "price" => 9.99 },
        { "name" => "Gadget", "price" => 19.99 }
      ]
    })

    expect(result.formatted).not_to be_nil
    lines = result.formatted.strip.split("\n")
    expect(lines.size).to be >= 2 # header + at least 1 data row
  end

  it "produces valid XML for xml target" do
    transform_text = <<~ODIN
      {$}
      odin = "1.0.0"
      transform = "1.0.0"
      direction = "json->xml"
      target.format = "xml"

      {person}
      name = @.name
      age = @.age
    ODIN

    transform_def = parser.parse(transform_text)
    result = engine.execute(transform_def, { "name" => "Charlie", "age" => 25 })

    expect(result.formatted).not_to be_nil
    expect(result.formatted).to include("<?xml")
    expect(result.formatted).to include("<name>Charlie</name>")
  end
end
