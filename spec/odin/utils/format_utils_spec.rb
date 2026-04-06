# frozen_string_literal: true

require "spec_helper"

RSpec.describe Odin::Utils::FormatUtils do
  let(:fu) { Odin::Utils::FormatUtils }

  # ─────────────────────────────────────────────────────────────────────────
  # String Escaping
  # ─────────────────────────────────────────────────────────────────────────

  describe ".escape_string" do
    it "passes plain strings through" do
      expect(fu.escape_string("hello")).to eq("hello")
    end

    it "escapes backslash" do
      expect(fu.escape_string("a\\b")).to eq("a\\\\b")
    end

    it "escapes double quote" do
      expect(fu.escape_string('say "hi"')).to eq('say \\"hi\\"')
    end

    it "escapes newline" do
      expect(fu.escape_string("line1\nline2")).to eq("line1\\nline2")
    end

    it "escapes carriage return" do
      expect(fu.escape_string("a\rb")).to eq("a\\rb")
    end

    it "escapes tab" do
      expect(fu.escape_string("a\tb")).to eq("a\\tb")
    end

    it "escapes control characters as \\uXXXX" do
      expect(fu.escape_string("\x01")).to eq("\\u0001")
      expect(fu.escape_string("\x1F")).to eq("\\u001F")
    end

    it "preserves non-ASCII printable characters" do
      expect(fu.escape_string("Zürich")).to eq("Zürich")
      expect(fu.escape_string("你好")).to eq("你好")
      expect(fu.escape_string("🌍")).to eq("🌍")
    end

    it "handles empty string" do
      expect(fu.escape_string("")).to eq("")
    end

    it "escapes multiple special chars" do
      expect(fu.escape_string("a\tb\nc")).to eq("a\\tb\\nc")
    end
  end

  describe ".format_quoted_string" do
    it "wraps in double quotes" do
      expect(fu.format_quoted_string("hello")).to eq('"hello"')
    end

    it "escapes and wraps" do
      expect(fu.format_quoted_string("say \"hi\"")).to eq('"say \\"hi\\""')
    end

    it "handles empty string" do
      expect(fu.format_quoted_string("")).to eq('""')
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Modifier Formatting
  # ─────────────────────────────────────────────────────────────────────────

  describe ".format_modifier_prefix" do
    it "returns empty for nil" do
      expect(fu.format_modifier_prefix(nil)).to eq("")
    end

    it "returns empty for no modifiers" do
      mods = Odin::Types::OdinModifiers.new
      expect(fu.format_modifier_prefix(mods)).to eq("")
    end

    it "formats required only" do
      mods = Odin::Types::OdinModifiers.new(required: true)
      expect(fu.format_modifier_prefix(mods)).to eq("!")
    end

    it "formats confidential only" do
      mods = Odin::Types::OdinModifiers.new(confidential: true)
      expect(fu.format_modifier_prefix(mods)).to eq("*")
    end

    it "formats deprecated only" do
      mods = Odin::Types::OdinModifiers.new(deprecated: true)
      expect(fu.format_modifier_prefix(mods)).to eq("-")
    end

    it "formats combined in canonical order !*-" do
      mods = Odin::Types::OdinModifiers.new(required: true, confidential: true, deprecated: true)
      expect(fu.format_modifier_prefix(mods)).to eq("!*-")
    end

    it "formats !* combination" do
      mods = Odin::Types::OdinModifiers.new(required: true, confidential: true)
      expect(fu.format_modifier_prefix(mods)).to eq("!*")
    end

    it "formats !- combination" do
      mods = Odin::Types::OdinModifiers.new(required: true, deprecated: true)
      expect(fu.format_modifier_prefix(mods)).to eq("!-")
    end

    it "formats *- combination" do
      mods = Odin::Types::OdinModifiers.new(confidential: true, deprecated: true)
      expect(fu.format_modifier_prefix(mods)).to eq("*-")
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Value Formatting (Stringify)
  # ─────────────────────────────────────────────────────────────────────────

  describe ".format_value" do
    it "formats null" do
      expect(fu.format_value(Odin::Types::NULL)).to eq("~")
    end

    it "formats boolean true with ? prefix" do
      expect(fu.format_value(Odin::Types::TRUE_VAL)).to eq("?true")
    end

    it "formats boolean false with ? prefix" do
      expect(fu.format_value(Odin::Types::FALSE_VAL)).to eq("?false")
    end

    it "formats string with quotes" do
      expect(fu.format_value(Odin::Types::OdinString.new("hello"))).to eq('"hello"')
    end

    it "formats number with raw" do
      expect(fu.format_value(Odin::Types::OdinNumber.new(3.14, raw: "3.14"))).to eq("#3.14")
    end

    it "formats number without raw" do
      expect(fu.format_value(Odin::Types::OdinNumber.new(3.14))).to eq("#3.14")
    end

    it "formats integer" do
      expect(fu.format_value(Odin::Types::OdinInteger.new(42))).to eq("##42")
    end

    it "formats integer NO commas for large numbers" do
      expect(fu.format_value(Odin::Types::OdinInteger.new(1_000_000))).to eq("##1000000")
    end

    it "formats currency with 2 decimal places" do
      val = Odin::Types::OdinCurrency.new("99.99", decimal_places: 2)
      expect(fu.format_value(val)).to eq('#$99.99')
    end

    it "formats currency with code" do
      val = Odin::Types::OdinCurrency.new("100.00", currency_code: "USD", decimal_places: 2)
      expect(fu.format_value(val)).to eq('#$100.00:USD')
    end

    it "formats percent with raw" do
      val = Odin::Types::OdinPercent.new(0.15, raw: "0.15")
      expect(fu.format_value(val)).to eq("#%0.15")
    end

    it "formats date" do
      val = Odin::Types::OdinDate.new(Date.parse("2024-06-15"), raw: "2024-06-15")
      expect(fu.format_value(val)).to eq("2024-06-15")
    end

    it "formats timestamp" do
      val = Odin::Types::OdinTimestamp.new(DateTime.parse("2024-06-15T10:30:00Z"), raw: "2024-06-15T10:30:00Z")
      expect(fu.format_value(val)).to eq("2024-06-15T10:30:00Z")
    end

    it "formats time" do
      val = Odin::Types::OdinTime.new("T09:30:00")
      expect(fu.format_value(val)).to eq("T09:30:00")
    end

    it "formats duration" do
      val = Odin::Types::OdinDuration.new("P6M")
      expect(fu.format_value(val)).to eq("P6M")
    end

    it "formats reference" do
      val = Odin::Types::OdinReference.new("drivers[0]")
      expect(fu.format_value(val)).to eq("@drivers[0]")
    end

    it "formats binary" do
      val = Odin::Types::OdinBinary.new("SGVsbG8=")
      expect(fu.format_value(val)).to eq("^SGVsbG8=")
    end

    it "formats binary with algorithm" do
      val = Odin::Types::OdinBinary.new("SGVsbG8=", algorithm: "sha256")
      expect(fu.format_value(val)).to eq("^sha256:SGVsbG8=")
    end

    it "formats verb expression" do
      val = Odin::Types::OdinVerbExpression.new("upper", args: [Odin::Types::OdinString.new("hello")])
      expect(fu.format_value(val)).to eq('%upper "hello"')
    end

    it "formats custom verb expression" do
      val = Odin::Types::OdinVerbExpression.new("myVerb", is_custom: true, args: [])
      expect(fu.format_value(val)).to eq("%&myVerb")
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Canonical Value Formatting
  # ─────────────────────────────────────────────────────────────────────────

  describe ".format_canonical_value" do
    it "formats boolean true without prefix" do
      expect(fu.format_canonical_value(Odin::Types::TRUE_VAL)).to eq("true")
    end

    it "formats boolean false without prefix" do
      expect(fu.format_canonical_value(Odin::Types::FALSE_VAL)).to eq("false")
    end

    it "formats number stripping trailing zeros" do
      val = Odin::Types::OdinNumber.new(3.14, raw: "3.140")
      expect(fu.format_canonical_value(val)).to eq("#3.14")
    end

    it "formats whole number without .0" do
      val = Odin::Types::OdinNumber.new(42.0)
      expect(fu.format_canonical_value(val)).to eq("#42")
    end

    it "formats currency with min 2 decimal places" do
      val = Odin::Types::OdinCurrency.new("10", decimal_places: 0)
      expect(fu.format_canonical_value(val)).to eq('#$10.00')
    end

    it "formats currency code uppercase" do
      val = Odin::Types::OdinCurrency.new("50.00", currency_code: "gbp", decimal_places: 2)
      expect(fu.format_canonical_value(val)).to eq('#$50.00:GBP')
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Canonical Number
  # ─────────────────────────────────────────────────────────────────────────

  describe ".format_canonical_number" do
    it "strips trailing zeros" do
      expect(fu.format_canonical_number(3.14)).to eq("3.14")
    end

    it "strips all trailing zeros" do
      expect(fu.format_canonical_number(3.0)).to eq("3")
    end

    it "keeps integer as-is" do
      expect(fu.format_canonical_number(42.0)).to eq("42")
    end

    it "handles zero" do
      expect(fu.format_canonical_number(0.0)).to eq("0")
    end

    it "handles negative" do
      expect(fu.format_canonical_number(-3.14)).to eq("-3.14")
    end
  end
end
