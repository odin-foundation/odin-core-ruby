# frozen_string_literal: true

require "spec_helper"

RSpec.describe Odin do
  it "has a version" do
    expect(Odin::VERSION).to be_a(String)
    expect(Odin::VERSION).not_to be_empty
  end

  it "builder returns OdinDocumentBuilder" do
    expect(Odin.builder).to be_a(Odin::Types::OdinDocumentBuilder)
  end

  it "parse returns an OdinDocument" do
    doc = Odin.parse('name = "John"')
    expect(doc).to be_a(Odin::Types::OdinDocument)
    expect(doc.get("name").value).to eq("John")
  end

  it "stringify serializes a document" do
    doc = Odin.parse('name = "John"')
    result = Odin.stringify(doc, use_headers: false)
    expect(result).to include('name = "John"')
  end

  it "canonicalize produces deterministic output" do
    doc = Odin.parse("zebra = \"z\"\nalpha = \"a\"")
    result = Odin.canonicalize(doc)
    expect(result).to eq("alpha = \"a\"\nzebra = \"z\"\n")
  end

  it "diff computes differences between documents" do
    a = Odin.parse("name = \"John\"")
    b = Odin.parse("name = \"Jane\"")
    d = Odin.diff(a, b)
    expect(d).to be_a(Odin::Types::OdinDiff)
    expect(d.changed.length).to eq(1)
  end

  it "patch applies diff to document" do
    a = Odin.parse("name = \"John\"")
    b = Odin.parse("name = \"Jane\"")
    d = Odin.diff(a, b)
    result = Odin.patch(a, d)
    expect(result.get("name")).to eq(b.get("name"))
  end
end
