# frozen_string_literal: true

require "spec_helper"
require "bigdecimal"

RSpec.describe Odin::Export do
  # Helper to build OdinDocument
  def build_doc(&block)
    builder = Odin::Types::OdinDocumentBuilder.new
    block.call(builder)
    builder.build
  end

  # ── JSON Export ──

  describe ".to_json" do
    it "exports simple string field" do
      doc = build_doc { |b| b.set("name", Odin::Types::OdinString.new("John")) }
      json = Odin::Export.to_json(doc)
      parsed = JSON.parse(json)
      expect(parsed["name"]).to eq("John")
    end

    it "exports integer field" do
      doc = build_doc { |b| b.set("age", Odin::Types::OdinInteger.new(30)) }
      json = Odin::Export.to_json(doc)
      parsed = JSON.parse(json)
      expect(parsed["age"]).to eq(30)
    end

    it "exports number field" do
      doc = build_doc { |b| b.set("pi", Odin::Types::OdinNumber.new(3.14)) }
      json = Odin::Export.to_json(doc)
      parsed = JSON.parse(json)
      expect(parsed["pi"]).to be_within(0.001).of(3.14)
    end

    it "exports boolean field" do
      doc = build_doc { |b| b.set("active", Odin::Types::OdinBoolean.new(true)) }
      json = Odin::Export.to_json(doc)
      parsed = JSON.parse(json)
      expect(parsed["active"]).to be true
    end

    it "exports null field" do
      doc = build_doc { |b| b.set("empty", Odin::Types::OdinNull.new) }
      json = Odin::Export.to_json(doc)
      parsed = JSON.parse(json)
      expect(parsed["empty"]).to be_nil
    end

    it "exports currency as number" do
      doc = build_doc { |b| b.set("price", Odin::Types::OdinCurrency.new(BigDecimal("99.99"), currency_code: "USD")) }
      json = Odin::Export.to_json(doc)
      parsed = JSON.parse(json)
      expect(parsed["price"]).to be_within(0.01).of(99.99)
    end

    it "exports percent" do
      doc = build_doc { |b| b.set("rate", Odin::Types::OdinPercent.new(50.0)) }
      json = Odin::Export.to_json(doc)
      parsed = JSON.parse(json)
      expect(parsed["rate"]).to eq(50.0)
    end

    it "exports nested paths as nested objects" do
      doc = build_doc do |b|
        b.set("person.name", Odin::Types::OdinString.new("John"))
        b.set("person.age", Odin::Types::OdinInteger.new(30))
      end
      json = Odin::Export.to_json(doc)
      parsed = JSON.parse(json)
      expect(parsed["person"]["name"]).to eq("John")
      expect(parsed["person"]["age"]).to eq(30)
    end

    it "exports date as string" do
      doc = build_doc { |b| b.set("dob", Odin::Types::OdinDate.new(Date.new(2024, 1, 15))) }
      json = Odin::Export.to_json(doc)
      parsed = JSON.parse(json)
      expect(parsed["dob"]).to eq("2024-01-15")
    end

    it "exports reference with @ prefix" do
      doc = build_doc { |b| b.set("ref", Odin::Types::OdinReference.new("other.field")) }
      json = Odin::Export.to_json(doc)
      parsed = JSON.parse(json)
      expect(parsed["ref"]).to eq("@other.field")
    end

    it "exports binary with ^ prefix" do
      doc = build_doc { |b| b.set("data", Odin::Types::OdinBinary.new("SGVsbG8=")) }
      json = Odin::Export.to_json(doc)
      parsed = JSON.parse(json)
      expect(parsed["data"]).to eq("^SGVsbG8=")
    end

    it "exports compact mode" do
      doc = build_doc { |b| b.set("x", Odin::Types::OdinInteger.new(1)) }
      json = Odin::Export.to_json(doc, pretty: false)
      expect(json).not_to include("\n")
    end
  end

  # ── XML Export ──

  describe ".to_xml" do
    it "generates valid XML with declaration" do
      doc = build_doc { |b| b.set("name", Odin::Types::OdinString.new("John")) }
      xml = Odin::Export.to_xml(doc)
      expect(xml).to include('<?xml version="1.0"')
      expect(xml).to include("<name>John</name>")
    end

    it "uses custom root element" do
      doc = build_doc { |b| b.set("x", Odin::Types::OdinInteger.new(1)) }
      xml = Odin::Export.to_xml(doc, root: "data")
      expect(xml).to include("<data>")
      expect(xml).to include("</data>")
    end

    it "omits null values in XML output" do
      doc = build_doc { |b| b.set("empty", Odin::Types::OdinNull.new) }
      xml = Odin::Export.to_xml(doc)
      expect(xml).not_to include("empty")
    end

    it "preserves type attributes when enabled" do
      doc = build_doc { |b| b.set("count", Odin::Types::OdinInteger.new(42)) }
      xml = Odin::Export.to_xml(doc, preserve_types: true)
      expect(xml).to include('odin:type="integer"')
    end

    it "preserves modifier attributes when enabled" do
      doc = build_doc do |b|
        b.set("ssn", Odin::Types::OdinString.new("123-45-6789"),
              modifiers: Odin::Types::OdinModifiers.new(confidential: true))
      end
      xml = Odin::Export.to_xml(doc, preserve_modifiers: true)
      expect(xml).to include('odin:confidential="true"')
    end

    it "adds namespace when preserving types" do
      doc = build_doc { |b| b.set("x", Odin::Types::OdinInteger.new(1)) }
      xml = Odin::Export.to_xml(doc, preserve_types: true)
      expect(xml).to include("xmlns:odin")
    end

    it "escapes special characters" do
      doc = build_doc { |b| b.set("text", Odin::Types::OdinString.new("a < b & c")) }
      xml = Odin::Export.to_xml(doc)
      expect(xml).to include("a &lt; b &amp; c")
    end
  end

  # ── CSV Export ──

  describe ".to_csv" do
    it "exports array-style paths as CSV" do
      doc = build_doc do |b|
        b.set("items[0].name", Odin::Types::OdinString.new("Widget"))
        b.set("items[0].price", Odin::Types::OdinNumber.new(9.99))
        b.set("items[1].name", Odin::Types::OdinString.new("Gadget"))
        b.set("items[1].price", Odin::Types::OdinNumber.new(19.99))
      end
      csv = Odin::Export.to_csv(doc)
      lines = csv.strip.split("\n")
      expect(lines[0]).to eq("name,price")
      expect(lines.size).to eq(3)
    end

    it "returns empty for documents without array patterns" do
      doc = build_doc { |b| b.set("name", Odin::Types::OdinString.new("John")) }
      csv = Odin::Export.to_csv(doc)
      expect(csv).to eq("")
    end

    it "escapes fields with commas" do
      doc = build_doc do |b|
        b.set("items[0].desc", Odin::Types::OdinString.new("a, b"))
      end
      csv = Odin::Export.to_csv(doc)
      expect(csv).to include('"a, b"')
    end
  end

  # ── Fixed-Width Export ──

  describe ".to_fixed_width" do
    it "exports fields at fixed positions" do
      doc = build_doc do |b|
        b.set("Name", Odin::Types::OdinString.new("John"))
        b.set("Age", Odin::Types::OdinInteger.new(30))
      end
      columns = [
        { name: "Name", path: "Name", pos: 0, len: 10 },
        { name: "Age", path: "Age", pos: 10, len: 3, align: :right }
      ]
      result = Odin::Export.to_fixed_width(doc, columns: columns, line_width: 13)
      expect(result).to start_with("John")
      expect(result[10..12].strip).to eq("30")
    end
  end
end
