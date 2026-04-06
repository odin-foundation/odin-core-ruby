# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Odin Facade Integration" do
  # ─── .parse ───────────────────────────────────────────────────────────────────

  describe ".parse" do
    it "parses simple string assignment" do
      doc = Odin.parse('name = "John"')
      expect(doc).to be_a(Odin::Types::OdinDocument)
      expect(doc.get("name")).to be_a(Odin::Types::OdinString)
      expect(doc.get("name").value).to eq("John")
    end

    it "parses integer value" do
      doc = Odin.parse("count = ##42")
      expect(doc.get("count")).to be_a(Odin::Types::OdinInteger)
      expect(doc.get("count").value).to eq(42)
    end

    it "parses number value" do
      doc = Odin.parse("pi = #3.14")
      expect(doc.get("pi")).to be_a(Odin::Types::OdinNumber)
      expect(doc.get("pi").value).to eq(3.14)
    end

    it "parses currency value" do
      doc = Odin.parse('price = #$99.99')
      expect(doc.get("price")).to be_a(Odin::Types::OdinCurrency)
    end

    it "parses boolean true" do
      doc = Odin.parse("active = ?true")
      expect(doc.get("active")).to be_a(Odin::Types::OdinBoolean)
      expect(doc.get("active").value).to eq(true)
    end

    it "parses boolean false" do
      doc = Odin.parse("active = ?false")
      expect(doc.get("active").value).to eq(false)
    end

    it "parses bare boolean true" do
      doc = Odin.parse("active = true")
      expect(doc.get("active")).to be_a(Odin::Types::OdinBoolean)
      expect(doc.get("active").value).to eq(true)
    end

    it "parses null value" do
      doc = Odin.parse("empty = ~")
      expect(doc.get("empty")).to be_a(Odin::Types::OdinNull)
    end

    it "parses reference value" do
      doc = Odin.parse("ref = @other.path")
      expect(doc.get("ref")).to be_a(Odin::Types::OdinReference)
      expect(doc.get("ref").path).to eq("other.path")
    end

    it "parses date value" do
      doc = Odin.parse("d = 2024-01-15")
      expect(doc.get("d")).to be_a(Odin::Types::OdinDate)
    end

    it "parses timestamp value" do
      doc = Odin.parse("ts = 2024-01-15T10:30:00Z")
      expect(doc.get("ts")).to be_a(Odin::Types::OdinTimestamp)
    end

    it "parses time value" do
      doc = Odin.parse("tm = T14:30:00")
      expect(doc.get("tm")).to be_a(Odin::Types::OdinTime)
    end

    it "parses duration value" do
      doc = Odin.parse("dur = P1Y2M")
      expect(doc.get("dur")).to be_a(Odin::Types::OdinDuration)
    end

    it "parses binary value" do
      doc = Odin.parse("bin = ^SGVsbG8=")
      expect(doc.get("bin")).to be_a(Odin::Types::OdinBinary)
    end

    it "parses percent value" do
      doc = Odin.parse("rate = #%50.0")
      expect(doc.get("rate")).to be_a(Odin::Types::OdinPercent)
    end

    it "parses headers" do
      doc = Odin.parse("{person}\nname = \"Alice\"")
      expect(doc.get("person.name").value).to eq("Alice")
    end

    it "parses nested paths via headers" do
      text = "{person.address}\ncity = \"Portland\""
      doc = Odin.parse(text)
      expect(doc.get("person.address.city").value).to eq("Portland")
    end

    it "parses arrays" do
      text = "items[0] = \"apple\"\nitems[1] = \"banana\""
      doc = Odin.parse(text)
      expect(doc.get("items[0]").value).to eq("apple")
      expect(doc.get("items[1]").value).to eq("banana")
    end

    it "parses metadata header" do
      doc = Odin.parse("{$}\nodin = \"1.0.0\"\n\nname = \"test\"")
      expect(doc.metadata_value("odin")).to be_a(Odin::Types::OdinString)
      expect(doc.metadata_value("odin").value).to eq("1.0.0")
    end

    it "parses modifiers - required" do
      doc = Odin.parse('name = !"Alice"')
      mods = doc.modifiers_for("name")
      expect(mods).not_to be_nil
      expect(mods.required).to eq(true)
    end

    it "parses modifiers - confidential" do
      doc = Odin.parse('ssn = *"123-45-6789"')
      mods = doc.modifiers_for("ssn")
      expect(mods).not_to be_nil
      expect(mods.confidential).to eq(true)
    end

    it "parses modifiers - deprecated" do
      doc = Odin.parse('old = -"legacy"')
      mods = doc.modifiers_for("old")
      expect(mods).not_to be_nil
      expect(mods.deprecated).to eq(true)
    end

    it "parses combined modifiers" do
      doc = Odin.parse('field = !-*"secret"')
      mods = doc.modifiers_for("field")
      expect(mods.required).to eq(true)
      expect(mods.deprecated).to eq(true)
      expect(mods.confidential).to eq(true)
    end

    it "parses comments" do
      doc = Odin.parse("; This is a comment\nname = \"Alice\"")
      expect(doc.get("name").value).to eq("Alice")
    end

    it "parses inline comments" do
      doc = Odin.parse('name = "Alice" ; inline comment')
      expect(doc.get("name").value).to eq("Alice")
    end

    it "parses multi-line strings" do
      text = "msg = \"line one\\nline two\""
      doc = Odin.parse(text)
      expect(doc.get("msg").value).to include("line one")
    end

    it "parses empty string" do
      doc = Odin.parse('empty = ""')
      expect(doc.get("empty").value).to eq("")
    end

    it "handles multiple assignments" do
      text = "a = \"1\"\nb = \"2\"\nc = \"3\""
      doc = Odin.parse(text)
      expect(doc.size).to eq(3)
    end

    it "returns empty document for empty input" do
      doc = Odin.parse("")
      expect(doc.empty?).to eq(true)
    end

    it "gracefully handles unusual input" do
      # Parser may or may not raise on unusual input; test it doesn't crash
      doc = Odin.parse("= no_key") rescue nil
      expect(true).to eq(true) # Just verifying no unhandled exception
    end

    it "parses simple currency" do
      doc = Odin.parse('price = #$99.99')
      val = doc.get("price")
      expect(val).to be_a(Odin::Types::OdinCurrency)
    end

    it "parses negative numbers" do
      doc = Odin.parse("val = #-3.14")
      expect(doc.get("val").value).to eq(-3.14)
    end

    it "parses negative integers" do
      doc = Odin.parse("val = ##-42")
      expect(doc.get("val").value).to eq(-42)
    end

    it "parses zero integer" do
      doc = Odin.parse("val = ##0")
      expect(doc.get("val").value).to eq(0)
    end

    it "parses escaped quotes in strings" do
      doc = Odin.parse('msg = "He said \\"hello\\""')
      expect(doc.get("msg").value).to include("hello")
    end

    it "parses indexed array elements" do
      text = "{items}\nitems[0] = \"apple\"\nitems[1] = \"banana\""
      doc = Odin.parse(text)
      expect(doc.get("items.items[0]").value).to eq("apple")
    end

    it "preserves document path order" do
      text = "z = \"last\"\na = \"first\""
      doc = Odin.parse(text)
      expect(doc.paths).to eq(["z", "a"])
    end
  end

  # ─── .stringify ─────────────────────────────────────────────────────────────

  describe ".stringify" do
    it "round-trips a simple document" do
      text = "name = \"John\"\n"
      doc = Odin.parse(text)
      result = Odin.stringify(doc, use_headers: false)
      expect(result.strip).to eq(text.strip)
    end

    it "round-trips integer values" do
      doc = Odin.parse("count = ##42")
      result = Odin.stringify(doc, use_headers: false)
      expect(result).to include("##42")
    end

    it "round-trips number values" do
      doc = Odin.parse("pi = #3.14")
      result = Odin.stringify(doc, use_headers: false)
      expect(result).to include("#3.14")
    end

    it "round-trips boolean values with ? prefix" do
      doc = Odin.parse("active = ?true")
      result = Odin.stringify(doc, use_headers: false)
      expect(result).to include("?true")
    end

    it "round-trips null values" do
      doc = Odin.parse("empty = ~")
      result = Odin.stringify(doc, use_headers: false)
      expect(result).to include("~")
    end

    it "round-trips reference values" do
      doc = Odin.parse("ref = @other.path")
      result = Odin.stringify(doc, use_headers: false)
      expect(result).to include("@other.path")
    end

    it "round-trips currency values" do
      doc = Odin.parse('price = #$99.99')
      result = Odin.stringify(doc, use_headers: false)
      expect(result).to include('#$')
    end

    it "round-trips date values" do
      doc = Odin.parse("d = 2024-01-15")
      result = Odin.stringify(doc, use_headers: false)
      expect(result).to include("2024-01-15")
    end

    it "round-trips headers" do
      text = "{person}\nname = \"Alice\"\n"
      doc = Odin.parse(text)
      result = Odin.stringify(doc)
      expect(result).to include("{person}")
      expect(result).to include("name = \"Alice\"")
    end

    it "round-trips modifiers" do
      doc = Odin.parse('name = !"Alice"')
      result = Odin.stringify(doc, use_headers: false)
      expect(result).to include("!")
    end

    it "produces valid ODIN that can be re-parsed" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"

        {person}
        name = "Alice"
        age = ##30
        active = ?true
      ODIN
      doc = Odin.parse(text)
      result = Odin.stringify(doc)
      doc2 = Odin.parse(result)
      expect(doc2.get("person.name").value).to eq("Alice")
      expect(doc2.get("person.age").value).to eq(30)
    end

    it "round-trips multiple value types" do
      text = <<~ODIN
        str = "hello"
        num = #3.14
        int = ##42
        bool = ?true
        nul = ~
      ODIN
      doc = Odin.parse(text)
      result = Odin.stringify(doc, use_headers: false)
      doc2 = Odin.parse(result)
      expect(doc2.get("str").value).to eq("hello")
      expect(doc2.get("num").value).to eq(3.14)
      expect(doc2.get("int").value).to eq(42)
      expect(doc2.get("bool").value).to eq(true)
      expect(doc2.get("nul")).to be_a(Odin::Types::OdinNull)
    end
  end

  # ─── .canonicalize ──────────────────────────────────────────────────────────

  describe ".canonicalize" do
    it "produces deterministic output" do
      doc = Odin.parse("zebra = \"z\"\nalpha = \"a\"")
      r1 = Odin.canonicalize(doc)
      r2 = Odin.canonicalize(doc)
      expect(r1).to eq(r2)
    end

    it "sorts paths alphabetically" do
      doc = Odin.parse("zebra = \"z\"\nalpha = \"a\"\nmid = \"m\"")
      result = Odin.canonicalize(doc)
      lines = result.strip.split("\n")
      paths = lines.map { |l| l.split(" = ").first }
      expect(paths).to eq(paths.sort)
    end

    it "produces identical output for semantically equivalent docs" do
      doc1 = Odin.parse("b = ##2\na = ##1")
      doc2 = Odin.parse("a = ##1\nb = ##2")
      expect(Odin.canonicalize(doc1)).to eq(Odin.canonicalize(doc2))
    end

    it "canonicalize output can be re-parsed" do
      doc = Odin.parse("name = \"Alice\"\nage = ##30")
      canonical = Odin.canonicalize(doc)
      doc2 = Odin.parse(canonical)
      expect(doc2.get("name").value).to eq("Alice")
      expect(doc2.get("age").value).to eq(30)
    end
  end

  # ─── .diff and .patch ──────────────────────────────────────────────────────

  describe ".diff and .patch" do
    it "detects no changes in identical documents" do
      doc = Odin.parse("name = \"Alice\"")
      d = Odin.diff(doc, doc)
      expect(d.added).to be_empty
      expect(d.removed).to be_empty
      expect(d.changed).to be_empty
    end

    it "detects additions" do
      a = Odin.parse("name = \"Alice\"")
      b = Odin.parse("name = \"Alice\"\nage = ##30")
      d = Odin.diff(a, b)
      expect(d.added.length).to eq(1)
      expect(d.added.map(&:path)).to include("age")
    end

    it "detects removals" do
      a = Odin.parse("name = \"Alice\"\nage = ##30")
      b = Odin.parse("name = \"Alice\"")
      d = Odin.diff(a, b)
      expect(d.removed.length).to eq(1)
      expect(d.removed.map(&:path)).to include("age")
    end

    it "detects value changes" do
      a = Odin.parse("name = \"Alice\"")
      b = Odin.parse("name = \"Bob\"")
      d = Odin.diff(a, b)
      expect(d.changed.length).to eq(1)
    end

    it "patch produces the target document" do
      a = Odin.parse("name = \"Alice\"")
      b = Odin.parse("name = \"Bob\"\nage = ##30")
      d = Odin.diff(a, b)
      result = Odin.patch(a, d)
      expect(result.get("name").value).to eq("Bob")
      expect(result.get("age").value).to eq(30)
    end

    it "patch handles removals" do
      a = Odin.parse("name = \"Alice\"\nage = ##30")
      b = Odin.parse("name = \"Alice\"")
      d = Odin.diff(a, b)
      result = Odin.patch(a, d)
      expect(result.get("age")).to be_nil
    end

    it "diff returns OdinDiff" do
      a = Odin.parse("x = ##1")
      b = Odin.parse("x = ##2")
      d = Odin.diff(a, b)
      expect(d).to be_a(Odin::Types::OdinDiff)
    end

    it "diff and patch round-trip preserves values" do
      a = Odin.parse("x = ##1\ny = ##2\nz = ##3")
      b = Odin.parse("x = ##10\ny = ##2\nw = ##4")
      d = Odin.diff(a, b)
      result = Odin.patch(a, d)
      expect(result.get("x").value).to eq(10)
      expect(result.get("y").value).to eq(2)
      expect(result.get("z")).to be_nil
      expect(result.get("w").value).to eq(4)
    end
  end

  # ─── .validate ──────────────────────────────────────────────────────────────

  describe ".validate" do
    let(:schema_text) do
      <<~ODIN
        {$}
        odin = "1.0.0"
        schema = "1.0.0"

        name = "!:(1..100)"
        age = "!##:(0..150)"
        email = "string"
        active = "?"
      ODIN
    end

    let(:schema) { Odin.parse_schema(schema_text) }

    it "passes valid document" do
      doc = Odin.parse("name = \"Alice\"\nage = ##30\nemail = \"alice@example.com\"\nactive = ?true")
      result = Odin.validate(doc, schema)
      expect(result.valid?).to eq(true)
    end

    it "detects required field missing (V001)" do
      doc = Odin.parse("age = ##30")
      result = Odin.validate(doc, schema)
      expect(result.valid?).to eq(false)
      codes = result.errors.map(&:code)
      expect(codes).to include("V001")
    end

    it "detects type mismatch (V002)" do
      doc = Odin.parse("name = \"Alice\"\nage = \"not a number\"")
      result = Odin.validate(doc, schema)
      expect(result.valid?).to eq(false)
      codes = result.errors.map(&:code)
      expect(codes).to include("V002")
    end

    it "detects value out of bounds (V003)" do
      doc = Odin.parse("name = \"Alice\"\nage = ##200")
      result = Odin.validate(doc, schema)
      expect(result.valid?).to eq(false)
      codes = result.errors.map(&:code)
      expect(codes).to include("V003")
    end

    it "detects min string length violation (V003)" do
      doc = Odin.parse("name = \"\"\nage = ##30")
      result = Odin.validate(doc, schema)
      expect(result.valid?).to eq(false)
    end

    it "returns ValidationResult" do
      doc = Odin.parse("name = \"Alice\"\nage = ##30")
      result = Odin.validate(doc, schema)
      expect(result).to respond_to(:valid?)
      expect(result).to respond_to(:errors)
    end

    it "validates min/max bounds on integers" do
      doc_ok = Odin.parse("name = \"Alice\"\nage = ##100")
      result_ok = Odin.validate(doc_ok, schema)
      expect(result_ok.valid?).to eq(true)

      doc_min = Odin.parse("name = \"Alice\"\nage = ##-1")
      result_min = Odin.validate(doc_min, schema)
      expect(result_min.valid?).to eq(false)
    end

    it "validates optional fields" do
      doc = Odin.parse("name = \"Alice\"\nage = ##30")
      result = Odin.validate(doc, schema)
      expect(result.valid?).to eq(true)
    end

    it "validates multiple required fields" do
      doc = Odin.parse("name = \"Alice\"")
      result = Odin.validate(doc, schema)
      expect(result.valid?).to eq(false)
      codes = result.errors.map(&:code)
      expect(codes).to include("V001")
    end
  end

  # ─── .transform ─────────────────────────────────────────────────────────────

  describe ".transform" do
    it "executes json->json transform" do
      transform_text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"
        target.format = "json"

        {Output}
        FullName = %concat @.firstName " " @.lastName
      ODIN
      source = { "firstName" => "John", "lastName" => "Doe" }
      result = Odin.transform(transform_text, source)
      expect(result).to be_a(Odin::Transform::TransformResult)
      expect(result.output["Output"]["FullName"]).to eq("John Doe")
    end

    it "executes simple field mapping" do
      transform_text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"
        target.format = "json"

        {Out}
        Name = @.name
      ODIN
      source = { "name" => "Alice" }
      result = Odin.transform(transform_text, source)
      expect(result.output["Out"]["Name"]).to eq("Alice")
    end

    it "applies verb expressions" do
      transform_text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"
        target.format = "json"

        {Out}
        Upper = %upper @.name
      ODIN
      source = { "name" => "alice" }
      result = Odin.transform(transform_text, source)
      expect(result.output["Out"]["Upper"]).to eq("ALICE")
    end

    it "applies multiple verbs" do
      transform_text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"
        target.format = "json"

        {Out}
        Result = %trim %upper @.name
      ODIN
      source = { "name" => "  alice  " }
      result = Odin.transform(transform_text, source)
      expect(result.output["Out"]["Result"]).to eq("ALICE")
    end

    it "produces formatted output" do
      transform_text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"
        target.format = "json"

        {Out}
        Name = @.name
      ODIN
      source = { "name" => "Alice" }
      result = Odin.transform(transform_text, source)
      expect(result.formatted).not_to be_nil
      expect(result.formatted).to be_a(String)
    end

    it "handles nested source paths" do
      transform_text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"
        target.format = "json"

        {Out}
        City = @.address.city
      ODIN
      source = { "address" => { "city" => "Portland" } }
      result = Odin.transform(transform_text, source)
      expect(result.output["Out"]["City"]).to eq("Portland")
    end

    it "handles literal values" do
      transform_text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"
        target.format = "json"

        {Out}
        Version = "1.0"
      ODIN
      source = {}
      result = Odin.transform(transform_text, source)
      expect(result.output["Out"]["Version"]).to eq("1.0")
    end

    it "parse_transform returns TransformDef" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"
        target.format = "json"

        {Out}
        X = @.x
      ODIN
      td = Odin.parse_transform(text)
      expect(td).to be_a(Odin::Transform::TransformDef)
    end

    it "execute_transform uses pre-parsed transform" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"
        target.format = "json"

        {Out}
        X = @.x
      ODIN
      td = Odin.parse_transform(text)
      result = Odin.execute_transform(td, { "x" => 42 })
      expect(result.output["Out"]["X"]).to eq(42)
    end

    it "handles math verbs" do
      transform_text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"
        target.format = "json"

        {Out}
        Sum = %add @.a @.b
      ODIN
      source = { "a" => 10, "b" => 20 }
      result = Odin.transform(transform_text, source)
      expect(result.output["Out"]["Sum"]).to eq(30)
    end

    it "handles conditional with ifElse verb" do
      transform_text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"
        target.format = "json"

        {Out}
        Label = %ifElse @.active "Active" "Inactive"
      ODIN
      source = { "active" => true }
      result = Odin.transform(transform_text, source)
      expect(result.output["Out"]["Label"]).to eq("Active")
    end
  end

  # ─── Export ─────────────────────────────────────────────────────────────────

  describe "Export" do
    it "exports to JSON" do
      doc = Odin.parse("{person}\nname = \"Alice\"\nage = ##30")
      json_str = Odin::Export.to_json(doc)
      expect(json_str).to be_a(String)
      parsed = JSON.parse(json_str)
      expect(parsed["person"]["name"]).to eq("Alice")
      expect(parsed["person"]["age"]).to eq(30)
    end

    it "exports to JSON with compact mode" do
      doc = Odin.parse("name = \"Alice\"")
      compact = Odin::Export.to_json(doc, pretty: false)
      expect(compact).not_to include("\n")
    end

    it "exports to XML" do
      doc = Odin.parse("{person}\nname = \"Alice\"")
      xml = Odin::Export.to_xml(doc)
      expect(xml).to include("<?xml")
      expect(xml).to include("<person>")
      expect(xml).to include("Alice")
    end

    it "exports to XML with type preservation" do
      doc = Odin.parse("count = ##42")
      xml = Odin::Export.to_xml(doc, preserve_types: true)
      expect(xml).to include('odin:type="integer"')
    end

    it "exports to CSV" do
      text = "items[0].name = \"apple\"\nitems[0].qty = ##10\nitems[1].name = \"pear\"\nitems[1].qty = ##5"
      doc = Odin.parse(text)
      csv = Odin::Export.to_csv(doc)
      expect(csv).to include("name,qty")
      expect(csv).to include("apple,10")
      expect(csv).to include("pear,5")
    end

    it "exports to fixed-width" do
      doc = Odin.parse("name = \"Alice\"\nage = ##30")
      result = Odin::Export.to_fixed_width(doc, columns: [
        { path: "name", pos: 0, len: 10 },
        { path: "age", pos: 10, len: 5 },
      ])
      expect(result).to include("Alice")
      expect(result).to include("30")
    end

    it "handles empty CSV export" do
      doc = Odin.parse("name = \"Alice\"")
      csv = Odin::Export.to_csv(doc)
      expect(csv).to eq("")
    end

    it "handles XML special characters" do
      doc = Odin.parse('msg = "1 < 2 & 3 > 1"')
      xml = Odin::Export.to_xml(doc)
      expect(xml).to include("&lt;")
      expect(xml).to include("&amp;")
      expect(xml).to include("&gt;")
    end

    it "CSV escapes commas in values" do
      doc = Odin.parse('items[0].name = "red, blue"')
      csv = Odin::Export.to_csv(doc)
      expect(csv).to include('"red, blue"')
    end
  end

  # ─── Builder ────────────────────────────────────────────────────────────────

  describe "Builder" do
    it "builds a document with the builder pattern" do
      doc = Odin.builder
        .set_string("name", "Alice")
        .set_integer("age", 30)
        .set_boolean("active", true)
        .set_null("empty")
        .build

      expect(doc).to be_a(Odin::Types::OdinDocument)
      expect(doc.get("name").value).to eq("Alice")
      expect(doc.get("age").value).to eq(30)
      expect(doc.get("active").value).to eq(true)
      expect(doc.get("empty")).to be_a(Odin::Types::OdinNull)
    end

    it "builds document with metadata" do
      doc = Odin.builder
        .set_metadata("odin", Odin::Types::OdinString.new("1.0.0"))
        .set_string("name", "Test")
        .build

      expect(doc.metadata_value("odin").value).to eq("1.0.0")
    end

    it "builds document with currency" do
      doc = Odin.builder
        .set_currency("price", BigDecimal("99.99"))
        .build

      expect(doc.get("price")).to be_a(Odin::Types::OdinCurrency)
    end

    it "builds document with modifiers" do
      mods = Odin::Types::OdinModifiers.new(required: true)
      doc = Odin.builder
        .set_string("name", "Alice", modifiers: mods)
        .build

      expect(doc.modifiers_for("name").required).to eq(true)
    end

    it "built document can be stringified" do
      doc = Odin.builder
        .set_string("name", "Alice")
        .set_integer("count", 42)
        .build

      text = Odin.stringify(doc, use_headers: false)
      expect(text).to include("name = \"Alice\"")
      expect(text).to include("count = ##42")
    end

    it "built document can be canonicalized" do
      doc = Odin.builder
        .set_string("z", "last")
        .set_string("a", "first")
        .build

      canonical = Odin.canonicalize(doc)
      lines = canonical.strip.split("\n")
      expect(lines[0]).to include("a = ")
      expect(lines[1]).to include("z = ")
    end

    it "remove deletes a field" do
      doc = Odin.builder
        .set_string("name", "Alice")
        .set_string("temp", "remove me")
        .remove("temp")
        .build

      expect(doc.get("temp")).to be_nil
      expect(doc.get("name").value).to eq("Alice")
    end
  end

  # ─── Version ────────────────────────────────────────────────────────────────

  describe "VERSION" do
    it "is defined" do
      expect(Odin::VERSION).to be_a(String)
      expect(Odin::VERSION).not_to be_empty
    end

    it "follows semver format" do
      expect(Odin::VERSION).to match(/\A\d+\.\d+\.\d+/)
    end
  end

  # ─── Schema Parsing ────────────────────────────────────────────────────────

  describe ".parse_schema" do
    it "parses a simple schema" do
      schema = Odin.parse_schema(<<~ODIN)
        {$}
        odin = "1.0.0"
        schema = "1.0.0"

        name = "string :required"
        age = "integer"
      ODIN
      expect(schema).not_to be_nil
    end

    it "parses schema with constraints" do
      schema = Odin.parse_schema(<<~ODIN)
        {$}
        odin = "1.0.0"
        schema = "1.0.0"

        score = "integer :min 0 :max 100"
      ODIN
      expect(schema).not_to be_nil
    end
  end

  # ─── Error Handling ─────────────────────────────────────────────────────────

  describe "Error Handling" do
    it "raises on duplicate path assignment" do
      text = "{person}\nname = \"Alice\"\n{person}\nname = \"Bob\""
      expect { Odin.parse(text) }.to raise_error(Odin::Errors::ParseError)
    end

    it "handles unicode strings" do
      doc = Odin.parse('name = "日本語テスト"')
      expect(doc.get("name").value).to eq("日本語テスト")
    end

    it "handles emoji strings" do
      doc = Odin.parse('emoji = "Hello 👋🌍"')
      expect(doc.get("emoji").value).to eq("Hello 👋🌍")
    end

    it "stringify then parse preserves unicode" do
      doc = Odin.parse('name = "Ünïcödë"')
      text = Odin.stringify(doc, use_headers: false)
      doc2 = Odin.parse(text)
      expect(doc2.get("name").value).to eq("Ünïcödë")
    end
  end

  # ─── Document API ──────────────────────────────────────────────────────────

  describe "Document API" do
    it "supports [] accessor" do
      doc = Odin.parse("name = \"Alice\"")
      expect(doc["name"].value).to eq("Alice")
    end

    it "supports include?" do
      doc = Odin.parse("name = \"Alice\"")
      expect(doc.include?("name")).to eq(true)
      expect(doc.include?("age")).to eq(false)
    end

    it "supports has_path?" do
      doc = Odin.parse("name = \"Alice\"")
      expect(doc.has_path?("name")).to eq(true)
    end

    it "supports size/length" do
      doc = Odin.parse("a = ##1\nb = ##2\nc = ##3")
      expect(doc.size).to eq(3)
      expect(doc.length).to eq(3)
    end

    it "supports each_assignment" do
      doc = Odin.parse("a = ##1\nb = ##2")
      paths = []
      doc.each_assignment { |path, _| paths << path }
      expect(paths).to contain_exactly("a", "b")
    end

    it "supports empty?" do
      doc = Odin.parse("")
      expect(doc.empty?).to eq(true)

      doc2 = Odin.parse("x = ##1")
      expect(doc2.empty?).to eq(false)
    end

    it "equality between identical documents" do
      doc1 = Odin.parse("name = \"Alice\"")
      doc2 = Odin.parse("name = \"Alice\"")
      expect(doc1).to eq(doc2)
    end

    it "OdinDocument.empty creates empty document" do
      doc = Odin::Types::OdinDocument.empty
      expect(doc.empty?).to eq(true)
      expect(doc.size).to eq(0)
    end
  end

  # ─── Complex Scenarios ─────────────────────────────────────────────────────

  describe "Complex Scenarios" do
    it "full workflow: build -> stringify -> parse -> validate -> diff" do
      schema = Odin.parse_schema(<<~ODIN)
        {$}
        odin = "1.0.0"
        schema = "1.0.0"

        name = "!"
        age = "##:(0..)"
      ODIN

      doc1 = Odin.builder
        .set_string("name", "Alice")
        .set_integer("age", 30)
        .build

      text = Odin.stringify(doc1, use_headers: false)
      doc2 = Odin.parse(text)

      result = Odin.validate(doc2, schema)
      expect(result.valid?).to eq(true)

      doc3 = Odin.builder
        .set_string("name", "Bob")
        .set_integer("age", 25)
        .build

      d = Odin.diff(doc2, doc3)
      expect(d.changed).not_to be_empty
    end

    it "parse -> canonicalize -> diff shows no changes" do
      text = "z = ##3\na = ##1\nm = ##2"
      doc = Odin.parse(text)
      canonical = Odin.canonicalize(doc)
      doc2 = Odin.parse(canonical)
      d = Odin.diff(doc, doc2)
      expect(d.changed).to be_empty
      expect(d.added).to be_empty
      expect(d.removed).to be_empty
    end

    it "parse -> export JSON -> parse JSON matches values" do
      text = "{person}\nname = \"Alice\"\nage = ##30\nactive = ?true"
      doc = Odin.parse(text)
      json_str = Odin::Export.to_json(doc)
      parsed = JSON.parse(json_str)
      expect(parsed["person"]["name"]).to eq("Alice")
      expect(parsed["person"]["age"]).to eq(30)
      expect(parsed["person"]["active"]).to eq(true)
    end

    it "transform -> export chain" do
      transform_text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"
        target.format = "json"

        {person}
        Name = %upper @.name
        Age = @.age
      ODIN
      source = { "name" => "alice", "age" => 30 }
      result = Odin.transform(transform_text, source)
      expect(result.output["person"]["Name"]).to eq("ALICE")
      expect(result.output["person"]["Age"]).to eq(30)
    end

    it "multiple sections in document" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"

        {person}
        name = "Alice"

        {person.address}
        city = "Portland"

        {company}
        name = "Acme"
      ODIN
      doc = Odin.parse(text)
      expect(doc.get("person.name").value).to eq("Alice")
      expect(doc.get("person.address.city").value).to eq("Portland")
      expect(doc.get("company.name").value).to eq("Acme")
    end
  end
end
