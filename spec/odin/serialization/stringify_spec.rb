# frozen_string_literal: true

require "spec_helper"

RSpec.describe Odin::Serialization::Stringify do
  def build_doc(&block)
    builder = Odin::Types::OdinDocumentBuilder.new
    block.call(builder)
    builder.build
  end

  def stringify(doc, **opts)
    Odin::Serialization::Stringify.new(opts).stringify(doc)
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Value Formatting
  # ─────────────────────────────────────────────────────────────────────────

  context "value formatting" do
    it "formats string quoted" do
      doc = build_doc { |b| b.set("name", Odin::Types::OdinString.new("hello")) }
      expect(stringify(doc, use_headers: false)).to include('"hello"')
    end

    it "formats empty string" do
      doc = build_doc { |b| b.set("name", Odin::Types::OdinString.new("")) }
      expect(stringify(doc, use_headers: false)).to include('""')
    end

    it "formats string with escape sequences" do
      doc = build_doc { |b| b.set("text", Odin::Types::OdinString.new("line1\nline2")) }
      result = stringify(doc, use_headers: false)
      expect(result).to include('"line1\\nline2"')
    end

    it "formats string with tab" do
      doc = build_doc { |b| b.set("text", Odin::Types::OdinString.new("a\tb")) }
      result = stringify(doc, use_headers: false)
      expect(result).to include('"a\\tb"')
    end

    it "formats string with escaped quotes" do
      doc = build_doc { |b| b.set("text", Odin::Types::OdinString.new('say "hi"')) }
      result = stringify(doc, use_headers: false)
      expect(result).to include('"say \\"hi\\""')
    end

    it "formats string with backslash" do
      doc = build_doc { |b| b.set("path", Odin::Types::OdinString.new("a\\b")) }
      result = stringify(doc, use_headers: false)
      expect(result).to include('"a\\\\b"')
    end

    it "formats integer with ## prefix" do
      doc = build_doc { |b| b.set("count", Odin::Types::OdinInteger.new(42)) }
      expect(stringify(doc, use_headers: false)).to include("##42")
    end

    it "formats integer zero" do
      doc = build_doc { |b| b.set("count", Odin::Types::OdinInteger.new(0)) }
      expect(stringify(doc, use_headers: false)).to include("##0")
    end

    it "formats negative integer" do
      doc = build_doc { |b| b.set("offset", Odin::Types::OdinInteger.new(-1)) }
      expect(stringify(doc, use_headers: false)).to include("##-1")
    end

    it "formats large integer without commas" do
      doc = build_doc { |b| b.set("big", Odin::Types::OdinInteger.new(1_000_000)) }
      result = stringify(doc, use_headers: false)
      expect(result).to include("##1000000")
      expect(result).not_to include(",")
    end

    it "formats number with # prefix" do
      doc = build_doc { |b| b.set("rate", Odin::Types::OdinNumber.new(3.14, raw: "3.14")) }
      expect(stringify(doc, use_headers: false)).to include("#3.14")
    end

    it "formats number zero" do
      doc = build_doc { |b| b.set("val", Odin::Types::OdinNumber.new(0.0)) }
      expect(stringify(doc, use_headers: false)).to include("#0.0")
    end

    it "formats currency with #$ prefix" do
      doc = build_doc { |b| b.set("price", Odin::Types::OdinCurrency.new("99.99", decimal_places: 2)) }
      expect(stringify(doc, use_headers: false)).to include('#$99.99')
    end

    it "formats currency with code" do
      val = Odin::Types::OdinCurrency.new("100.00", currency_code: "USD", decimal_places: 2)
      doc = build_doc { |b| b.set("amount", val) }
      expect(stringify(doc, use_headers: false)).to include('#$100.00:USD')
    end

    it "formats boolean true with ? prefix" do
      doc = build_doc { |b| b.set_boolean("flag", true) }
      result = stringify(doc, use_headers: false)
      expect(result).to include("?true")
      expect(result).not_to match(/[^?]true/)
    end

    it "formats boolean false with ? prefix" do
      doc = build_doc { |b| b.set_boolean("flag", false) }
      result = stringify(doc, use_headers: false)
      expect(result).to include("?false")
    end

    it "formats null" do
      doc = build_doc { |b| b.set_null("val") }
      expect(stringify(doc, use_headers: false)).to include("= ~")
    end

    it "formats reference" do
      doc = build_doc { |b| b.set("ref", Odin::Types::OdinReference.new("path.to.field")) }
      expect(stringify(doc, use_headers: false)).to include("@path.to.field")
    end

    it "formats binary" do
      doc = build_doc { |b| b.set("data", Odin::Types::OdinBinary.new("SGVsbG8=")) }
      expect(stringify(doc, use_headers: false)).to include("^SGVsbG8=")
    end

    it "formats binary with algorithm" do
      doc = build_doc { |b| b.set("hash", Odin::Types::OdinBinary.new("SGVsbG8=", algorithm: "sha256")) }
      expect(stringify(doc, use_headers: false)).to include("^sha256:SGVsbG8=")
    end

    it "formats date" do
      val = Odin::Types::OdinDate.new(Date.parse("2024-06-15"), raw: "2024-06-15")
      doc = build_doc { |b| b.set("eff", val) }
      expect(stringify(doc, use_headers: false)).to include("2024-06-15")
    end

    it "formats timestamp" do
      val = Odin::Types::OdinTimestamp.new(DateTime.parse("2024-06-15T10:30:00Z"), raw: "2024-06-15T10:30:00Z")
      doc = build_doc { |b| b.set("created", val) }
      expect(stringify(doc, use_headers: false)).to include("2024-06-15T10:30:00Z")
    end

    it "formats time" do
      val = Odin::Types::OdinTime.new("T09:30:00")
      doc = build_doc { |b| b.set("start", val) }
      expect(stringify(doc, use_headers: false)).to include("T09:30:00")
    end

    it "formats duration" do
      val = Odin::Types::OdinDuration.new("P6M")
      doc = build_doc { |b| b.set("term", val) }
      expect(stringify(doc, use_headers: false)).to include("P6M")
    end

    it "formats percent" do
      val = Odin::Types::OdinPercent.new(0.15, raw: "0.15")
      doc = build_doc { |b| b.set("rate", val) }
      expect(stringify(doc, use_headers: false)).to include("#%0.15")
    end

    it "formats verb expression" do
      val = Odin::Types::OdinVerbExpression.new("upper", args: [Odin::Types::OdinString.new("hello")])
      doc = build_doc { |b| b.set("result", val) }
      expect(stringify(doc, use_headers: false)).to include('%upper "hello"')
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Modifier Formatting
  # ─────────────────────────────────────────────────────────────────────────

  context "modifier formatting" do
    it "formats required modifier" do
      mods = Odin::Types::OdinModifiers.new(required: true)
      doc = build_doc { |b| b.set_string("name", "John", modifiers: mods) }
      expect(stringify(doc, use_headers: false)).to include('!"John"')
    end

    it "formats confidential modifier" do
      mods = Odin::Types::OdinModifiers.new(confidential: true)
      doc = build_doc { |b| b.set_string("ssn", "123", modifiers: mods) }
      expect(stringify(doc, use_headers: false)).to include('*"123"')
    end

    it "formats deprecated modifier" do
      mods = Odin::Types::OdinModifiers.new(deprecated: true)
      doc = build_doc { |b| b.set_string("old", "val", modifiers: mods) }
      expect(stringify(doc, use_headers: false)).to include('-"val"')
    end

    it "formats combined modifiers in canonical order !*-" do
      mods = Odin::Types::OdinModifiers.new(required: true, confidential: true, deprecated: true)
      doc = build_doc { |b| b.set_string("important", "secret", modifiers: mods) }
      expect(stringify(doc, use_headers: false)).to include('!*-"secret"')
    end

    it "formats !* combination" do
      mods = Odin::Types::OdinModifiers.new(required: true, confidential: true)
      doc = build_doc { |b| b.set_string("x", "v", modifiers: mods) }
      expect(stringify(doc, use_headers: false)).to include('!*"v"')
    end

    it "formats !- combination" do
      mods = Odin::Types::OdinModifiers.new(required: true, deprecated: true)
      doc = build_doc { |b| b.set_string("x", "v", modifiers: mods) }
      expect(stringify(doc, use_headers: false)).to include('!-"v"')
    end

    it "formats *- combination" do
      mods = Odin::Types::OdinModifiers.new(confidential: true, deprecated: true)
      doc = build_doc { |b| b.set_string("x", "v", modifiers: mods) }
      expect(stringify(doc, use_headers: false)).to include('*-"v"')
    end

    it "no modifiers means no prefix" do
      doc = build_doc { |b| b.set_string("x", "v") }
      result = stringify(doc, use_headers: false)
      expect(result).to match(/= "v"/)
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Header Grouping
  # ─────────────────────────────────────────────────────────────────────────

  context "header grouping" do
    it "groups paths under common parent header" do
      doc = build_doc do |b|
        b.set_string("Person.name", "Alice")
        b.set_integer("Person.age", 30)
      end
      result = stringify(doc)
      expect(result).to include("{Person}")
      expect(result).to include("name = ")
      expect(result).to include("age = ")
    end

    it "handles root-level paths without header" do
      doc = build_doc do |b|
        b.set_string("name", "Alice")
        b.set_integer("age", 30)
      end
      result = stringify(doc, use_headers: false)
      expect(result).not_to include("{")
      expect(result).to include("name = ")
      expect(result).to include("age = ")
    end

    it "handles multiple sections" do
      doc = build_doc do |b|
        b.set_string("Person.name", "Alice")
        b.set_string("Address.city", "Austin")
        b.set_string("Address.state", "TX")
      end
      result = stringify(doc)
      expect(result).to include("{Person}")
      expect(result).to include("{Address}")
    end

    it "handles array headers" do
      doc = build_doc do |b|
        b.set_string("items[0].name", "Widget")
        b.set_integer("items[0].qty", 10)
        b.set_string("items[1].name", "Gadget")
        b.set_integer("items[1].qty", 5)
      end
      result = stringify(doc)
      expect(result).to include("items[]")
    end

    it "root-level scalar comes before groups" do
      doc = build_doc do |b|
        b.set_string("title", "Test")
        b.set_string("Person.name", "Alice")
        b.set_integer("Person.age", 30)
      end
      result = stringify(doc)
      lines = result.lines.map(&:chomp)
      title_idx = lines.index { |l| l.include?("title") }
      person_idx = lines.index { |l| l.include?("{Person}") }
      expect(title_idx).to be < person_idx
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Metadata
  # ─────────────────────────────────────────────────────────────────────────

  context "metadata" do
    it "outputs metadata under {$} header" do
      doc = build_doc do |b|
        b.set_metadata("odin", Odin::Types::OdinString.new("1.0.0"))
        b.set_string("name", "test")
      end
      result = stringify(doc)
      expect(result).to start_with("{$}\n")
      expect(result).to include('odin = "1.0.0"')
    end

    it "adds separator between metadata and data" do
      doc = build_doc do |b|
        b.set_metadata("odin", Odin::Types::OdinString.new("1.0.0"))
        b.set_string("name", "test")
      end
      result = stringify(doc)
      expect(result).to include("{}\n")
    end

    it "no separator when only metadata" do
      doc = build_doc do |b|
        b.set_metadata("odin", Odin::Types::OdinString.new("1.0.0"))
      end
      result = stringify(doc)
      expect(result).not_to include("{}\n")
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Comments
  # ─────────────────────────────────────────────────────────────────────────

  context "comments" do
    it "includes comments after values" do
      doc = build_doc { |b| b.set("name", Odin::Types::OdinString.new("John"), comment: "full name") }
      result = stringify(doc, use_headers: false)
      expect(result).to include('; full name')
    end

    it "omits comments when include_comments is false" do
      doc = build_doc { |b| b.set("name", Odin::Types::OdinString.new("John"), comment: "full name") }
      result = stringify(doc, use_headers: false, include_comments: false)
      expect(result).not_to include(";")
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Options
  # ─────────────────────────────────────────────────────────────────────────

  context "options" do
    it "use_headers: false produces flat output" do
      doc = build_doc do |b|
        b.set_string("Person.name", "Alice")
        b.set_integer("Person.age", 30)
      end
      result = stringify(doc, use_headers: false)
      expect(result).not_to include("{Person}")
      expect(result).to include("Person.name = ")
      expect(result).to include("Person.age = ")
    end

    it "sort_paths: true sorts paths" do
      doc = build_doc do |b|
        b.set_string("zebra", "last")
        b.set_string("alpha", "first")
      end
      result = stringify(doc, use_headers: false, sort_paths: true)
      lines = result.lines.map(&:chomp).reject(&:empty?)
      expect(lines[0]).to include("alpha")
      expect(lines[1]).to include("zebra")
    end

    it "line_ending: CRLF uses CRLF" do
      doc = build_doc { |b| b.set_string("name", "test") }
      result = stringify(doc, use_headers: false, line_ending: "\r\n")
      expect(result).to include("\r\n")
    end

    it "trailing line ending" do
      doc = build_doc { |b| b.set_string("name", "test") }
      result = stringify(doc, use_headers: false)
      expect(result).to end_with("\n")
    end

    it "empty document produces empty string" do
      doc = Odin::Types::OdinDocument.empty
      result = stringify(doc)
      expect(result).to eq("")
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Roundtrip
  # ─────────────────────────────────────────────────────────────────────────

  context "roundtrip" do
    it "parse-stringify preserves simple values" do
      input = "name = \"John\"\nage = ##30\nactive = ?true\n"
      doc = Odin.parse(input)
      output = Odin.stringify(doc, use_headers: false)
      doc2 = Odin.parse(output)
      expect(doc2.get("name")).to eq(doc.get("name"))
      expect(doc2.get("age")).to eq(doc.get("age"))
      expect(doc2.get("active")).to eq(doc.get("active"))
    end

    it "parse-stringify preserves metadata" do
      input = "{$}\nodin = \"1.0.0\"\n{}\nname = \"test\"\n"
      doc = Odin.parse(input)
      output = Odin.stringify(doc)
      doc2 = Odin.parse(output)
      expect(doc2.metadata_value("odin")).to eq(doc.metadata_value("odin"))
      expect(doc2.get("name")).to eq(doc.get("name"))
    end

    it "parse-stringify preserves modifiers" do
      input = "name = !\"John\"\n"
      doc = Odin.parse(input)
      output = Odin.stringify(doc, use_headers: false)
      doc2 = Odin.parse(output)
      expect(doc2.modifiers_for("name")&.required).to be true
    end

    it "parse-stringify preserves null values" do
      input = "val = ~\n"
      doc = Odin.parse(input)
      output = Odin.stringify(doc, use_headers: false)
      doc2 = Odin.parse(output)
      expect(doc2.get("val")).to be_a(Odin::Types::OdinNull)
    end

    it "parse-stringify preserves currency" do
      input = 'price = #$99.99:USD' + "\n"
      doc = Odin.parse(input)
      output = Odin.stringify(doc, use_headers: false)
      doc2 = Odin.parse(output)
      expect(doc2.get("price").value).to eq(doc.get("price").value)
    end

    it "parse-stringify preserves reference" do
      input = "ref = @drivers[0]\n"
      doc = Odin.parse(input)
      output = Odin.stringify(doc, use_headers: false)
      doc2 = Odin.parse(output)
      expect(doc2.get("ref").path).to eq("drivers[0]")
    end

    it "parse-stringify preserves sections" do
      input = "{Person}\nname = \"Alice\"\nage = ##30\n"
      doc = Odin.parse(input)
      output = Odin.stringify(doc)
      doc2 = Odin.parse(output)
      expect(doc2.get("Person.name")).to eq(doc.get("Person.name"))
      expect(doc2.get("Person.age")).to eq(doc.get("Person.age"))
    end

    it "parse-stringify-parse produces equivalent document" do
      input = "name = \"John\"\nage = ##30\nactive = ?true\nval = ~\n"
      doc1 = Odin.parse(input)
      text1 = Odin.stringify(doc1, use_headers: false)
      doc2 = Odin.parse(text1)
      text2 = Odin.stringify(doc2, use_headers: false)
      doc3 = Odin.parse(text2)
      expect(doc3.paths.sort).to eq(doc2.paths.sort)
      doc3.paths.each do |path|
        expect(doc3.get(path)).to eq(doc2.get(path))
      end
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Tabular Output
  # ─────────────────────────────────────────────────────────────────────────

  context "tabular output" do
    it "outputs primitive array as tabular" do
      doc = build_doc do |b|
        b.set("tags[0]", Odin::Types::OdinString.new("urgent"))
        b.set("tags[1]", Odin::Types::OdinString.new("important"))
      end
      result = stringify(doc)
      expect(result).to include("tags[]")
      expect(result).to include('"urgent"')
      expect(result).to include('"important"')
    end

    it "outputs object array as tabular" do
      doc = build_doc do |b|
        b.set("items[0].name", Odin::Types::OdinString.new("Widget"))
        b.set("items[0].qty", Odin::Types::OdinInteger.new(10))
        b.set("items[1].name", Odin::Types::OdinString.new("Gadget"))
        b.set("items[1].qty", Odin::Types::OdinInteger.new(5))
      end
      result = stringify(doc)
      expect(result).to include("items[]")
    end
  end
end
