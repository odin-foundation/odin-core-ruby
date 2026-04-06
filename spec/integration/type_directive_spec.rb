# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe "Type Directive Integration" do
  let(:parser) { Odin::Transform::TransformParser.new }
  let(:engine) { Odin::Transform::TransformEngine.new }

  it "applies :type integer directive" do
    transform_text = <<~ODIN
      {$}
      odin = "1.0.0"
      transform = "1.0.0"
      direction = "json->json"
      target.format = "json"

      {}
      value = @.value :type integer
    ODIN

    transform_def = parser.parse(transform_text)
    result = engine.execute(transform_def, { "value" => 3.14 })

    expect(result.output["value"]).to eq(3)
  end

  it "applies :type number directive" do
    transform_text = <<~ODIN
      {$}
      odin = "1.0.0"
      transform = "1.0.0"
      direction = "json->json"
      target.format = "json"

      {}
      value = @.value :type number
    ODIN

    transform_def = parser.parse(transform_text)
    result = engine.execute(transform_def, { "value" => "42" })

    expect(result.output["value"]).to be_a(Numeric)
  end

  it "applies :type boolean directive" do
    transform_text = <<~ODIN
      {$}
      odin = "1.0.0"
      transform = "1.0.0"
      direction = "json->json"
      target.format = "json"

      {}
      value = @.value :type boolean
    ODIN

    transform_def = parser.parse(transform_text)
    result = engine.execute(transform_def, { "value" => "true" })

    expect(result.output["value"]).to eq(true)
  end

  it "applies :type string directive" do
    transform_text = <<~ODIN
      {$}
      odin = "1.0.0"
      transform = "1.0.0"
      direction = "json->json"
      target.format = "json"

      {}
      value = @.value :type string
    ODIN

    transform_def = parser.parse(transform_text)
    result = engine.execute(transform_def, { "value" => 42 })

    expect(result.output["value"]).to eq("42")
  end

  it "applies :date directive" do
    transform_text = <<~ODIN
      {$}
      odin = "1.0.0"
      transform = "1.0.0"
      direction = "json->json"
      target.format = "json"

      {}
      value = @.value :date "yyyy-MM-dd"
    ODIN

    transform_def = parser.parse(transform_text)
    result = engine.execute(transform_def, { "value" => "2024-01-15" })

    expect(result.output["value"]).to eq("2024-01-15")
  end
end
