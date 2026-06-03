# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe "Extra String Verbs" do
  let(:engine) { Odin::Transform::TransformEngine.new }
  let(:ctx) { Odin::Transform::VerbContext.new }
  let(:dv) { Odin::Types::DynValue }

  def invoke(name, *args)
    engine.invoke_verb(name, args, ctx)
  end

  # ── escapeHtml ──

  describe "escapeHtml" do
    it "escapes angle brackets and ampersands" do
      result = invoke("escapeHtml", dv.of_string("<p>1 & 2</p>"))
      expect(result.value).to eq("&lt;p&gt;1 &amp; 2&lt;/p&gt;")
    end

    it "leaves an empty string unchanged" do
      expect(invoke("escapeHtml", dv.of_string("")).value).to eq("")
    end

    it "returns null for no arguments" do
      expect(invoke("escapeHtml").null?).to be true
    end
  end

  # ── unescapeHtml ──

  describe "unescapeHtml" do
    it "decodes named entities" do
      result = invoke("unescapeHtml", dv.of_string("&lt;p&gt;1 &amp; 2&lt;/p&gt;"))
      expect(result.value).to eq("<p>1 & 2</p>")
    end

    it "decodes decimal and hex numeric references" do
      result = invoke("unescapeHtml", dv.of_string("&#65;&#x42;"))
      expect(result.value).to eq("AB")
    end
  end

  # ── escapeXml ──

  describe "escapeXml" do
    it "escapes apostrophes as &apos;" do
      result = invoke("escapeXml", dv.of_string("x = 'a' & b"))
      expect(result.value).to eq("x = &apos;a&apos; &amp; b")
    end

    it "escapes angle brackets and quotes" do
      result = invoke("escapeXml", dv.of_string('<a href="u">'))
      expect(result.value).to eq("&lt;a href=&quot;u&quot;&gt;")
    end

    it "leaves text without specials unchanged" do
      expect(invoke("escapeXml", dv.of_string("no specials")).value).to eq("no specials")
    end
  end

  # ── stripTags ──

  describe "stripTags" do
    it "removes html tags" do
      result = invoke("stripTags", dv.of_string("<p>Hello <b>world</b></p>"))
      expect(result.value).to eq("Hello world")
    end

    it "leaves untagged text unchanged" do
      expect(invoke("stripTags", dv.of_string("no tags here")).value).to eq("no tags here")
    end
  end

  # ── template ──

  describe "template" do
    it "substitutes named placeholders" do
      data = dv.of_object({ "name" => dv.of_string("Ada"), "age" => dv.of_integer(36) })
      result = invoke("template", dv.of_string("Hi {name}, you are {age}"), data)
      expect(result.value).to eq("Hi Ada, you are 36")
    end

    it "replaces a missing key with an empty string" do
      data = dv.of_object({ "name" => dv.of_string("Ada") })
      result = invoke("template", dv.of_string("a{missing}b"), data)
      expect(result.value).to eq("ab")
    end

    it "returns null with fewer than two arguments" do
      expect(invoke("template", dv.of_string("a{x}b")).null?).to be true
    end
  end
end
