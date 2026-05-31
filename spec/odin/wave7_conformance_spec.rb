# frozen_string_literal: true

require_relative "../spec_helper"

# Conformance specs for the second-pass fixes: canonical numeric precision,
# canonical modifier order, :unless inversion, :computed exclusion, binary size
# bounds, decimal-place enforcement, and lookup onMissing reporting.
RSpec.describe "Wave-7 conformance" do
  def canonical(input)
    Odin.canonicalize(Odin.parse(input))
  end

  def validate(schema_body, input)
    schema = Odin.parse_schema("{$}\nodin = \"1.0.0\"\nschema = \"1.0.0\"\n\n#{schema_body}")
    Odin.validate(Odin.parse(input), schema)
  end

  # ── Canonical numeric precision (raw preserved) ──

  describe "canonical numeric precision" do
    it "preserves integers beyond Float safe range" do
      expect(canonical("big = ##9007199254740993")).to eq("big = ##9007199254740993\n")
    end

    it "preserves a 20-digit integer" do
      expect(canonical("huge = ##12345678901234567890")).to eq("huge = ##12345678901234567890\n")
    end

    it "preserves a high-precision decimal" do
      expect(canonical("pi = #3.14159265358979323846")).to eq("pi = #3.14159265358979323846\n")
    end

    it "preserves a currency integer part beyond Float range" do
      expect(canonical('amt = #$12345678901234567890.50')).to eq("amt = \#$12345678901234567890.50\n")
    end

    it "preserves a high-precision currency fraction" do
      expect(canonical('amt = #$123.450000000000000000')).to eq("amt = \#$123.450000000000000000\n")
    end
  end

  # ── Canonical modifier order !-* ──

  describe "canonical modifier order" do
    it "emits required-deprecated-confidential as !-*" do
      expect(canonical("x = !-*\"secret\"")).to eq("x = !-*\"secret\"\n")
    end

    it "emits required+deprecated as !-" do
      expect(canonical("x = !-\"secret\"")).to eq("x = !-\"secret\"\n")
    end

    it "emits required+confidential as !*" do
      expect(canonical("x = !*\"secret\"")).to eq("x = !*\"secret\"\n")
    end
  end

  # ── :unless is the inverse of :if ──

  describe ":unless conditional requirement" do
    let(:schema) { "{Person}\nstatus =\nphone = ! :unless status = \"inactive\"" }

    it "is not required when the condition is true" do
      expect(validate(schema, "{Person}\nstatus = \"inactive\"").valid?).to be(true)
    end

    it "is required when the condition is false" do
      result = validate(schema, "{Person}\nstatus = \"active\"")
      expect(result.valid?).to be(false)
      expect(result.errors.map(&:code)).to include("V010")
    end

    it "is required when the condition field is absent" do
      result = validate(schema, "{Person}\nname = \"x\"")
      expect(result.valid?).to be(false)
      expect(result.errors.map(&:code)).to include("V010")
    end
  end

  # ── :computed input exclusion ──

  describe ":computed required exclusion" do
    it "does not flag an absent computed required field" do
      result = validate("{Order}\ntotal = !# :computed", "{Order}\nname = \"x\"")
      expect(result.valid?).to be(true)
    end
  end

  # ── Binary size bounds (V003) ──

  describe "binary size bounds" do
    it "accepts a value of exact byte length" do
      expect(validate("{R}\nhash = ^:(4)", "{R}\nhash = ^AAAAAA==").valid?).to be(true)
    end

    it "rejects a value below the byte length" do
      result = validate("{R}\nhash = ^:(4)", "{R}\nhash = ^AAAA")
      expect(result.errors.map(&:code)).to include("V003")
    end

    it "rejects a value above the byte length" do
      result = validate("{R}\nhash = ^:(4)", "{R}\nhash = ^AAAAAAA=")
      expect(result.errors.map(&:code)).to include("V003")
    end

    it "rejects an algorithm-tagged value of the wrong byte length" do
      result = validate("{R}\nhash = ^sha256:(32)", "{R}\nhash = ^sha256:AAAAAAAAAAAAAAAAAAAAAA==")
      expect(result.errors.map(&:code)).to include("V003")
    end
  end

  # ── Decimal places (#.N) (V003) ──

  describe "decimal place enforcement" do
    it "accepts a value with exactly N places" do
      expect(validate("{R}\nrate = #.4", "{R}\nrate = #1.2345").valid?).to be(true)
    end

    it "rejects a value with too few places" do
      result = validate("{R}\nrate = #.4", "{R}\nrate = #1.23")
      expect(result.errors.map(&:code)).to include("V003")
    end

    it "rejects a value with too many places" do
      result = validate("{R}\nrate = #.4", "{R}\nrate = #1.23456")
      expect(result.errors.map(&:code)).to include("V003")
    end
  end

  # ── Unknown vs custom verbs ──

  describe "verb error policy" do
    def run(transform_text)
      td = Odin.parse_transform(transform_text)
      source = Odin::Transform::SourceParsers.parse_json('{"name":"x"}')
      Odin::Transform::TransformEngine.new.execute(td, source)
    end

    it "surfaces an unknown built-in verb as an error" do
      result = run(<<~ODIN)
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"
        target.format = "json"

        {root}
        out = %nonexistentVerb @.name
      ODIN
      expect(result.errors).not_to be_empty
    end

    it "echoes the first argument of an unregistered custom verb" do
      result = run(<<~ODIN)
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"
        target.format = "json"

        {root}
        out = %&customThing @.name
      ODIN
      expect(result.errors).to be_empty
      expect(result.output["root"]["out"]).to eq("x")
    end
  end

  # ── %lookup onMissing reporting ──

  describe "%lookup onMissing" do
    def run(policy, code)
      transform_text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"
        target.format = "json"
        target.onMissing = "#{policy}"

        {$table.Codes[code, label]}
        "A", "Alpha"

        {root}
        out = %lookup Codes.label @.code
      ODIN
      td = Odin.parse_transform(transform_text)
      source = Odin::Transform::SourceParsers.parse_json(%({"code":"#{code}"}))
      Odin::Transform::TransformEngine.new.execute(td, source)
    end

    it "is silent by default" do
      expect(run("skip", "Z").errors).to be_empty
    end

    it "reports a miss as an error when onMissing is fail" do
      expect(run("fail", "Z").errors).not_to be_empty
    end

    it "reports a miss as a warning when onMissing is warn" do
      result = run("warn", "Z")
      expect(result.errors).to be_empty
      expect(result.warnings).not_to be_empty
    end

    it "still resolves a hit without reporting" do
      result = run("fail", "A")
      expect(result.errors).to be_empty
      expect(result.output["root"]["out"]).to eq("Alpha")
    end
  end
end
