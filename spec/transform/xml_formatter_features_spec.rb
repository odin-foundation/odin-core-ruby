# frozen_string_literal: true

require "spec_helper"

# Tests for two XML transform-target features in the engine's XML formatter:
#   (A) target namespaces — {$target.namespace} + :ns field modifier
#   (B) emitTypeHints — target.emitTypeHints = ?false suppresses odin:* attrs/ns
RSpec.describe "XML formatter features (transform engine)" do
  let(:engine) { Odin::Transform::TransformEngine.new }
  let(:parser) { Odin::Transform::TransformParser.new }

  def run(transform_text, source)
    engine.execute(parser.parse(transform_text), source).formatted
  end

  # ODIN source carrying typed integer + currency values.
  # Single-quoted heredoc: ODIN's #$ currency prefix must not be Ruby-interpolated.
  TYPED_INPUT = <<~'ODIN'
    {$}
    odin = "1.0.0"
    {}
    {rec}
    count = ##42
    price = #$9.99:USD
    bare = #$50.00
  ODIN

  # ── emitTypeHints default (true) ──

  describe "emitTypeHints default (true)" do
    let(:transform) do
      <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "odin->xml"
        target.format = "xml"

        {$source}
        format = "odin"

        {Record}
        Count = @rec.count
        Price = @rec.price
        Bare = @rec.bare
      ODIN
    end

    it "emits odin:type for integer and the odin namespace" do
      xml = run(transform, TYPED_INPUT)
      expect(xml).to include('xmlns:odin="https://odin.foundation/ns"')
      expect(xml).to include('odin:type="integer"')
      expect(xml).to include("<Count")
      expect(xml).to include(">42<")
    end

    it "emits odin:type=currency and odin:currencyCode for the coded currency value" do
      xml = run(transform, TYPED_INPUT)
      expect(xml).to include("<Price")
      expect(xml).to include('odin:type="currency"')
      expect(xml).to include('odin:currencyCode="USD"')
      expect(xml).to include(">9.99<")
    end

    it "emits odin:type=currency with preserved decimals for a code-less currency" do
      xml = run(transform, TYPED_INPUT)
      bare = xml[/<Bare[^>]*>/]
      expect(bare).to include('odin:type="currency"')
      expect(bare).not_to include("odin:currencyCode")
      expect(xml).to include(">50.00<")
    end
  end

  # ── emitTypeHints = ?false ──

  describe "emitTypeHints = ?false" do
    let(:transform) do
      <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "odin->xml"
        target.format = "xml"
        target.emitTypeHints = ?false

        {$source}
        format = "odin"

        {Record}
        Count = @rec.count
        Price = @rec.price
      ODIN
    end

    it "suppresses all odin: attributes and namespace but keeps values" do
      xml = run(transform, TYPED_INPUT)
      expect(xml).not_to include("odin:type")
      expect(xml).not_to include("odin:currencyCode")
      expect(xml).not_to include("xmlns:odin")
      expect(xml).not_to include("odin:")
      expect(xml).to include("<Count>42</Count>")
      expect(xml).to include("<Price>9.99</Price>")
    end
  end

  # ── :ns prefixing + root xmlns ──

  describe ":ns prefixing" do
    let(:transform) do
      <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->xml"
        target.format = "xml"

        {$target.namespace}
        p = "urn:x"

        {Doc}
        Code = @.code :ns p
        Name = @.name
      ODIN
    end

    it "declares xmlns on root and prefixes only the :ns field" do
      xml = run(transform, { "code" => "A1", "name" => "Bob" })
      expect(xml).to include('xmlns:p="urn:x"')
      expect(xml).to include("<p:Code>A1</p:Code>")
      expect(xml).to include("<Name>Bob</Name>")
      expect(xml).not_to include("<p:Name")
    end
  end

  # ── multiple namespaces ──

  describe "multiple namespaces" do
    let(:transform) do
      <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->xml"
        target.format = "xml"

        {$target.namespace}
        p = "urn:x"
        q = "urn:y"

        {Doc}
        Code = @.code :ns p
        Name = @.name :ns q
      ODIN
    end

    it "declares both xmlns prefixes on the root element" do
      xml = run(transform, { "code" => "A1", "name" => "Bob" })
      expect(xml).to include('xmlns:p="urn:x"')
      expect(xml).to include('xmlns:q="urn:y"')
      expect(xml).to include("<p:Code>A1</p:Code>")
      expect(xml).to include("<q:Name>Bob</q:Name>")
    end
  end

  # ── namespace + emitTypeHints=false together ──

  describe "namespace with emitTypeHints = ?false" do
    let(:transform) do
      <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "odin->xml"
        target.format = "xml"
        target.emitTypeHints = ?false

        {$source}
        format = "odin"

        {$target.namespace}
        p = "urn:x"

        {Rec}
        Count = @rec.count :ns p
        Name = @rec.name
      ODIN
    end

    let(:input) do
      <<~ODIN
        {$}
        odin = "1.0.0"
        {}
        {rec}
        count = ##42
        name = "Bob"
      ODIN
    end

    it "keeps the prefixed element and xmlns but emits no odin: attributes" do
      xml = run(transform, input)
      expect(xml).to include('xmlns:p="urn:x"')
      expect(xml).to include("<p:Count>42</p:Count>")
      expect(xml).to include("<Name>Bob</Name>")
      expect(xml).not_to include("odin:")
    end
  end
end
