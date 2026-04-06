# frozen_string_literal: true

require "spec_helper"

RSpec.describe Odin::Serialization::Canonicalize do
  def build_doc(&block)
    builder = Odin::Types::OdinDocumentBuilder.new
    block.call(builder)
    builder.build
  end

  def canonicalize(doc)
    Odin::Serialization::Canonicalize.new.canonicalize(doc)
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Path Sorting
  # ─────────────────────────────────────────────────────────────────────────

  context "path sorting" do
    it "sorts $ metadata paths first" do
      doc = build_doc do |b|
        b.set_string("name", "test")
        b.set_metadata("odin", Odin::Types::OdinString.new("1.0.0"))
      end
      result = canonicalize(doc)
      lines = result.lines
      expect(lines[0]).to start_with("$.odin")
      expect(lines[1]).to start_with("name")
    end

    it "sorts paths lexicographically" do
      doc = build_doc do |b|
        b.set_string("zebra", "last")
        b.set_string("alpha", "first")
        b.set_string("middle", "mid")
      end
      result = canonicalize(doc)
      lines = result.lines.map { |l| l.split(" = ")[0] }
      expect(lines).to eq(%w[alpha middle zebra])
    end

    it "sorts array indices numerically" do
      doc = build_doc do |b|
        b.set_string("items[0]", "zero")
        b.set_string("items[1]", "one")
        b.set_string("items[2]", "two")
        b.set_string("items[10]", "ten")
      end
      result = canonicalize(doc)
      lines = result.lines.map { |l| l.split(" = ")[0] }
      expect(lines).to eq(%w[items[0] items[1] items[2] items[10]])
    end

    it "sorts & extension paths last" do
      doc = build_doc do |b|
        b.set_string("name", "test")
        b.set_string("&ext.field", "val")
      end
      result = canonicalize(doc)
      lines = result.lines.map { |l| l.split(" = ")[0] }
      expect(lines[0]).to eq("name")
      expect(lines[1]).to eq("&ext.field")
    end

    it "sorts mixed: metadata + regular + extension" do
      doc = build_doc do |b|
        b.set_string("&ext", "e")
        b.set_string("name", "n")
        b.set_metadata("ver", Odin::Types::OdinString.new("1"))
      end
      result = canonicalize(doc)
      lines = result.lines.map { |l| l.split(" = ")[0] }
      expect(lines[0]).to eq("$.ver")
      expect(lines[1]).to eq("name")
      expect(lines[2]).to eq("&ext")
    end

    it "sorts nested paths correctly" do
      doc = build_doc do |b|
        b.set_string("person.name", "Alice")
        b.set_integer("person.age", 30)
      end
      result = canonicalize(doc)
      lines = result.lines.map { |l| l.split(" = ")[0] }
      expect(lines).to eq(%w[person.age person.name])
    end

    it "sorts deeply nested paths" do
      doc = build_doc do |b|
        b.set_integer("a.z.val", 1)
        b.set_integer("a.m.val", 2)
      end
      result = canonicalize(doc)
      lines = result.lines.map { |l| l.split(" = ")[0] }
      expect(lines).to eq(%w[a.m.val a.z.val])
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Value Formatting
  # ─────────────────────────────────────────────────────────────────────────

  context "value formatting" do
    it "formats strings always quoted" do
      doc = build_doc { |b| b.set_string("name", "John") }
      expect(canonicalize(doc)).to include('"John"')
    end

    it "formats number stripping trailing zeros" do
      doc = build_doc { |b| b.set("rate", Odin::Types::OdinNumber.new(3.14, raw: "3.140")) }
      expect(canonicalize(doc)).to include("#3.14\n")
    end

    it "formats whole number without .0" do
      doc = build_doc { |b| b.set("count", Odin::Types::OdinNumber.new(42.0)) }
      expect(canonicalize(doc)).to include("#42\n")
    end

    it "formats currency with min 2 decimal places" do
      doc = build_doc { |b| b.set("price", Odin::Types::OdinCurrency.new("10", decimal_places: 0)) }
      expect(canonicalize(doc)).to include('#$10.00')
    end

    it "formats currency preserving existing 2+ decimal places" do
      doc = build_doc { |b| b.set("price", Odin::Types::OdinCurrency.new("99.50", decimal_places: 2)) }
      expect(canonicalize(doc)).to include('#$99.50')
    end

    it "formats currency code uppercase" do
      doc = build_doc do |b|
        b.set("price", Odin::Types::OdinCurrency.new("50.00", currency_code: "gbp", decimal_places: 2))
      end
      expect(canonicalize(doc)).to include('#$50.00:GBP')
    end

    it "formats negative currency" do
      doc = build_doc { |b| b.set("refund", Odin::Types::OdinCurrency.new("-25.00", decimal_places: 2)) }
      expect(canonicalize(doc)).to include('#$-25.00')
    end

    it "formats boolean as bare true (no ? prefix)" do
      doc = build_doc { |b| b.set_boolean("flag", true) }
      result = canonicalize(doc)
      expect(result).to include("= true\n")
      expect(result).not_to include("?true")
    end

    it "formats boolean as bare false (no ? prefix)" do
      doc = build_doc { |b| b.set_boolean("flag", false) }
      result = canonicalize(doc)
      expect(result).to include("= false\n")
      expect(result).not_to include("?false")
    end

    it "formats integer without commas" do
      doc = build_doc { |b| b.set_integer("big", 1_000_000) }
      result = canonicalize(doc)
      expect(result).to include("##1000000")
      expect(result).not_to include(",")
    end

    it "formats negative integer" do
      doc = build_doc { |b| b.set_integer("offset", -100) }
      expect(canonicalize(doc)).to include("##-100\n")
    end

    it "formats null" do
      doc = build_doc { |b| b.set_null("val") }
      expect(canonicalize(doc)).to include("= ~\n")
    end

    it "formats reference" do
      doc = build_doc { |b| b.set("ref", Odin::Types::OdinReference.new("drivers[0]")) }
      expect(canonicalize(doc)).to include("@drivers[0]\n")
    end

    it "formats binary" do
      doc = build_doc { |b| b.set("data", Odin::Types::OdinBinary.new("SGVsbG8=")) }
      expect(canonicalize(doc)).to include("^SGVsbG8=\n")
    end

    it "formats binary with algorithm" do
      doc = build_doc { |b| b.set("hash", Odin::Types::OdinBinary.new("SGVsbG8=", algorithm: "sha256")) }
      expect(canonicalize(doc)).to include("^sha256:SGVsbG8=\n")
    end

    it "formats date" do
      val = Odin::Types::OdinDate.new(Date.parse("2024-06-15"), raw: "2024-06-15")
      doc = build_doc { |b| b.set("eff", val) }
      expect(canonicalize(doc)).to include("2024-06-15\n")
    end

    it "formats timestamp" do
      val = Odin::Types::OdinTimestamp.new(DateTime.parse("2024-06-15T10:30:00Z"), raw: "2024-06-15T10:30:00Z")
      doc = build_doc { |b| b.set("created", val) }
      expect(canonicalize(doc)).to include("2024-06-15T10:30:00Z\n")
    end

    it "formats time" do
      val = Odin::Types::OdinTime.new("T09:30:00")
      doc = build_doc { |b| b.set("start", val) }
      expect(canonicalize(doc)).to include("T09:30:00\n")
    end

    it "formats duration" do
      val = Odin::Types::OdinDuration.new("P6M")
      doc = build_doc { |b| b.set("term", val) }
      expect(canonicalize(doc)).to include("P6M\n")
    end

    it "formats percent" do
      val = Odin::Types::OdinPercent.new(0.15, raw: "0.15")
      doc = build_doc { |b| b.set("rate", val) }
      expect(canonicalize(doc)).to include("#%0.15\n")
    end

    it "formats percent whole number" do
      val = Odin::Types::OdinPercent.new(1.0, raw: "1")
      doc = build_doc { |b| b.set("complete", val) }
      expect(canonicalize(doc)).to include("#%1\n")
    end

    it "formats negative percent" do
      val = Odin::Types::OdinPercent.new(-0.05, raw: "-0.05")
      doc = build_doc { |b| b.set("loss", val) }
      expect(canonicalize(doc)).to include("#%-0.05\n")
    end

    it "formats string with escape sequences" do
      doc = build_doc { |b| b.set("text", Odin::Types::OdinString.new("line1\nline2")) }
      expect(canonicalize(doc)).to include('"line1\\nline2"')
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Modifier Formatting
  # ─────────────────────────────────────────────────────────────────────────

  context "modifier formatting" do
    it "preserves required modifier" do
      mods = Odin::Types::OdinModifiers.new(required: true)
      doc = build_doc { |b| b.set_string("name", "John", modifiers: mods) }
      expect(canonicalize(doc)).to include('!"John"')
    end

    it "preserves confidential modifier" do
      mods = Odin::Types::OdinModifiers.new(confidential: true)
      doc = build_doc { |b| b.set_string("ssn", "123-45-6789", modifiers: mods) }
      expect(canonicalize(doc)).to include('*"123-45-6789"')
    end

    it "preserves deprecated modifier" do
      mods = Odin::Types::OdinModifiers.new(deprecated: true)
      doc = build_doc { |b| b.set_string("old", "legacy", modifiers: mods) }
      expect(canonicalize(doc)).to include('-"legacy"')
    end

    it "formats combined modifiers in canonical order !*-" do
      mods = Odin::Types::OdinModifiers.new(required: true, confidential: true, deprecated: true)
      doc = build_doc { |b| b.set_string("important", "secret", modifiers: mods) }
      expect(canonicalize(doc)).to include('!*-"secret"')
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Output Format
  # ─────────────────────────────────────────────────────────────────────────

  context "output format" do
    it "uses flat path = value format (no headers)" do
      doc = build_doc do |b|
        b.set_string("Person.name", "Alice")
        b.set_integer("Person.age", 30)
      end
      result = canonicalize(doc)
      expect(result).not_to include("{Person}")
      expect(result).to include("Person.age = ")
      expect(result).to include("Person.name = ")
    end

    it "strips comments" do
      doc = build_doc { |b| b.set("name", Odin::Types::OdinString.new("John"), comment: "full name") }
      result = canonicalize(doc)
      expect(result).not_to include(";")
    end

    it "uses LF line endings only" do
      doc = build_doc do |b|
        b.set_string("a", "1")
        b.set_string("b", "2")
      end
      result = canonicalize(doc)
      expect(result).not_to include("\r")
      expect(result).to include("\n")
    end

    it "produces UTF-8 encoded output" do
      doc = build_doc { |b| b.set_string("name", "test") }
      result = canonicalize(doc)
      expect(result.encoding).to eq(Encoding::UTF_8)
    end

    it "trailing newline present" do
      doc = build_doc { |b| b.set_string("name", "test") }
      result = canonicalize(doc)
      expect(result).to end_with("\n")
    end

    it "empty document produces empty string" do
      doc = Odin::Types::OdinDocument.empty
      result = canonicalize(doc)
      expect(result).to eq("")
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Idempotence
  # ─────────────────────────────────────────────────────────────────────────

  context "idempotence" do
    it "canonicalize(parse(canonicalize(parse(text)))) == canonicalize(parse(text))" do
      input = "zebra = \"last\"\nalpha = \"first\"\nmiddle = \"mid\""
      doc1 = Odin.parse(input)
      c1 = Odin.canonicalize(doc1)
      doc2 = Odin.parse(c1)
      c2 = Odin.canonicalize(doc2)
      expect(c2).to eq(c1)
    end

    it "same document always produces identical output" do
      doc = build_doc do |b|
        b.set_string("name", "test")
        b.set_integer("count", 42)
      end
      r1 = canonicalize(doc)
      r2 = canonicalize(doc)
      expect(r1).to eq(r2)
    end

    it "builder order does not affect canonical output" do
      doc1 = build_doc do |b|
        b.set_integer("alpha", 1)
        b.set_integer("beta", 2)
        b.set_integer("gamma", 3)
      end
      doc2 = build_doc do |b|
        b.set_integer("gamma", 3)
        b.set_integer("alpha", 1)
        b.set_integer("beta", 2)
      end
      expect(canonicalize(doc1)).to eq(canonicalize(doc2))
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Integration with parse
  # ─────────────────────────────────────────────────────────────────────────

  context "parse integration" do
    it "canonicalizes parsed document with sections" do
      input = "{person}\nname = \"Alice\"\n{person}\nage = ##30"
      doc = Odin.parse(input)
      result = Odin.canonicalize(doc)
      expect(result).to eq("person.age = ##30\nperson.name = \"Alice\"\n")
    end

    it "canonicalizes parsed document stripping comments" do
      input = "; This is a comment\nname = \"John\"\n; Another\nage = ##30"
      doc = Odin.parse(input)
      result = Odin.canonicalize(doc)
      expect(result).to eq("age = ##30\nname = \"John\"\n")
    end

    it "canonicalizes document with metadata" do
      input = "name = \"Policy\"\n{$}\nodin = \"1.0.0\""
      doc = Odin.parse(input)
      result = Odin.canonicalize(doc)
      expect(result).to eq("$.odin = \"1.0.0\"\nname = \"Policy\"\n")
    end

    it "canonicalizes boolean correctly (no ? prefix)" do
      input = "active = ?true\nenabled = ?false"
      doc = Odin.parse(input)
      result = Odin.canonicalize(doc)
      expect(result).to eq("active = true\nenabled = false\n")
    end

    it "normalizes currency trailing zeros" do
      input = 'price = #$10' + "\n" + 'amount = #$99.50'
      doc = Odin.parse(input)
      result = Odin.canonicalize(doc)
      expect(result).to include('#$10.00')
      expect(result).to include('#$99.50')
    end

    it "normalizes number trailing zeros" do
      input = "rate = #3.140\npi = #3.14"
      doc = Odin.parse(input)
      result = Odin.canonicalize(doc)
      lines = result.lines
      # Both should be #3.14
      expect(lines.all? { |l| l.include?("#3.14") }).to be true
    end
  end
end
