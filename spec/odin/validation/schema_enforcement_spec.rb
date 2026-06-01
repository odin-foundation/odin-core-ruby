# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Schema-validation enforcement" do
  HEADER = %({$}\nodin = "1.0.0"\nschema = "1.0.0"\n\n)
  PLACEHOLDER = %({root}\nx = "")

  def run(schema_text, input_text)
    schema = Odin.parse_schema(HEADER + schema_text)
    doc = Odin.parse(input_text)
    Odin.validate(doc, schema)
  end

  def codes_at(result, path)
    result.errors.select { |e| e.path == path }.map(&:code)
  end

  describe "invariant expression evaluation" do
    it "passes a three-term additive invariant" do
      r = run(
        "{order}\nsubtotal = #\$\ntax = #\$\nshipping = #\$\ntotal = #\$\n:invariant total = subtotal + tax + shipping",
        "{order}\nsubtotal = #\$10.00\ntax = #\$1.00\nshipping = #\$2.00\ntotal = #\$13.00"
      )
      expect(r.valid?).to be(true)
    end

    it "fails a three-term additive invariant when inconsistent" do
      r = run(
        "{order}\nsubtotal = #\$\ntax = #\$\nshipping = #\$\ntotal = #\$\n:invariant total = subtotal + tax + shipping",
        "{order}\nsubtotal = #\$10.00\ntax = #\$1.00\nshipping = #\$2.00\ntotal = #\$99.00"
      )
      expect(r.valid?).to be(false)
      expect(codes_at(r, "order")).to include("V008")
    end

    it "evaluates parentheses and precedence" do
      schema = "{discount}\nsubtotal = #\$\npercentage = #\nfixed_amount = #\$\ntotal = #\$\n" \
               ":invariant total = subtotal - (subtotal * percentage / 100) - fixed_amount"
      good = "{discount}\nsubtotal = #\$100.00\npercentage = #10\nfixed_amount = #\$5.00\ntotal = #\$85.00"
      bad  = "{discount}\nsubtotal = #\$100.00\npercentage = #10\nfixed_amount = #\$5.00\ntotal = #\$80.00"
      expect(run(schema, good).valid?).to be(true)
      expect(run(schema, bad).valid?).to be(false)
    end

    it "evaluates logical OR" do
      schema = "{discount}\npercentage = #\nfixed_amount = #\$\n:invariant percentage == 0 || fixed_amount == 0"
      expect(run(schema, "{discount}\npercentage = #0\nfixed_amount = #\$5.00").valid?).to be(true)
      expect(run(schema, "{discount}\npercentage = #10\nfixed_amount = #\$5.00").valid?).to be(false)
    end

    it "evaluates logical AND and negation" do
      schema = "{f}\na = #\nb = #\n:invariant !(a > 10) && b < 5"
      expect(run(schema, "{f}\na = #3\nb = #2").valid?).to be(true)
      expect(run(schema, "{f}\na = #20\nb = #2").valid?).to be(false)
    end

    it "evaluates modulo" do
      schema = "{n}\nx = ##\n:invariant x % 2 == 0"
      expect(run(schema, "{n}\nx = ##4").valid?).to be(true)
      expect(run(schema, "{n}\nx = ##5").valid?).to be(false)
    end

    it "compares temporal operands" do
      schema = "{r}\nstart = date\nend = date\n:invariant end >= start"
      expect(run(schema, "{r}\nstart = 2020-01-01\nend = 2020-02-01").valid?).to be(true)
      expect(run(schema, "{r}\nstart = 2020-03-01\nend = 2020-02-01").valid?).to be(false)
    end

    it "treats a null operand as false (V008)" do
      r = run(
        "{o}\ntotal = #\$\nsubtotal = #\$\ntax = ~#\$\n:invariant total = subtotal + tax",
        "{o}\ntotal = #\$10.00\nsubtotal = #\$10.00\ntax = ~"
      )
      expect(r.valid?).to be(false)
      expect(codes_at(r, "o")).to include("V008")
    end

    it "does not apply when an operand field is absent" do
      r = run(
        "{o}\ntotal = #\$\nsubtotal = #\$\ntax = #\$\n:invariant total = subtotal + tax",
        "{o}\ntotal = #\$10.00"
      )
      expect(r.valid?).to be(true)
    end

    it "reports a malformed invariant expression as V008" do
      r = run("{o}\nx = #\n:invariant x + + ", "{o}\nx = #1")
      expect(r.valid?).to be(false)
      expect(codes_at(r, "o")).to include("V008")
    end
  end

  describe "currency decimal-place enforcement" do
    it "accepts a value with the declared places" do
      expect(run("{w}\nbtc = #\$.8", "{w}\nbtc = #\$1.00000000").valid?).to be(true)
    end

    it "rejects a value with too few places (V003)" do
      r = run("{w}\nbtc = #\$.8", "{w}\nbtc = #\$1.00")
      expect(r.valid?).to be(false)
      expect(codes_at(r, "w.btc")).to include("V003")
    end

    it "defaults currency to two places" do
      expect(run("{w}\nprice = #\$", "{w}\nprice = #\$9.99").valid?).to be(true)
      expect(run("{w}\nprice = #\$", "{w}\nprice = #\$9.999").valid?).to be(false)
    end
  end

  describe "percent bounds enforcement" do
    it "accepts an in-range percent" do
      expect(run("{r}\nrate = #%:(0..1)", "{r}\nrate = #%0.5").valid?).to be(true)
    end

    it "rejects an out-of-range percent (V003)" do
      r = run("{r}\nrate = #%:(0..1)", "{r}\nrate = #%1.5")
      expect(r.valid?).to be(false)
      expect(codes_at(r, "r.rate")).to include("V003")
    end

    it "rejects a percent below the minimum" do
      expect(run("{r}\nrate = #%:(0.1..1)", "{r}\nrate = #%0.05").valid?).to be(false)
    end
  end

  describe "override restrictiveness" do
    it "accepts an override that narrows bounds" do
      schema = "{@base}\namount = #\$:(0..1000)\n\n{@narrow}\n= @base :override\namount = #\$:(0..100)"
      expect(run(schema, PLACEHOLDER).valid?).to be(true)
    end

    it "rejects an override that widens bounds (V017)" do
      r = run("{@base}\namount = #\$:(0..100)\n\n{@wide}\n= @base :override\namount = #\$:(0..1000)", PLACEHOLDER)
      expect(r.valid?).to be(false)
      expect(codes_at(r, "@wide.amount")).to include("V017")
    end

    it "allows optional to required but not the reverse" do
      expect(run("{@base}\nname =\n\n{@d}\n= @base :override\nname = !", PLACEHOLDER).valid?).to be(true)
      r = run("{@base}\nname = !\n\n{@d}\n= @base :override\nname =", PLACEHOLDER)
      expect(r.valid?).to be(false)
      expect(codes_at(r, "@d.name")).to include("V017")
    end

    it "allows removing nullability but not adding it" do
      expect(run("{@base}\nx = ~#\n\n{@d}\n= @base :override\nx = #", PLACEHOLDER).valid?).to be(true)
      r = run("{@base}\nx = #\n\n{@d}\n= @base :override\nx = ~#", PLACEHOLDER)
      expect(r.valid?).to be(false)
      expect(codes_at(r, "@d.x")).to include("V017")
    end

    it "rejects changing the base type (V017)" do
      r = run("{@base}\nx = #\n\n{@d}\n= @base :override\nx =", PLACEHOLDER)
      expect(r.valid?).to be(false)
      expect(codes_at(r, "@d.x")).to include("V017")
    end

    it "enforces override rules on path-level compositions" do
      r = run("{@base}\namount = #\$:(0..100)\n\n{order}\n= @base :override\namount = #\$:(0..1000)", PLACEHOLDER)
      expect(r.valid?).to be(false)
      expect(codes_at(r, "order.amount")).to include("V017")
    end

    it "does not flag fields the override does not touch" do
      schema = "{@base}\na = #\$:(0..100)\nb = !\n\n{@d}\n= @base :override\na = #\$:(0..50)"
      expect(run(schema, PLACEHOLDER).valid?).to be(true)
    end
  end

  describe "intersection field conflicts" do
    it "rejects same-name fields with differing definitions (V017)" do
      r = run("{@a}\nx = !\n\n{@b}\nx = !##\n\n{cust}\n= @a & @b", "{cust}\nx = ##5")
      expect(r.valid?).to be(false)
      expect(codes_at(r, "@cust.x")).to include("V017")
    end

    it "accepts disjoint or identical member fields" do
      schema = "{@a}\nx = !\nname = !\n\n{@b}\nx = !\nage = !##\n\n{cust}\n= @a & @b"
      input = "{cust}\nx = \"hi\"\nname = \"n\"\nage = ##5"
      expect(run(schema, input).valid?).to be(true)
    end

    it "reports conflict for a three-way intersection" do
      r = run("{@a}\nx = !\n\n{@b}\ny = !\n\n{@c}\nx = !##\n\n{cust}\n= @a & @b & @c", "{cust}\nx = \"hi\"\ny = \"z\"")
      expect(r.valid?).to be(false)
      expect(codes_at(r, "@cust.x")).to include("V017")
    end
  end

  describe "tabular column rules" do
    it "accepts primitive columns" do
      expect(run("{contacts[] : name, email}\nname = !\nemail = !",
                 "{contacts[0]}\nname = \"a\"\nemail = \"b\"").valid?).to be(true)
    end

    it "rejects a column referencing a defined type (V017)" do
      r = run("{@addr}\nline1 = !\n\n{customers[] : name, address}\nname = !\naddress = @addr",
              "{customers[0]}\nname = \"a\"")
      expect(r.valid?).to be(false)
      expect(codes_at(r, "customers[].address")).to include("V017")
    end

    it "accepts primitive columns of differing types" do
      expect(run("{rows[] : id, label}\nid = !##\nlabel = !",
                 "{rows[0]}\nid = ##1\nlabel = \"x\"").valid?).to be(true)
    end
  end

  describe "default value rules" do
    it "accepts a default within constraints on an optional field" do
      expect(run("{root}\npriority = ##:(1..5) ##3", PLACEHOLDER).valid?).to be(true)
    end

    it "rejects a default on a required field (V017)" do
      r = run("{root}\nstatus = !(\"a\", \"b\") \"a\"", "{root}\nstatus = \"a\"")
      expect(r.valid?).to be(false)
      expect(codes_at(r, "root.status")).to include("V017")
    end

    it "rejects a default that violates bounds (V017)" do
      r = run("{root}\npriority = ##:(1..5) ##9", PLACEHOLDER)
      expect(r.valid?).to be(false)
      expect(codes_at(r, "root.priority")).to include("V017")
    end

    it "rejects a default outside the enum (V017)" do
      r = run("{root}\nstatus = (\"a\", \"b\") \"c\"", PLACEHOLDER)
      expect(r.valid?).to be(false)
      expect(codes_at(r, "root.status")).to include("V017")
    end

    it "accepts a default that matches the enum" do
      expect(run("{root}\nstatus = (\"a\", \"b\") \"a\"", PLACEHOLDER).valid?).to be(true)
    end
  end
end
