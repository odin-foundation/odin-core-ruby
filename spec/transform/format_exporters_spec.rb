# frozen_string_literal: true

require "spec_helper"
require "bigdecimal"

RSpec.describe Odin::Transform::FormatExporters do
  FE = Odin::Transform::FormatExporters
  DV = Odin::Types::DynValue unless defined?(DV)

  # ── JSON Export ──

  describe ".to_json" do
    it "exports simple object" do
      v = DV.of_object({ "name" => DV.of_string("John"), "age" => DV.of_integer(30) })
      json = FE.to_json(v)
      parsed = JSON.parse(json)
      expect(parsed["name"]).to eq("John")
      expect(parsed["age"]).to eq(30)
    end

    it "exports nested objects" do
      v = DV.of_object({
        "person" => DV.of_object({ "name" => DV.of_string("John") })
      })
      json = FE.to_json(v)
      parsed = JSON.parse(json)
      expect(parsed["person"]["name"]).to eq("John")
    end

    it "exports arrays" do
      v = DV.of_array([DV.of_integer(1), DV.of_integer(2), DV.of_integer(3)])
      json = FE.to_json(v)
      parsed = JSON.parse(json)
      expect(parsed).to eq([1, 2, 3])
    end

    it "exports null as JSON null" do
      v = DV.of_object({ "x" => DV.of_null })
      json = FE.to_json(v)
      parsed = JSON.parse(json)
      expect(parsed["x"]).to be_nil
    end

    it "exports booleans" do
      v = DV.of_object({ "t" => DV.of_bool(true), "f" => DV.of_bool(false) })
      json = FE.to_json(v)
      parsed = JSON.parse(json)
      expect(parsed["t"]).to be true
      expect(parsed["f"]).to be false
    end

    it "exports currency as number" do
      v = DV.of_object({ "price" => DV.of_currency(99.99) })
      json = FE.to_json(v)
      parsed = JSON.parse(json)
      expect(parsed["price"]).to be_within(0.01).of(99.99)
    end

    it "supports compact mode" do
      v = DV.of_object({ "a" => DV.of_integer(1) })
      json = FE.to_json(v, pretty: false)
      expect(json).not_to include("\n")
    end

    it "pretty prints by default" do
      v = DV.of_object({ "a" => DV.of_integer(1) })
      json = FE.to_json(v)
      expect(json).to include("\n")
    end

    it "exports reference as string" do
      v = DV.of_object({ "ref" => DV.of_reference("path.to.field") })
      json = FE.to_json(v)
      parsed = JSON.parse(json)
      expect(parsed["ref"]).to eq("@path.to.field")
    end

    it "exports binary as string" do
      v = DV.of_object({ "data" => DV.of_binary("SGVsbG8=") })
      json = FE.to_json(v)
      parsed = JSON.parse(json)
      expect(parsed["data"]).to eq("^SGVsbG8=")
    end
  end

  # ── ODIN Export ──

  describe ".to_odin" do
    it "emits {$} header with odin version" do
      v = DV.of_object({ "name" => DV.of_string("test") })
      odin = FE.to_odin(v)
      expect(odin).to include("{$}")
      expect(odin).to include('odin = "1.0.0"')
    end

    it "emits ?true and ?false for booleans" do
      v = DV.of_object({ "active" => DV.of_bool(true), "deleted" => DV.of_bool(false) })
      odin = FE.to_odin(v)
      expect(odin).to include("?true")
      expect(odin).to include("?false")
    end

    it "emits # prefix for numbers" do
      v = DV.of_object({ "pi" => DV.of_float(3.14) })
      odin = FE.to_odin(v)
      expect(odin).to include("#3.14")
    end

    it "emits ## prefix for integers" do
      v = DV.of_object({ "count" => DV.of_integer(42) })
      odin = FE.to_odin(v)
      expect(odin).to include("##42")
    end

    it "emits #$ prefix for currency" do
      v = DV.of_object({ "price" => DV.of_currency(BigDecimal("99.99"), 2, "USD") })
      odin = FE.to_odin(v)
      expect(odin).to include("#$99.99:USD")
    end

    it "emits #% prefix for percent" do
      v = DV.of_object({ "rate" => DV.of_percent(50.0) })
      odin = FE.to_odin(v)
      expect(odin).to include("#%50.0")
    end

    it "emits ~ for null" do
      v = DV.of_object({ "empty" => DV.of_null })
      odin = FE.to_odin(v)
      expect(odin).to include("empty = ~")
    end

    it "emits @ prefix for reference" do
      v = DV.of_object({ "ref" => DV.of_reference("path.to.field") })
      odin = FE.to_odin(v)
      expect(odin).to include("@path.to.field")
    end

    it "emits ^ prefix for binary" do
      v = DV.of_object({ "data" => DV.of_binary("SGVsbG8=") })
      odin = FE.to_odin(v)
      expect(odin).to include("^SGVsbG8=")
    end

    it "emits quoted strings" do
      v = DV.of_object({ "name" => DV.of_string("John") })
      odin = FE.to_odin(v)
      expect(odin).to include('"John"')
    end

    it "generates tabular arrays" do
      items = [
        DV.of_object({ "Name" => DV.of_string("Widget"), "Price" => DV.of_currency(BigDecimal("9.99")) }),
        DV.of_object({ "Name" => DV.of_string("Gadget"), "Price" => DV.of_currency(BigDecimal("19.99")) })
      ]
      v = DV.of_object({ "Items" => DV.of_array(items) })
      odin = FE.to_odin(v)
      expect(odin).to include("{Items[] : Name, Price}")
      expect(odin).to include('"Widget"')
      expect(odin).to include('"Gadget"')
    end

    it "handles nested objects as sections" do
      # Single-child objects are leaf chains: Customer.Name = "John"
      v = DV.of_object({
        "Customer" => DV.of_object({
          "Name" => DV.of_string("John"),
          "Age" => DV.of_integer(30)
        })
      })
      odin = FE.to_odin(v, header: false)
      expect(odin).to include("{Customer}")
      expect(odin).to include('Name = "John"')
      expect(odin).to include("Age = ##30")
    end

    it "handles modifier prefixes" do
      v = DV.of_object({ "field" => DV.of_string("secret") })
      odin = FE.to_odin(v, modifiers: { "field" => { required: true, confidential: true } })
      expect(odin).to include('!*"secret"')
    end

    it "modifier prefix order is !-*" do
      v = DV.of_object({ "f" => DV.of_string("val") })
      odin = FE.to_odin(v, modifiers: { "f" => { required: true, deprecated: true, confidential: true } })
      expect(odin).to include('!-*"val"')
    end

    it "can skip header" do
      v = DV.of_object({ "x" => DV.of_integer(1) })
      odin = FE.to_odin(v, header: false)
      expect(odin).not_to include("{$}")
    end

    it "escapes strings with special characters" do
      v = DV.of_object({ "s" => DV.of_string("line1\nline2") })
      odin = FE.to_odin(v)
      expect(odin).to include("\\n")
    end

    it "handles large numbers with normalized scientific notation" do
      v = DV.of_object({ "big" => DV.of_float(1e18) })
      odin = FE.to_odin(v)
      # Should use normalized scientific notation (lowercase e with explicit sign)
      match = odin.match(/#(\S+)/)
      expect(match[1]).to match(/e\+/) if match
      expect(match[1]).not_to match(/E/) if match
    end
  end

  # ── XML Export ──

  describe ".to_xml" do
    it "generates valid XML" do
      v = DV.of_object({ "name" => DV.of_string("John") })
      xml = FE.to_xml(v)
      expect(xml).to include('<?xml version="1.0"')
      expect(xml).to include("<name>John</name>")
    end

    it "handles nested objects" do
      v = DV.of_object({
        "person" => DV.of_object({ "name" => DV.of_string("John") })
      })
      xml = FE.to_xml(v)
      expect(xml).to include("<person>")
      expect(xml).to include("<name>John</name>")
      expect(xml).to include("</person>")
    end

    it "handles arrays as repeated elements" do
      v = DV.of_object({
        "items" => DV.of_array([DV.of_string("a"), DV.of_string("b")])
      })
      xml = FE.to_xml(v)
      expect(xml).to include("<items>a</items>")
      expect(xml).to include("<items>b</items>")
    end

    it "handles null with odin:type attribute" do
      v = DV.of_object({ "empty" => DV.of_null })
      xml = FE.to_xml(v)
      expect(xml).to include('xmlns:odin="https://odin.foundation/ns"')
      expect(xml).to include('<empty odin:type="null"></empty>')
    end

    it "escapes special characters" do
      v = DV.of_object({ "text" => DV.of_string("a < b & c") })
      xml = FE.to_xml(v)
      expect(xml).to include("a &lt; b &amp; c")
    end

    it "sanitizes element names starting with digits" do
      v = DV.of_object({ "1item" => DV.of_string("test") })
      xml = FE.to_xml(v)
      expect(xml).to include("<_1item>")
    end

    it "uses custom root element" do
      v = DV.of_object({ "name" => DV.of_string("test") })
      xml = FE.to_xml(v, root: "data")
      expect(xml).to include("<data>")
      expect(xml).to include("</data>")
    end

    it "includes odin namespace when typed values present" do
      v = DV.of_object({
        "name" => DV.of_string("Alice"),
        "age" => DV.of_integer(30),
        "active" => DV.of_bool(true)
      })
      xml = FE.to_xml(v)
      expect(xml).to include('xmlns:odin="https://odin.foundation/ns"')
      expect(xml).to include('odin:type="integer"')
      expect(xml).to include('odin:type="boolean"')
    end

    it "omits odin namespace when only string values" do
      v = DV.of_object({
        "name" => DV.of_string("Alice"),
        "city" => DV.of_string("Springfield")
      })
      xml = FE.to_xml(v)
      expect(xml).not_to include("xmlns:odin")
      expect(xml).not_to include("odin:type")
    end

    it "emits type attributes for various types" do
      v = DV.of_object({
        "count" => DV.of_integer(42),
        "price" => DV.of_float(9.99),
        "active" => DV.of_bool(true),
        "name" => DV.of_string("test")
      })
      xml = FE.to_xml(v)
      expect(xml).to include('<count odin:type="integer">42</count>')
      expect(xml).to include('<price odin:type="number">9.99</price>')
      expect(xml).to include('<active odin:type="boolean">true</active>')
      expect(xml).to include("<name>test</name>")
      expect(xml).not_to include('<name odin:type')
    end
  end

  # ── CSV Export ──

  describe ".to_csv" do
    it "exports array of objects" do
      items = [
        DV.of_object({ "name" => DV.of_string("John"), "age" => DV.of_integer(30) }),
        DV.of_object({ "name" => DV.of_string("Jane"), "age" => DV.of_integer(25) })
      ]
      v = DV.of_array(items)
      csv = FE.to_csv(v)
      lines = csv.strip.split("\n")
      expect(lines[0]).to eq("name,age")
      expect(lines[1]).to eq("John,30")
      expect(lines[2]).to eq("Jane,25")
    end

    it "quotes fields with commas" do
      items = [DV.of_object({ "desc" => DV.of_string("a, b, c") })]
      v = DV.of_array(items)
      csv = FE.to_csv(v)
      expect(csv).to include('"a, b, c"')
    end

    it "quotes fields with quotes" do
      items = [DV.of_object({ "desc" => DV.of_string('He said "hi"') })]
      v = DV.of_array(items)
      csv = FE.to_csv(v)
      expect(csv).to include('"He said ""hi"""')
    end

    it "returns empty string for non-array" do
      expect(FE.to_csv(DV.of_string("x"))).to eq("")
    end

    it "returns empty string for empty array" do
      expect(FE.to_csv(DV.of_array([]))).to eq("")
    end

    it "handles null values as empty cells" do
      items = [DV.of_object({ "a" => DV.of_null, "b" => DV.of_string("x") })]
      v = DV.of_array(items)
      csv = FE.to_csv(v)
      lines = csv.strip.split("\n")
      expect(lines[0]).to eq("a,b")
      expect(lines[1]).to eq(",x")
    end
  end

  # ── Fixed-Width Export ──

  describe ".to_fixed_width" do
    let(:columns) do
      [
        { name: "Name", pos: 0, len: 10 },
        { name: "Age", pos: 10, len: 3, align: :right }
      ]
    end

    it "formats fields at fixed positions" do
      v = DV.of_object({ "Name" => DV.of_string("John"), "Age" => DV.of_string("30") })
      result = FE.to_fixed_width(v, columns: columns, line_width: 13)
      expect(result.chomp.length).to be <= 13
      expect(result).to start_with("John")
    end

    it "right-aligns when specified" do
      v = DV.of_object({ "Name" => DV.of_string("John"), "Age" => DV.of_string("30") })
      result = FE.to_fixed_width(v, columns: columns, line_width: 13)
      # Age should be right-aligned in 3-char field
      expect(result[10..12].strip).to eq("30")
    end

    it "truncates long values" do
      v = DV.of_object({ "Name" => DV.of_string("VeryLongNameThatExceedsWidth"), "Age" => DV.of_string("30") })
      result = FE.to_fixed_width(v, columns: columns, line_width: 13)
      expect(result[0..9]).to eq("VeryLongNa")
    end

    it "handles multiple rows" do
      items = [
        DV.of_object({ "Name" => DV.of_string("John"), "Age" => DV.of_string("30") }),
        DV.of_object({ "Name" => DV.of_string("Jane"), "Age" => DV.of_string("25") })
      ]
      v = DV.of_array(items)
      result = FE.to_fixed_width(v, columns: columns, line_width: 13)
      lines = result.strip.split("\n")
      expect(lines.size).to eq(2)
    end
  end

  # ── Flat KVP Export ──

  describe ".to_flat_kvp" do
    it "exports simple key=value pairs" do
      v = DV.of_object({ "name" => DV.of_string("John"), "age" => DV.of_integer(30) })
      result = FE.to_flat_kvp(v)
      expect(result).to include("name=John")
      expect(result).to include("age=30")
    end

    it "exports nested objects with dotted paths" do
      v = DV.of_object({
        "person" => DV.of_object({ "name" => DV.of_string("John") })
      })
      result = FE.to_flat_kvp(v)
      expect(result).to include("person.name=John")
    end

    it "exports arrays with bracket notation" do
      v = DV.of_object({
        "items" => DV.of_array([DV.of_string("a"), DV.of_string("b")])
      })
      result = FE.to_flat_kvp(v)
      expect(result).to include("items[0]=a")
      expect(result).to include("items[1]=b")
    end

    it "exports null as empty value" do
      v = DV.of_object({ "x" => DV.of_null })
      result = FE.to_flat_kvp(v)
      expect(result).to include("x=")
    end

    it "exports booleans" do
      v = DV.of_object({ "active" => DV.of_bool(true) })
      result = FE.to_flat_kvp(v)
      expect(result).to include("active=true")
    end

    it "returns empty string for non-object" do
      expect(FE.to_flat_kvp(DV.of_string("x"))).to eq("")
    end
  end
end
