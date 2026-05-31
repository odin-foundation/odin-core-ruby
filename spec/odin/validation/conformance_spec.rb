# frozen_string_literal: true

require_relative "../../spec_helper"

# Conformance specs mirroring the schema-validator fixes: type intersections,
# temporal bounds, percent type, typed defaults, union edge cases, pattern
# conditionals, glued temporal directives, field typeRefs, invariant null operands.
RSpec.describe "Schema validator conformance" do
  def parse_schema(body)
    Odin.parse_schema("{$}\nodin = \"1.0.0\"\nschema = \"1.0.0\"\n\n#{body}")
  end

  def validate(schema_body, input)
    schema = Odin.parse_schema("{$}\nodin = \"1.0.0\"\nschema = \"1.0.0\"\n\n#{schema_body}")
    doc = Odin.parse(input)
    Odin.validate(doc, schema)
  end

  # ── Fix 1: type intersection ──

  describe "type intersection (= @a & @b)" do
    let(:schema_body) { "{@hasName}\nname = !\n\n{@hasAge}\nage = !##\n\n{customer}\n= @hasName & @hasAge" }

    it "stores both members on the _composition field" do
      schema = parse_schema(schema_body)
      comp = schema.fields["customer._composition"]
      expect(comp).not_to be_nil
      expect(comp.type_ref).to eq("@hasName&hasAge")
    end

    it "passes when all members' required fields are present" do
      result = validate(schema_body, "{customer}\nname = \"Bob\"\nage = ##5")
      expect(result.valid?).to be(true)
    end

    it "reports V001 when a member's required field is missing" do
      result = validate(schema_body, "{customer}\nname = \"Bob\"")
      err = result.errors.find { |e| e.code == "V001" && e.path == "customer.age" }
      expect(err).not_to be_nil
    end

    it "reports V013 for an unresolved member type" do
      body = "{@hasName}\nname = !\n\n{customer}\n= @hasName & @doesNotExist"
      result = validate(body, "{customer}\nname = \"Bob\"")
      expect(result.errors.map(&:code)).to include("V013")
    end
  end

  # ── Fix 2: temporal range bounds ──

  describe "date range bounds" do
    let(:schema_body) { "{root}\nd = date:(2020-06-15..2020-06-20)" }

    it "preserves temporal literals as strings" do
      schema = parse_schema(schema_body)
      bounds = schema.fields["root.d"].constraints.first
      expect([bounds.min, bounds.max]).to eq(["2020-06-15", "2020-06-20"])
    end

    it "passes for a date within range" do
      expect(validate(schema_body, "{root}\nd = 2020-06-17").valid?).to be(true)
    end

    it "fails V003 below the minimum" do
      result = validate(schema_body, "{root}\nd = 2020-06-10")
      expect(result.errors.map(&:code)).to include("V003")
    end

    it "fails V003 above the maximum" do
      result = validate(schema_body, "{root}\nd = 2020-06-25")
      expect(result.errors.map(&:code)).to include("V003")
    end
  end

  # ── Fix 3: percent type ──

  describe "percent type (#%)" do
    it "parses as a first-class percent type" do
      schema = parse_schema("{root}\ntax = #" + "%")
      expect(schema.fields["root.tax"].field_type).to eq(Odin::Types::SchemaFieldType::PERCENT)
    end

    it "accepts a percent value" do
      expect(validate("{root}\ntax = #" + "%", "{root}\ntax = #" + "%0.15").valid?).to be(true)
    end

    it "rejects a non-percent value with V002" do
      result = validate("{root}\ntax = #" + "%", "{root}\ntax = \"fifteen\"")
      expect(result.errors.map(&:code)).to include("V002")
    end
  end

  # ── Fix 4: typed default values ──

  describe "typed default values" do
    it "captures a bare integer default ##3" do
      d = parse_schema("{root}\na = ##3").fields["root.a"].default_value
      expect([d.class, d.value]).to eq([Odin::Types::OdinInteger, 3])
    end

    it "captures a bare number default #0.05" do
      d = parse_schema("{root}\nb = #0.05").fields["root.b"].default_value
      expect([d.class, d.value]).to eq([Odin::Types::OdinNumber, 0.05])
    end

    it "captures a bare currency default" do
      d = parse_schema("{root}\nc = #" + "$5.00").fields["root.c"].default_value
      expect([d.class, d.value.to_f]).to eq([Odin::Types::OdinCurrency, 5.0])
    end

    it "captures a bare percent default" do
      d = parse_schema("{root}\np = #" + "%0.15").fields["root.p"].default_value
      expect([d.class, d.value]).to eq([Odin::Types::OdinPercent, 0.15])
    end

    it "captures a default trailing a bounds constraint" do
      field = parse_schema("{root}\npriority = ##:(1..5) ##3").fields["root.priority"]
      expect(field.default_value.value).to eq(3)
      expect(field.constraints.first.min).to eq(1)
      expect(field.constraints.first.max).to eq(5)
    end
  end

  # ── Fix 5: union edge cases ──

  describe "union types" do
    it "keeps both members of date|timestamp" do
      field = parse_schema("{root}\nu = date|timestamp").fields["root.u"]
      expect(field.union_members).to eq([Odin::Types::SchemaFieldType::DATE,
                                         Odin::Types::SchemaFieldType::TIMESTAMP])
    end

    it "keeps number and null members of #|~" do
      field = parse_schema("{root}\nn = #|~").fields["root.n"]
      expect(field.union_members).to eq([Odin::Types::SchemaFieldType::NUMBER,
                                         Odin::Types::SchemaFieldType::NULL])
    end

    it "accepts a null value for a union with a null member" do
      expect(validate("{root}\nn = #|~", "{root}\nn = ~").valid?).to be(true)
    end

    it "accepts a timestamp for a date|timestamp union" do
      expect(validate("{root}\nu = date|timestamp", "{root}\nu = 2020-06-17T10:00:00Z").valid?).to be(true)
    end
  end

  # ── Fix 6: :if after a pattern constraint ──

  describe ":if after a pattern" do
    let(:schema_body) { "{root}\nfield = !:/^[a-z]+$/:if method = paypal\nmethod = " }

    it "parses the trailing conditional" do
      field = parse_schema(schema_body).fields["root.field"]
      expect(field.constraints.first.pattern).to eq("^[a-z]+$")
      cond = field.conditionals.first
      expect([cond.field, cond.operator, cond.value]).to eq(["method", "=", "paypal"])
    end

    it "fails V010 when the condition holds and the field is missing" do
      result = validate(schema_body, "{root}\nmethod = \"paypal\"")
      expect(result.errors.map(&:code)).to include("V010")
    end

    it "is optional when the condition fails" do
      expect(validate(schema_body, "{root}\nmethod = \"stripe\"").valid?).to be(true)
    end

    it "still enforces the pattern on present values" do
      result = validate(schema_body, "{root}\nfield = \"ABC123\"\nmethod = \"paypal\"")
      expect(result.errors.map(&:code)).to include("V004")
    end
  end

  # ── Fix 7: glued temporal directives ──

  describe "glued temporal directives" do
    it "keeps the timestamp type and immutable flag" do
      field = parse_schema("{root}\ncreated_at = !timestamp:immutable").fields["root.created_at"]
      expect(field.field_type).to eq(Odin::Types::SchemaFieldType::TIMESTAMP)
      expect(field.required).to be(true)
      expect(field.immutable).to be(true)
    end

    it "keeps the date type and computed flag" do
      field = parse_schema("{root}\nstamp = date:computed").fields["root.stamp"]
      expect(field.field_type).to eq(Odin::Types::SchemaFieldType::DATE)
      expect(field.computed).to be(true)
    end
  end

  # ── Fix 8: field-level typeRef recursive validation ──

  describe "field typeRef recursive validation" do
    let(:schema_body) { "{@address}\nstreet = !\ncity = !\n\n{customer}\nname = !\nbilling = @address" }

    it "enforces nested required fields when the sub-object is present" do
      result = validate(schema_body, "{customer}\nname = \"X\"\nbilling.street = \"Main\"")
      err = result.errors.find { |e| e.code == "V001" && e.path == "customer.billing.city" }
      expect(err).not_to be_nil
    end

    it "does not require nested fields when the optional sub-object is absent" do
      expect(validate(schema_body, "{customer}\nname = \"X\"").valid?).to be(true)
    end

    it "passes when all nested required fields are present" do
      result = validate(schema_body, "{customer}\nname = \"X\"\nbilling.street = \"Main\"\nbilling.city = \"NYC\"")
      expect(result.valid?).to be(true)
    end
  end

  # ── Fix 9: invariant null operands ──

  describe "invariant null operands" do
    it "fails V008 for an arithmetic invariant with a null operand" do
      body = "{order}\ntotal = #" + "$\nsubtotal = #" + "$\ntax = ~#" + "$\n:invariant total = subtotal + tax"
      input = "{order}\ntotal = #" + "$10.00\nsubtotal = #" + "$10.00\ntax = ~"
      result = validate(body, input)
      err = result.errors.find { |e| e.code == "V008" && e.path == "order" }
      expect(err).not_to be_nil
    end

    it "passes an arithmetic invariant when all operands are present and consistent" do
      body = "{order}\ntotal = #" + "$\nsubtotal = #" + "$\ntax = #" + "$\n:invariant total = subtotal + tax"
      input = "{order}\ntotal = #" + "$12.00\nsubtotal = #" + "$10.00\ntax = #" + "$2.00"
      expect(validate(body, input).valid?).to be(true)
    end

    it "fails V008 for a comparison invariant with a null operand" do
      body = "{range}\nstart = ~#\nend = ~#\n:invariant end >= start"
      result = validate(body, "{range}\nend = #5\nstart = ~")
      expect(result.errors.map(&:code)).to include("V008")
    end
  end
end
