# frozen_string_literal: true

require "spec_helper"

RSpec.describe Odin::Types::OdinDocumentBuilder do
  let(:builder) { described_class.new }

  describe "#set and #build" do
    it "builds a document with assignments" do
      val = Odin::Types::OdinString.new("test")
      doc = builder.set("name", val).build
      expect(doc["name"]).to eq(val)
    end

    it "builds with multiple assignments" do
      doc = builder
        .set("a", Odin::Types::OdinString.new("x"))
        .set("b", Odin::Types::OdinInteger.new(1))
        .build
      expect(doc.size).to eq(2)
    end
  end

  describe "#set with modifiers" do
    it "stores modifiers for path" do
      mods = Odin::Types::OdinModifiers.new(required: true)
      doc = builder.set("name", Odin::Types::OdinString.new("x"), modifiers: mods).build
      expect(doc.modifiers_for("name")).to eq(mods)
    end
  end

  describe "#set with comments" do
    it "stores comment for path" do
      doc = builder.set("x", Odin::Types::NULL, comment: "a comment").build
      expect(doc.comment_for("x")).to eq("a comment")
    end
  end

  describe "#set_metadata" do
    it "stores metadata" do
      doc = builder.set_metadata("odin", Odin::Types::OdinString.new("1.0.0")).build
      expect(doc.metadata["odin"]).to eq(Odin::Types::OdinString.new("1.0.0"))
    end
  end

  describe "#set_string" do
    it "creates OdinString value" do
      doc = builder.set_string("name", "hello").build
      expect(doc["name"]).to be_a(Odin::Types::OdinString)
      expect(doc["name"].value).to eq("hello")
    end
  end

  describe "#set_integer" do
    it "creates OdinInteger value" do
      doc = builder.set_integer("count", 42).build
      expect(doc["count"]).to be_a(Odin::Types::OdinInteger)
      expect(doc["count"].value).to eq(42)
    end
  end

  describe "#set_number" do
    it "creates OdinNumber value" do
      doc = builder.set_number("pi", 3.14).build
      expect(doc["pi"]).to be_a(Odin::Types::OdinNumber)
    end
  end

  describe "#set_boolean" do
    it "creates TRUE_VAL for true" do
      doc = builder.set_boolean("flag", true).build
      expect(doc["flag"]).to eq(Odin::Types::TRUE_VAL)
    end

    it "creates FALSE_VAL for false" do
      doc = builder.set_boolean("flag", false).build
      expect(doc["flag"]).to eq(Odin::Types::FALSE_VAL)
    end
  end

  describe "#set_null" do
    it "creates NULL value" do
      doc = builder.set_null("empty").build
      expect(doc["empty"]).to eq(Odin::Types::NULL)
    end
  end

  describe "#set_currency" do
    it "creates OdinCurrency value" do
      doc = builder.set_currency("price", "99.99", currency_code: "USD").build
      expect(doc["price"]).to be_a(Odin::Types::OdinCurrency)
      expect(doc["price"].currency_code).to eq("USD")
    end
  end

  describe "#remove" do
    it "removes a path" do
      doc = builder
        .set("a", Odin::Types::NULL)
        .set("b", Odin::Types::NULL)
        .remove("a")
        .build
      expect(doc.include?("a")).to be false
      expect(doc.include?("b")).to be true
    end
  end

  describe "independent builds" do
    it "produces independent documents" do
      builder.set("x", Odin::Types::OdinString.new("v1"))
      doc1 = builder.build
      builder.set("x", Odin::Types::OdinString.new("v2"))
      doc2 = builder.build
      expect(doc1["x"].value).to eq("v1")
      expect(doc2["x"].value).to eq("v2")
    end
  end

  describe "built document is frozen" do
    it "returns frozen document" do
      doc = builder.set("a", Odin::Types::NULL).build
      expect(doc).to be_frozen
    end
  end
end
