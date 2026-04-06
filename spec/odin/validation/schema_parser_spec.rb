# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Odin::Validation::SchemaParser do
  let(:parser) { described_class.new }

  def parse(text)
    parser.parse_schema(text)
  end

  # ── Metadata ──

  describe "schema metadata" do
    it "parses schema version from metadata" do
      schema = parse("{$}\nodin = \"1.0.0\"\nschema = \"1.0.0\"")
      expect(schema.metadata["odin"]).to eq("1.0.0")
    end

    it "parses schema name" do
      schema = parse("{$}\nodin = \"1.0.0\"\nschema = \"1.0.0\"\nid = \"test-schema\"")
      expect(schema.metadata["id"]).to eq("test-schema")
    end

    it "parses schema description" do
      schema = parse("{$}\nodin = \"1.0.0\"\ndescription = \"A test schema\"")
      expect(schema.metadata["description"]).to eq("A test schema")
    end

    it "parses schema version" do
      schema = parse("{$}\nodin = \"1.0.0\"\nschema = \"2.0.0\"")
      expect(schema.metadata["schema"]).to eq("2.0.0")
    end

    it "handles missing metadata fields gracefully" do
      schema = parse("{$}\nodin = \"1.0.0\"")
      expect(schema.metadata["schema"]).to be_nil
    end

    it "parses title metadata" do
      schema = parse("{$}\nodin = \"1.0.0\"\ntitle = \"My Schema\"")
      expect(schema.metadata["title"]).to eq("My Schema")
    end

    it "returns OdinSchema type" do
      schema = parse("{$}\nodin = \"1.0.0\"")
      expect(schema).to be_a(Odin::Types::OdinSchema)
    end

    it "metadata is a hash" do
      schema = parse("{$}\nodin = \"1.0.0\"")
      expect(schema.metadata).to be_a(Hash)
    end
  end

  # ── Field types ──

  describe "field type parsing" do
    it "parses string field (default)" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nname = \"!\"")
      field = schema.fields["name"]
      expect(field).not_to be_nil
      expect(field.required).to be true
    end

    it "parses integer field" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nage = \"##\"")
      field = schema.fields["age"]
      expect(field.field_type).to eq(:integer)
    end

    it "parses number field" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nrate = \"#\"")
      field = schema.fields["rate"]
      expect(field.field_type).to eq(:number)
    end

    it "parses boolean field" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nactive = \"?\"")
      field = schema.fields["active"]
      expect(field.field_type).to eq(:boolean)
    end

    it "parses currency field" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nprice = \"#{'#$'}\"")
      field = schema.fields["price"]
      expect(field.field_type).to eq(:currency)
    end

    it "parses percent field" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\ntax = \"#{'#%'}\"")
      field = schema.fields["tax"]
      expect(field.field_type).to eq(:percent)
    end

    it "parses date field" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nborn = \"date\"")
      field = schema.fields["born"]
      expect(field.field_type).to eq(:date)
    end

    it "parses timestamp field" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\ncreated = \"timestamp\"")
      field = schema.fields["created"]
      expect(field.field_type).to eq(:timestamp)
    end

    it "parses time field" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nstart = \"time\"")
      field = schema.fields["start"]
      expect(field.field_type).to eq(:time)
    end

    it "parses duration field" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nterm = \"duration\"")
      field = schema.fields["term"]
      expect(field.field_type).to eq(:duration)
    end

    it "parses reference field" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nparent = \"@\"")
      field = schema.fields["parent"]
      expect(field.field_type).to eq(:reference)
    end

    it "parses binary field" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\ndata = \"^\"")
      field = schema.fields["data"]
      expect(field.field_type).to eq(:binary)
    end

    it "parses reference with target path" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nbilling = \"@address\"")
      field = schema.fields["billing"]
      expect(field.field_type).to eq(:reference)
      expect(field.type_ref).to eq("@address")
    end
  end

  # ── Modifiers ──

  describe "modifier parsing" do
    it "parses required modifier" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nname = \"!\"")
      expect(schema.fields["name"].required).to be true
    end

    it "parses nullable modifier" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nnotes = \"~\"")
      expect(schema.fields["notes"].nullable).to be true
    end

    it "parses redacted modifier" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nssn = \"*\"")
      expect(schema.fields["ssn"].redacted).to be true
    end

    it "parses deprecated modifier" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nold_field = \"-\"")
      expect(schema.fields["old_field"].deprecated).to be true
    end

    it "parses combined modifiers !*" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nssn = \"!*\"")
      field = schema.fields["ssn"]
      expect(field.required).to be true
      expect(field.redacted).to be true
    end

    it "parses required boolean !?" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nactive = \"!?\"")
      field = schema.fields["active"]
      expect(field.required).to be true
      expect(field.field_type).to eq(:boolean)
    end

    it "parses required integer !##" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\ncount = \"!##\"")
      field = schema.fields["count"]
      expect(field.required).to be true
      expect(field.field_type).to eq(:integer)
    end
  end

  # ── Constraints ──

  describe "constraint parsing" do
    it "parses bounds constraint with range" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nage = \"##:(0..150)\"")
      field = schema.fields["age"]
      bounds = field.constraints.find { |c| c.kind == :bounds }
      expect(bounds).not_to be_nil
      expect(bounds.min).to eq(0)
      expect(bounds.max).to eq(150)
    end

    it "parses bounds with min only" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nqty = \"##:(1..)\"")
      field = schema.fields["qty"]
      bounds = field.constraints.find { |c| c.kind == :bounds }
      expect(bounds.min).to eq(1)
      expect(bounds.max).to be_nil
    end

    it "parses bounds with max only" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nlen = \":(..100)\"")
      field = schema.fields["len"]
      bounds = field.constraints.find { |c| c.kind == :bounds }
      expect(bounds.min).to be_nil
      expect(bounds.max).to eq(100)
    end

    it "parses exact bounds" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\ncode = \":(3)\"")
      field = schema.fields["code"]
      bounds = field.constraints.find { |c| c.kind == :bounds }
      expect(bounds.min).to eq(3)
      expect(bounds.max).to eq(3)
    end

    it "parses pattern constraint" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nzip = \":/^\\\\d{5}$/\"")
      field = schema.fields["zip"]
      pattern = field.constraints.find { |c| c.kind == :pattern }
      expect(pattern).not_to be_nil
      expect(pattern.pattern).to include("\\d{5}")
    end

    it "parses enum constraint" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nstatus = \"(draft, published, archived)\"")
      field = schema.fields["status"]
      enum = field.constraints.find { |c| c.kind == :enum }
      expect(enum).not_to be_nil
      expect(enum.values).to eq(["draft", "published", "archived"])
    end

    it "parses format constraint" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nemail_addr = \":format email\"")
      field = schema.fields["email_addr"]
      fmt = field.constraints.find { |c| c.kind == :format }
      expect(fmt).not_to be_nil
      expect(fmt.format_name).to eq("email")
    end

    it "parses unique constraint" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nid = \":unique\"")
      field = schema.fields["id"]
      unique = field.constraints.find { |c| c.kind == :unique }
      expect(unique).not_to be_nil
    end

    it "parses combined required + type + bounds" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nage = \"!##:(0..150)\"")
      field = schema.fields["age"]
      expect(field.required).to be true
      expect(field.field_type).to eq(:integer)
      bounds = field.constraints.find { |c| c.kind == :bounds }
      expect(bounds.min).to eq(0)
    end

    it "parses float bounds" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nprice = \"#:(0.0..999999.99)\"")
      field = schema.fields["price"]
      bounds = field.constraints.find { |c| c.kind == :bounds }
      expect(bounds.min).to eq(0.0)
      expect(bounds.max).to eq(999999.99)
    end

    it "parses multiple constraints on one field" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\ncode = \":(3..10):/^[A-Z]+$/\"")
      field = schema.fields["code"]
      expect(field.constraints.length).to eq(2)
    end
  end

  # ── Conditionals ──

  describe "conditional parsing" do
    it "parses :if conditional" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\ncard_number = \"!:if method = card\"")
      field = schema.fields["card_number"]
      expect(field.conditionals.length).to eq(1)
      cond = field.conditionals.first
      expect(cond.field).to eq("method")
      expect(cond.operator).to eq("=")
      expect(cond.value).to eq("card")
    end

    it "parses :unless conditional" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\npassword = \"!:unless sso_enabled\"")
      field = schema.fields["password"]
      cond = field.conditionals.first
      expect(cond.unless).to be true
    end

    it "parses shorthand :if (boolean)" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nfield = \":if active\"")
      field = schema.fields["field"]
      cond = field.conditionals.first
      expect(cond.field).to eq("active")
      expect(cond.value).to eq("true")
    end

    it "parses :if with != operator" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nfallback = \":if status != active\"")
      field = schema.fields["fallback"]
      cond = field.conditionals.first
      expect(cond.operator).to eq("!=")
    end

    it "parses :if with > operator" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\ndiscount = \":if amount > 100\"")
      field = schema.fields["discount"]
      cond = field.conditionals.first
      expect(cond.operator).to eq(">")
      expect(cond.value).to eq("100")
    end
  end

  # ── Directives ──

  describe "field directive parsing" do
    it "parses :computed directive" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\ntotal = \"!#:computed\"")
      field = schema.fields["total"]
      expect(field.computed).to be true
    end

    it "parses :immutable directive" do
      schema = parse("{$}\nodin = \"1.0.0\"\n\nid = \"!:immutable\"")
      field = schema.fields["id"]
      expect(field.immutable).to be true
    end
  end

  # ── Type definitions ──

  describe "type definitions" do
    it "parses a type section into schema types" do
      # Types are represented as path-based sections in ODIN
      # We build the schema using the group_by_section logic
      doc_text = <<~ODIN
        {$}
        odin = "1.0.0"

        {address}
        line1 = "!"
        city = "!"
        zip = ":/^\\\\d{5}$/"
      ODIN
      schema = parse(doc_text)
      # Fields should be under address section
      expect(schema.fields["address.line1"]).not_to be_nil
      expect(schema.fields["address.line1"].required).to be true
    end

    it "parses multiple sections" do
      doc_text = <<~ODIN
        {$}
        odin = "1.0.0"

        {customer}
        name = "!"
        email = "!"

        {order}
        id = "!"
        total = "#"
      ODIN
      schema = parse(doc_text)
      expect(schema.fields["customer.name"]).not_to be_nil
      expect(schema.fields["order.id"]).not_to be_nil
    end
  end

  # ── Schema return structure ──

  describe "schema structure" do
    it "has types hash" do
      schema = parse("{$}\nodin = \"1.0.0\"")
      expect(schema.types).to be_a(Hash)
    end

    it "has fields hash" do
      schema = parse("{$}\nodin = \"1.0.0\"")
      expect(schema.fields).to be_a(Hash)
    end

    it "has arrays hash" do
      schema = parse("{$}\nodin = \"1.0.0\"")
      expect(schema.arrays).to be_a(Hash)
    end

    it "has imports array" do
      schema = parse("{$}\nodin = \"1.0.0\"")
      expect(schema.imports).to be_a(Array)
    end

    it "has object_constraints hash" do
      schema = parse("{$}\nodin = \"1.0.0\"")
      expect(schema.object_constraints).to be_a(Hash)
    end
  end
end
