# frozen_string_literal: true

require "spec_helper"

RSpec.describe Odin::Transform::SourceParsers do
  SP = Odin::Transform::SourceParsers
  DV = Odin::Types::DynValue unless defined?(DV)

  # ── JSON Parser ──

  describe ".parse_json" do
    it "parses simple object" do
      v = SP.parse_json('{"name": "John", "age": 30}')
      expect(v.object?).to be true
      expect(v.get("name").value).to eq("John")
      expect(v.get("age").value).to eq(30)
    end

    it "parses nested objects" do
      v = SP.parse_json('{"a": {"b": {"c": 1}}}')
      expect(v.get("a").get("b").get("c").value).to eq(1)
    end

    it "parses arrays" do
      v = SP.parse_json('[1, 2, 3]')
      expect(v.array?).to be true
      expect(v.value.size).to eq(3)
    end

    it "preserves integer vs float" do
      v = SP.parse_json('{"int": 42, "float": 3.14}')
      expect(v.get("int").integer?).to be true
      expect(v.get("float").float?).to be true
    end

    it "handles null" do
      v = SP.parse_json('{"x": null}')
      expect(v.get("x").null?).to be true
    end

    it "handles booleans" do
      v = SP.parse_json('{"t": true, "f": false}')
      expect(v.get("t").value).to be true
      expect(v.get("f").value).to be false
    end

    it "handles strings with special characters" do
      v = SP.parse_json('{"s": "hello\\nworld"}')
      expect(v.get("s").value).to eq("hello\nworld")
    end

    it "raises on nil input" do
      expect { SP.parse_json(nil) }.to raise_error(ArgumentError)
    end

    it "raises on empty input" do
      expect { SP.parse_json("") }.to raise_error(ArgumentError)
    end

    it "raises on invalid JSON" do
      expect { SP.parse_json("{bad json}") }.to raise_error(Odin::Transform::SourceParsers::FormatError)
    end
  end

  # ── CSV Parser ──

  describe ".parse_csv" do
    it "parses basic CSV with headers" do
      csv = "name,age\nJohn,30\nJane,25\n"
      v = SP.parse_csv(csv)
      expect(v.array?).to be true
      expect(v.value.size).to eq(2)
      expect(v.value[0].get("name").value).to eq("John")
      expect(v.value[0].get("age").value).to eq(30)
    end

    it "handles quoted fields" do
      csv = "name,desc\nJohn,\"Hello, World\"\n"
      v = SP.parse_csv(csv)
      expect(v.value[0].get("desc").value).to eq("Hello, World")
    end

    it "handles embedded quotes" do
      csv = "name,quote\nJohn,\"He said \"\"hi\"\"\"\n"
      v = SP.parse_csv(csv)
      expect(v.value[0].get("quote").value).to eq('He said "hi"')
    end

    it "handles embedded newlines in quoted fields" do
      csv = "name,bio\nJohn,\"Line 1\nLine 2\"\n"
      v = SP.parse_csv(csv)
      expect(v.value[0].get("bio").value).to eq("Line 1\nLine 2")
    end

    it "strips BOM" do
      csv = +"\xEF\xBB\xBFname,age\nJohn,30\n"
      csv.force_encoding("ASCII-8BIT")
      v = SP.parse_csv(csv)
      expect(v.array?).to be true
      expect(v.value[0].get("name").value).to eq("John")
    end

    it "handles no-header mode" do
      csv = "John,30\nJane,25\n"
      v = SP.parse_csv(csv, headers: false)
      expect(v.array?).to be true
      expect(v.value[0].array?).to be true
      expect(v.value[0].value[0].value).to eq("John")
    end

    it "infers types: integer" do
      csv = "val\n42\n"
      v = SP.parse_csv(csv)
      expect(v.value[0].get("val").integer?).to be true
    end

    it "infers types: float" do
      csv = "val\n3.14\n"
      v = SP.parse_csv(csv)
      expect(v.value[0].get("val").float?).to be true
    end

    it "infers types: boolean" do
      csv = "val\ntrue\n"
      v = SP.parse_csv(csv)
      expect(v.value[0].get("val").bool?).to be true
    end

    it "infers types: null" do
      csv = "val\nnull\n"
      v = SP.parse_csv(csv)
      expect(v.value[0].get("val").null?).to be true
    end

    it "returns empty array for nil input" do
      v = SP.parse_csv(nil)
      expect(v.array?).to be true
      expect(v.value).to be_empty
    end

    it "returns empty array for empty input" do
      v = SP.parse_csv("")
      expect(v.array?).to be true
      expect(v.value).to be_empty
    end

    it "handles CRLF line endings" do
      csv = "name,age\r\nJohn,30\r\n"
      v = SP.parse_csv(csv)
      expect(v.value.size).to eq(1)
      expect(v.value[0].get("name").value).to eq("John")
    end
  end

  # ── XML Parser ──

  describe ".parse_xml" do
    it "parses simple element" do
      xml = "<root><name>John</name></root>"
      v = SP.parse_xml(xml)
      expect(v.object?).to be true
      expect(v.get("root").get("name").value).to eq("John")
    end

    it "handles attributes" do
      xml = '<root><item id="1">text</item></root>'
      v = SP.parse_xml(xml)
      # 'item' elements are always treated as arrays (matching TypeScript)
      items = v.get("root").get("item")
      expect(items.array?).to be true
      item = items.value[0]
      expect(item.get("@id").value).to eq("1")
      expect(item.get("_text").value).to eq("text")
    end

    it "handles repeated elements as arrays" do
      xml = "<root><item>a</item><item>b</item><item>c</item></root>"
      v = SP.parse_xml(xml)
      items = v.get("root").get("item")
      expect(items.array?).to be true
      expect(items.value.size).to eq(3)
    end

    it "handles nested elements" do
      xml = "<root><parent><child>value</child></parent></root>"
      v = SP.parse_xml(xml)
      expect(v.get("root").get("parent").get("child").value).to eq("value")
    end

    it "handles self-closing elements" do
      xml = "<root><empty/></root>"
      v = SP.parse_xml(xml)
      expect(v.get("root").get("empty").null?).to be true
    end

    it "handles xsi:nil" do
      xml = '<root xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><val xsi:nil="true"/></root>'
      v = SP.parse_xml(xml)
      expect(v.get("root").get("val").null?).to be true
    end

    it "preserves namespace prefixes" do
      xml = '<ns:root xmlns:ns="http://example.com"><ns:name>John</ns:name></ns:root>'
      v = SP.parse_xml(xml)
      expect(v.get("ns:root").get("ns:name").value).to eq("John")
    end

    it "raises on nil input" do
      expect { SP.parse_xml(nil) }.to raise_error(ArgumentError)
    end

    it "raises on empty input" do
      expect { SP.parse_xml("") }.to raise_error(ArgumentError)
    end

    it "raises on invalid XML" do
      expect { SP.parse_xml("<unclosed>") }.to raise_error(Odin::Transform::SourceParsers::FormatError)
    end

    it "handles text content with children" do
      xml = "<root><mixed>text<child>inner</child></mixed></root>"
      v = SP.parse_xml(xml)
      mixed = v.get("root").get("mixed")
      expect(mixed.get("_text").value).to eq("text")
      expect(mixed.get("child").value).to eq("inner")
    end

    it "handles attributes only (no text)" do
      xml = '<root><item id="1" type="widget"/></root>'
      v = SP.parse_xml(xml)
      # 'item' elements are always treated as arrays (matching TypeScript)
      items = v.get("root").get("item")
      expect(items.array?).to be true
      item = items.value[0]
      expect(item.get("@id").value).to eq("1")
      expect(item.get("@type").value).to eq("widget")
    end
  end

  # ── Fixed-Width Parser ──

  describe ".parse_fixed_width" do
    let(:columns) do
      [
        { name: "Name", pos: 0, len: 10 },
        { name: "Age", pos: 10, len: 3 },
        { name: "City", pos: 13, len: 15 }
      ]
    end

    it "parses single line" do
      input = "John      030Springfield    "
      v = SP.parse_fixed_width(input, columns: columns)
      expect(v.object?).to be true
      expect(v.get("Name").value).to eq("John")
      expect(v.get("Age").value).to eq("030")
      expect(v.get("City").value).to eq("Springfield")
    end

    it "parses multiple lines" do
      input = "John      030Springfield    \nJane      025Shelbyville    \n"
      v = SP.parse_fixed_width(input, columns: columns)
      expect(v.array?).to be true
      expect(v.value.size).to eq(2)
    end

    it "trims values by default" do
      input = "John      030Springfield    "
      v = SP.parse_fixed_width(input, columns: columns)
      expect(v.get("Name").value).to eq("John")
    end

    it "returns empty for nil input" do
      v = SP.parse_fixed_width(nil, columns: columns)
      expect(v.array?).to be true
      expect(v.value).to be_empty
    end

    it "raises on missing columns" do
      expect { SP.parse_fixed_width("data", columns: nil) }.to raise_error(ArgumentError)
    end

    it "handles short lines gracefully" do
      input = "John"
      v = SP.parse_fixed_width(input, columns: columns)
      expect(v.get("Name").value).to eq("John")
      expect(v.get("Age").value).to eq("")
    end
  end

  # ── Flat KVP Parser ──

  describe ".parse_flat_kvp" do
    it "parses simple key=value pairs" do
      input = "name = John\nage = 42\n"
      v = SP.parse_flat_kvp(input)
      expect(v.object?).to be true
      expect(v.get("name").value).to eq("John")
      expect(v.get("age").value).to eq(42)
    end

    it "handles dotted paths" do
      input = "person.name = John\nperson.age = 30\n"
      v = SP.parse_flat_kvp(input)
      expect(v.get("person").object?).to be true
      expect(v.get("person").get("name").value).to eq("John")
    end

    it "handles array notation" do
      input = "items[0] = apple\nitems[1] = banana\n"
      v = SP.parse_flat_kvp(input)
      expect(v.get("items").array?).to be true
      expect(v.get("items").value[0].value).to eq("apple")
    end

    it "handles quoted strings" do
      input = 'name = "John Doe"'
      v = SP.parse_flat_kvp(input)
      expect(v.get("name").value).to eq("John Doe")
    end

    it "handles null values" do
      input = "value = ~\nempty ="
      v = SP.parse_flat_kvp(input)
      expect(v.get("value").null?).to be true
      expect(v.get("empty").null?).to be true
    end

    it "handles boolean values" do
      input = "active = true\ndeleted = false"
      v = SP.parse_flat_kvp(input)
      expect(v.get("active").bool?).to be true
      expect(v.get("deleted").bool?).to be true
      expect(v.get("deleted").value).to be false
    end

    it "skips comments" do
      input = "# comment\n; another comment\nname = John"
      v = SP.parse_flat_kvp(input)
      expect(v.get("name").value).to eq("John")
    end

    it "skips empty lines" do
      input = "a = 1\n\nb = 2"
      v = SP.parse_flat_kvp(input)
      expect(v.get("a").value).to eq(1)
      expect(v.get("b").value).to eq(2)
    end

    it "returns empty object for nil input" do
      v = SP.parse_flat_kvp(nil)
      expect(v.object?).to be true
    end
  end

  # ── YAML Parser ──

  describe ".parse_yaml" do
    it "parses simple object" do
      yaml = "name: John\nage: 30\n"
      v = SP.parse_yaml(yaml)
      expect(v.object?).to be true
      expect(v.get("name").value).to eq("John")
      expect(v.get("age").value).to eq(30)
    end

    it "parses nested objects" do
      yaml = "person:\n  name: John\n  age: 30\n"
      v = SP.parse_yaml(yaml)
      expect(v.get("person").object?).to be true
      expect(v.get("person").get("name").value).to eq("John")
    end

    it "parses arrays" do
      yaml = "items:\n  - apple\n  - banana\n  - cherry\n"
      v = SP.parse_yaml(yaml)
      items = v.get("items")
      expect(items.array?).to be true
      expect(items.value.size).to eq(3)
    end

    it "handles booleans" do
      yaml = "active: true\ndeleted: false\n"
      v = SP.parse_yaml(yaml)
      expect(v.get("active").bool?).to be true
      expect(v.get("deleted").value).to be false
    end

    it "handles null" do
      yaml = "value: null\n"
      v = SP.parse_yaml(yaml)
      expect(v.get("value").null?).to be true
    end

    it "handles integers and floats" do
      yaml = "int: 42\nfloat: 3.14\n"
      v = SP.parse_yaml(yaml)
      expect(v.get("int").integer?).to be true
      expect(v.get("float").float?).to be true
    end

    it "returns empty object for nil input" do
      v = SP.parse_yaml(nil)
      expect(v.object?).to be true
    end

    it "raises on invalid YAML" do
      expect { SP.parse_yaml("  bad:\n\t- indent\n  wrong: {[") }.to raise_error(Odin::Transform::SourceParsers::FormatError)
    end
  end
end
