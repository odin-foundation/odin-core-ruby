# frozen_string_literal: true

require "spec_helper"
require "bigdecimal"
require "date"

RSpec.describe "Odin::Types value classes" do
  # ── OdinNull ──────────────────────────────────────────────
  describe Odin::Types::OdinNull do
    subject { Odin::Types::NULL }

    it "has type :null" do
      expect(subject.type).to eq(:null)
    end

    it "has nil value" do
      expect(subject.value).to be_nil
    end

    it "is frozen" do
      expect(subject).to be_frozen
    end

    it "null? returns true" do
      expect(subject.null?).to be true
    end

    it "other type predicates return false" do
      expect(subject.boolean?).to be false
      expect(subject.string?).to be false
      expect(subject.numeric?).to be false
    end

    it "equals another OdinNull" do
      expect(Odin::Types::OdinNull.new).to eq(subject)
    end

    it "to_s returns ~" do
      expect(subject.to_s).to eq("~")
    end

    it "singleton constant exists" do
      expect(Odin::Types::NULL).to be_a(Odin::Types::OdinNull)
    end
  end

  # ── OdinBoolean ───────────────────────────────────────────
  describe Odin::Types::OdinBoolean do
    it "stores true value" do
      val = Odin::Types::OdinBoolean.new(true)
      expect(val.value).to be true
      expect(val.type).to eq(:boolean)
    end

    it "stores false value" do
      val = Odin::Types::OdinBoolean.new(false)
      expect(val.value).to be false
    end

    it "is frozen" do
      expect(Odin::Types::OdinBoolean.new(true)).to be_frozen
    end

    it "boolean? returns true" do
      expect(Odin::Types::OdinBoolean.new(true).boolean?).to be true
    end

    it "TRUE_VAL constant exists" do
      expect(Odin::Types::TRUE_VAL).to be_a(Odin::Types::OdinBoolean)
      expect(Odin::Types::TRUE_VAL.value).to be true
    end

    it "FALSE_VAL constant exists" do
      expect(Odin::Types::FALSE_VAL).to be_a(Odin::Types::OdinBoolean)
      expect(Odin::Types::FALSE_VAL.value).to be false
    end

    it "equality works" do
      expect(Odin::Types::OdinBoolean.new(true)).to eq(Odin::Types::OdinBoolean.new(true))
      expect(Odin::Types::OdinBoolean.new(true)).not_to eq(Odin::Types::OdinBoolean.new(false))
    end

    it "to_s returns string representation" do
      expect(Odin::Types::OdinBoolean.new(true).to_s).to eq("true")
      expect(Odin::Types::OdinBoolean.new(false).to_s).to eq("false")
    end
  end

  # ── OdinString ────────────────────────────────────────────
  describe Odin::Types::OdinString do
    it "stores string value" do
      val = Odin::Types::OdinString.new("hello")
      expect(val.value).to eq("hello")
      expect(val.type).to eq(:string)
    end

    it "is frozen" do
      expect(Odin::Types::OdinString.new("test")).to be_frozen
    end

    it "string? returns true" do
      expect(Odin::Types::OdinString.new("x").string?).to be true
    end

    it "equality works" do
      expect(Odin::Types::OdinString.new("a")).to eq(Odin::Types::OdinString.new("a"))
      expect(Odin::Types::OdinString.new("a")).not_to eq(Odin::Types::OdinString.new("b"))
    end

    it "handles empty string" do
      val = Odin::Types::OdinString.new("")
      expect(val.value).to eq("")
    end

    it "handles unicode" do
      val = Odin::Types::OdinString.new("こんにちは")
      expect(val.value).to eq("こんにちは")
    end
  end

  # ── OdinNumber ────────────────────────────────────────────
  describe Odin::Types::OdinNumber do
    it "stores float value" do
      val = Odin::Types::OdinNumber.new(3.14)
      expect(val.value).to be_within(0.001).of(3.14)
      expect(val.type).to eq(:number)
    end

    it "converts integer input to float" do
      val = Odin::Types::OdinNumber.new(42)
      expect(val.value).to eq(42.0)
      expect(val.value).to be_a(Float)
    end

    it "stores raw string" do
      val = Odin::Types::OdinNumber.new(3.14, raw: "3.14")
      expect(val.raw).to eq("3.14")
    end

    it "raw is nil by default" do
      expect(Odin::Types::OdinNumber.new(1.0).raw).to be_nil
    end

    it "is frozen" do
      expect(Odin::Types::OdinNumber.new(1.0)).to be_frozen
    end

    it "number? returns true, numeric? returns true" do
      val = Odin::Types::OdinNumber.new(1.0)
      expect(val.number?).to be true
      expect(val.numeric?).to be true
    end

    it "equality ignores raw" do
      a = Odin::Types::OdinNumber.new(3.14, raw: "3.14")
      b = Odin::Types::OdinNumber.new(3.14, raw: "3.140")
      expect(a).to eq(b)
    end
  end

  # ── OdinInteger ───────────────────────────────────────────
  describe Odin::Types::OdinInteger do
    it "stores integer value" do
      val = Odin::Types::OdinInteger.new(42)
      expect(val.value).to eq(42)
      expect(val.value).to be_a(Integer)
      expect(val.type).to eq(:integer)
    end

    it "converts float to integer" do
      val = Odin::Types::OdinInteger.new(3.7)
      expect(val.value).to eq(3)
    end

    it "stores raw" do
      val = Odin::Types::OdinInteger.new(42, raw: "42")
      expect(val.raw).to eq("42")
    end

    it "is frozen" do
      expect(Odin::Types::OdinInteger.new(0)).to be_frozen
    end

    it "integer? and numeric? return true" do
      val = Odin::Types::OdinInteger.new(1)
      expect(val.integer?).to be true
      expect(val.numeric?).to be true
    end

    it "handles large integers" do
      big = 2**64
      val = Odin::Types::OdinInteger.new(big)
      expect(val.value).to eq(big)
    end
  end

  # ── OdinCurrency ──────────────────────────────────────────
  describe Odin::Types::OdinCurrency do
    it "stores BigDecimal value" do
      val = Odin::Types::OdinCurrency.new("99.99")
      expect(val.value).to be_a(BigDecimal)
      expect(val.value).to eq(BigDecimal("99.99"))
      expect(val.type).to eq(:currency)
    end

    it "accepts BigDecimal directly" do
      bd = BigDecimal("100.50")
      val = Odin::Types::OdinCurrency.new(bd)
      expect(val.value).to eq(bd)
    end

    it "stores currency_code" do
      val = Odin::Types::OdinCurrency.new("50.00", currency_code: "USD")
      expect(val.currency_code).to eq("USD")
    end

    it "defaults decimal_places to 2" do
      val = Odin::Types::OdinCurrency.new("10.00")
      expect(val.decimal_places).to eq(2)
    end

    it "stores custom decimal_places" do
      val = Odin::Types::OdinCurrency.new("10.000", decimal_places: 3)
      expect(val.decimal_places).to eq(3)
    end

    it "stores raw" do
      val = Odin::Types::OdinCurrency.new("99.99", raw: "99.99")
      expect(val.raw).to eq("99.99")
    end

    it "is frozen" do
      expect(Odin::Types::OdinCurrency.new("1.00")).to be_frozen
    end

    it "currency? and numeric? return true" do
      val = Odin::Types::OdinCurrency.new("1.00")
      expect(val.currency?).to be true
      expect(val.numeric?).to be true
    end

    it "equality considers currency_code" do
      a = Odin::Types::OdinCurrency.new("100", currency_code: "USD")
      b = Odin::Types::OdinCurrency.new("100", currency_code: "EUR")
      expect(a).not_to eq(b)
    end
  end

  # ── OdinPercent ───────────────────────────────────────────
  describe Odin::Types::OdinPercent do
    it "stores float value" do
      val = Odin::Types::OdinPercent.new(0.15)
      expect(val.value).to be_within(0.001).of(0.15)
      expect(val.type).to eq(:percent)
    end

    it "stores raw" do
      val = Odin::Types::OdinPercent.new(0.15, raw: "0.15")
      expect(val.raw).to eq("0.15")
    end

    it "is frozen" do
      expect(Odin::Types::OdinPercent.new(0.0)).to be_frozen
    end

    it "percent? and numeric? return true" do
      val = Odin::Types::OdinPercent.new(0.5)
      expect(val.percent?).to be true
      expect(val.numeric?).to be true
    end
  end

  # ── OdinDate ──────────────────────────────────────────────
  describe Odin::Types::OdinDate do
    it "stores Date value" do
      d = Date.new(2024, 1, 15)
      val = Odin::Types::OdinDate.new(d)
      expect(val.value).to eq(d)
      expect(val.type).to eq(:date)
    end

    it "stores raw from date if not given" do
      d = Date.new(2024, 1, 15)
      val = Odin::Types::OdinDate.new(d)
      expect(val.raw).to eq("2024-01-15")
    end

    it "stores explicit raw" do
      d = Date.new(2024, 1, 15)
      val = Odin::Types::OdinDate.new(d, raw: "2024-01-15")
      expect(val.raw).to eq("2024-01-15")
    end

    it "is frozen" do
      expect(Odin::Types::OdinDate.new(Date.today)).to be_frozen
    end

    it "date? and temporal? return true" do
      val = Odin::Types::OdinDate.new(Date.today)
      expect(val.date?).to be true
      expect(val.temporal?).to be true
    end
  end

  # ── OdinTimestamp ─────────────────────────────────────────
  describe Odin::Types::OdinTimestamp do
    it "stores DateTime value" do
      dt = DateTime.new(2024, 1, 15, 10, 30, 0)
      val = Odin::Types::OdinTimestamp.new(dt)
      expect(val.value).to eq(dt)
      expect(val.type).to eq(:timestamp)
    end

    it "stores raw" do
      dt = DateTime.new(2024, 1, 15, 10, 30, 0)
      val = Odin::Types::OdinTimestamp.new(dt, raw: "2024-01-15T10:30:00Z")
      expect(val.raw).to eq("2024-01-15T10:30:00Z")
    end

    it "is frozen" do
      expect(Odin::Types::OdinTimestamp.new(DateTime.now)).to be_frozen
    end

    it "timestamp? and temporal? return true" do
      val = Odin::Types::OdinTimestamp.new(DateTime.now)
      expect(val.timestamp?).to be true
      expect(val.temporal?).to be true
    end
  end

  # ── OdinTime ──────────────────────────────────────────────
  describe Odin::Types::OdinTime do
    it "stores string value" do
      val = Odin::Types::OdinTime.new("T10:30:00")
      expect(val.value).to eq("T10:30:00")
      expect(val.type).to eq(:time)
    end

    it "is frozen" do
      expect(Odin::Types::OdinTime.new("T00:00:00")).to be_frozen
    end

    it "time? and temporal? return true" do
      val = Odin::Types::OdinTime.new("T12:00:00")
      expect(val.time?).to be true
      expect(val.temporal?).to be true
    end
  end

  # ── OdinDuration ──────────────────────────────────────────
  describe Odin::Types::OdinDuration do
    it "stores string value" do
      val = Odin::Types::OdinDuration.new("P1Y6M")
      expect(val.value).to eq("P1Y6M")
      expect(val.type).to eq(:duration)
    end

    it "is frozen" do
      expect(Odin::Types::OdinDuration.new("PT1H")).to be_frozen
    end

    it "duration? and temporal? return true" do
      val = Odin::Types::OdinDuration.new("P1D")
      expect(val.duration?).to be true
      expect(val.temporal?).to be true
    end
  end

  # ── OdinReference ─────────────────────────────────────────
  describe Odin::Types::OdinReference do
    it "stores path" do
      val = Odin::Types::OdinReference.new("policy.id")
      expect(val.path).to eq("policy.id")
      expect(val.value).to eq("policy.id")
      expect(val.type).to eq(:reference)
    end

    it "handles empty path (bare @)" do
      val = Odin::Types::OdinReference.new("")
      expect(val.path).to eq("")
    end

    it "is frozen" do
      expect(Odin::Types::OdinReference.new("x")).to be_frozen
    end

    it "reference? returns true" do
      expect(Odin::Types::OdinReference.new("x").reference?).to be true
    end

    it "to_s includes @" do
      expect(Odin::Types::OdinReference.new("foo.bar").to_s).to eq("@foo.bar")
    end
  end

  # ── OdinBinary ────────────────────────────────────────────
  describe Odin::Types::OdinBinary do
    it "stores data" do
      val = Odin::Types::OdinBinary.new("SGVsbG8=")
      expect(val.data).to eq("SGVsbG8=")
      expect(val.type).to eq(:binary)
    end

    it "stores algorithm" do
      val = Odin::Types::OdinBinary.new("abc123", algorithm: "sha256")
      expect(val.algorithm).to eq("sha256")
    end

    it "algorithm is nil by default" do
      expect(Odin::Types::OdinBinary.new("data").algorithm).to be_nil
    end

    it "is frozen" do
      expect(Odin::Types::OdinBinary.new("x")).to be_frozen
    end

    it "binary? returns true" do
      expect(Odin::Types::OdinBinary.new("x").binary?).to be true
    end
  end

  # ── OdinVerbExpression ────────────────────────────────────
  describe Odin::Types::OdinVerbExpression do
    it "stores verb name" do
      val = Odin::Types::OdinVerbExpression.new("upper")
      expect(val.verb).to eq("upper")
      expect(val.type).to eq(:verb)
    end

    it "stores is_custom flag" do
      val = Odin::Types::OdinVerbExpression.new("myVerb", is_custom: true)
      expect(val.is_custom).to be true
      expect(val.custom?).to be true
    end

    it "defaults is_custom to false" do
      val = Odin::Types::OdinVerbExpression.new("upper")
      expect(val.is_custom).to be false
      expect(val.custom?).to be false
    end

    it "stores args" do
      val = Odin::Types::OdinVerbExpression.new("concat", args: ["a", "b"])
      expect(val.args).to eq(["a", "b"])
    end

    it "defaults args to empty" do
      val = Odin::Types::OdinVerbExpression.new("noop")
      expect(val.args).to eq([])
    end

    it "is frozen" do
      expect(Odin::Types::OdinVerbExpression.new("x")).to be_frozen
    end

    it "verb? returns true" do
      expect(Odin::Types::OdinVerbExpression.new("x").verb?).to be true
    end
  end

  # ── OdinArray ─────────────────────────────────────────────
  describe Odin::Types::OdinArray do
    it "stores items" do
      items = [Odin::Types::OdinString.new("a"), Odin::Types::OdinInteger.new(1)]
      val = Odin::Types::OdinArray.new(items: items)
      expect(val.items).to eq(items)
      expect(val.type).to eq(:array)
    end

    it "defaults to empty items" do
      val = Odin::Types::OdinArray.new
      expect(val.items).to eq([])
    end

    it "size returns item count" do
      items = [Odin::Types::NULL, Odin::Types::NULL]
      val = Odin::Types::OdinArray.new(items: items)
      expect(val.size).to eq(2)
      expect(val.length).to eq(2)
    end

    it "[] accesses items by index" do
      items = [Odin::Types::OdinString.new("first")]
      val = Odin::Types::OdinArray.new(items: items)
      expect(val[0]).to eq(Odin::Types::OdinString.new("first"))
    end

    it "empty? works" do
      expect(Odin::Types::OdinArray.new.empty?).to be true
      expect(Odin::Types::OdinArray.new(items: [Odin::Types::NULL]).empty?).to be false
    end

    it "is frozen" do
      expect(Odin::Types::OdinArray.new).to be_frozen
    end

    it "array? returns true" do
      expect(Odin::Types::OdinArray.new.array?).to be true
    end
  end

  # ── OdinObject ────────────────────────────────────────────
  describe Odin::Types::OdinObject do
    it "stores entries" do
      entries = { "name" => Odin::Types::OdinString.new("test") }
      val = Odin::Types::OdinObject.new(entries: entries)
      expect(val.entries).to eq(entries)
      expect(val.type).to eq(:object)
    end

    it "defaults to empty entries" do
      val = Odin::Types::OdinObject.new
      expect(val.entries).to eq({})
    end

    it "[] accesses entries by key" do
      entries = { "x" => Odin::Types::OdinInteger.new(42) }
      val = Odin::Types::OdinObject.new(entries: entries)
      expect(val["x"]).to eq(Odin::Types::OdinInteger.new(42))
    end

    it "size, keys, empty? work" do
      val = Odin::Types::OdinObject.new(entries: { "a" => Odin::Types::NULL })
      expect(val.size).to eq(1)
      expect(val.keys).to eq(["a"])
      expect(val.empty?).to be false
    end

    it "is frozen" do
      expect(Odin::Types::OdinObject.new).to be_frozen
    end

    it "object? returns true" do
      expect(Odin::Types::OdinObject.new.object?).to be true
    end
  end

  # ── Modifier predicates on values ─────────────────────────
  describe "modifier predicates" do
    it "required? returns true when modifier set" do
      mods = Odin::Types::OdinModifiers.new(required: true)
      val = Odin::Types::OdinString.new("test", modifiers: mods)
      expect(val.required?).to be true
      expect(val.confidential?).to be false
      expect(val.deprecated?).to be false
    end

    it "confidential? returns true when modifier set" do
      mods = Odin::Types::OdinModifiers.new(confidential: true)
      val = Odin::Types::OdinString.new("secret", modifiers: mods)
      expect(val.confidential?).to be true
    end

    it "deprecated? returns true when modifier set" do
      mods = Odin::Types::OdinModifiers.new(deprecated: true)
      val = Odin::Types::OdinString.new("old", modifiers: mods)
      expect(val.deprecated?).to be true
    end

    it "returns false when no modifiers" do
      val = Odin::Types::OdinString.new("plain")
      expect(val.required?).to be false
      expect(val.confidential?).to be false
      expect(val.deprecated?).to be false
    end
  end

  # ── with_modifiers / with_directives ──────────────────────
  describe "with_modifiers" do
    it "creates new value with modifiers on OdinString" do
      val = Odin::Types::OdinString.new("test")
      mods = Odin::Types::OdinModifiers.new(required: true)
      new_val = val.with_modifiers(mods)
      expect(new_val.required?).to be true
      expect(new_val.value).to eq("test")
      expect(val.required?).to be false
    end

    it "creates new value with modifiers on OdinNull" do
      new_val = Odin::Types::NULL.with_modifiers(Odin::Types::OdinModifiers.new(confidential: true))
      expect(new_val.confidential?).to be true
      expect(new_val.null?).to be true
    end
  end

  describe "with_directives" do
    it "creates new value with directives" do
      dir = Odin::Types::OdinDirective.new("type", "string")
      val = Odin::Types::OdinInteger.new(42)
      new_val = val.with_directives([dir])
      expect(new_val.directives).to eq([dir])
      expect(new_val.value).to eq(42)
    end
  end

  # ── ValueType completeness ────────────────────────────────
  describe "ValueType" do
    it "has 16 types" do
      expect(Odin::Types::ValueType::ALL.size).to eq(16)
    end

    it "all types are symbols" do
      Odin::Types::ValueType::ALL.each do |t|
        expect(t).to be_a(Symbol)
      end
    end
  end
end
