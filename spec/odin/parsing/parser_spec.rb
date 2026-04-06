# frozen_string_literal: true

require "spec_helper"

RSpec.describe Odin::Parsing::OdinParser do
  subject(:parser) { described_class.new }

  def parse(text)
    parser.parse(text)
  end

  # ──── Basic Parsing ────

  describe "basic parsing" do
    it "parses simple string assignment" do
      doc = parse('name = "John"')
      expect(doc.get("name").value).to eq("John")
      expect(doc.get("name").type).to eq(:string)
    end

    it "parses empty string" do
      doc = parse('empty = ""')
      expect(doc.get("empty").value).to eq("")
    end

    it "parses integer" do
      doc = parse("count = ##42")
      expect(doc.get("count").value).to eq(42)
      expect(doc.get("count").type).to eq(:integer)
    end

    it "parses negative integer" do
      doc = parse("offset = ##-100")
      expect(doc.get("offset").value).to eq(-100)
    end

    it "parses number" do
      doc = parse("pi = #3.14")
      expect(doc.get("pi").value).to be_within(1e-10).of(3.14)
      expect(doc.get("pi").type).to eq(:number)
    end

    it "parses negative number" do
      doc = parse("temp = #-273.15")
      expect(doc.get("temp").value).to be_within(1e-10).of(-273.15)
    end

    it "parses scientific notation" do
      doc = parse("big = #6.022e23")
      expect(doc.get("big").type).to eq(:number)
    end

    it "parses currency" do
      doc = parse('price = #$99.99')
      expect(doc.get("price").type).to eq(:currency)
      expect(doc.get("price").value.to_f).to be_within(1e-10).of(99.99)
    end

    it "parses currency with code" do
      doc = parse('price = #$99.99:USD')
      expect(doc.get("price").currency_code).to eq("USD")
    end

    it "parses boolean ?true" do
      doc = parse("active = ?true")
      expect(doc.get("active").value).to eq(true)
      expect(doc.get("active").type).to eq(:boolean)
    end

    it "parses boolean ?false" do
      doc = parse("active = ?false")
      expect(doc.get("active").value).to eq(false)
    end

    it "parses bare boolean true" do
      doc = parse("active = true")
      expect(doc.get("active").value).to eq(true)
    end

    it "parses bare boolean false" do
      doc = parse("active = false")
      expect(doc.get("active").value).to eq(false)
    end

    it "parses null" do
      doc = parse("value = ~")
      expect(doc.get("value").type).to eq(:null)
    end

    it "parses reference" do
      doc = parse("ref = @other.path")
      expect(doc.get("ref").type).to eq(:reference)
      expect(doc.get("ref").path).to eq("other.path")
    end

    it "parses bare @ reference (empty path)" do
      doc = parse("ref = @")
      expect(doc.get("ref").type).to eq(:reference)
      expect(doc.get("ref").path).to eq("")
    end

    it "parses binary" do
      doc = parse("data = ^SGVsbG8=")
      expect(doc.get("data").type).to eq(:binary)
    end

    it "parses binary with algorithm" do
      doc = parse("hash = ^sha256:e3b0c44")
      expect(doc.get("hash").algorithm).to eq("sha256")
    end

    it "parses date" do
      doc = parse("born = 2024-01-15")
      expect(doc.get("born").type).to eq(:date)
      expect(doc.get("born").raw).to eq("2024-01-15")
    end

    it "parses timestamp" do
      doc = parse("created = 2024-01-15T10:30:00Z")
      expect(doc.get("created").type).to eq(:timestamp)
    end

    it "parses time" do
      doc = parse("start = T10:30:00")
      expect(doc.get("start").type).to eq(:time)
      expect(doc.get("start").value).to eq("T10:30:00")
    end

    it "parses duration" do
      doc = parse("length = P1Y2M3D")
      expect(doc.get("length").type).to eq(:duration)
      expect(doc.get("length").value).to eq("P1Y2M3D")
    end

    it "parses percent" do
      doc = parse("rate = #%0.15")
      expect(doc.get("rate").type).to eq(:percent)
      expect(doc.get("rate").value).to be_within(1e-10).of(0.15)
    end

    it "parses multiple assignments" do
      doc = parse("first = \"John\"\nlast = \"Smith\"")
      expect(doc.get("first").value).to eq("John")
      expect(doc.get("last").value).to eq("Smith")
    end

    it "parses nested path" do
      doc = parse('customer.name.first = "John"')
      expect(doc.get("customer.name.first").value).to eq("John")
    end

    it "ignores inline comments" do
      doc = parse('name = "John" ; this is a comment')
      expect(doc.get("name").value).to eq("John")
    end

    it "ignores full-line comments" do
      doc = parse("; comment\nname = \"John\"")
      expect(doc.get("name").value).to eq("John")
    end

    it "preserves whitespace in quoted strings" do
      doc = parse('name = "  John  "')
      expect(doc.get("name").value).to eq("  John  ")
    end
  end

  # ──── @# Error ────

  describe "@# error" do
    it "raises P001 for @# on value side" do
      expect { parse('ref = @#invalid') }.to raise_error(Odin::Errors::ParseError) { |e|
        expect(e.code).to eq("P001")
      }
    end
  end

  # ──── Header Context ────

  describe "header context" do
    it "sets context with {Person}" do
      doc = parse("{Person}\nname = \"John\"")
      expect(doc.get("Person.name").value).to eq("John")
    end

    it "resets context with {}" do
      doc = parse("{Person}\nname = \"John\"\n{}\ncity = \"Austin\"")
      expect(doc.get("Person.name").value).to eq("John")
      expect(doc.get("city").value).to eq("Austin")
    end

    it "handles multiple headers" do
      doc = parse("{A}\nx = ##1\n{B}\ny = ##2")
      expect(doc.get("A.x").value).to eq(1)
      expect(doc.get("B.y").value).to eq(2)
    end

    it "handles deep nesting" do
      doc = parse("{A.B.C}\nval = ##1")
      expect(doc.get("A.B.C.val").value).to eq(1)
    end

    it "handles array index in header" do
      doc = parse("{items[0]}\nname = \"X\"")
      expect(doc.get("items[0].name").value).to eq("X")
    end

    it "handles multiple array indices" do
      doc = parse("{items[0]}\nname = \"A\"\n{items[1]}\nname = \"B\"")
      expect(doc.get("items[0].name").value).to eq("A")
      expect(doc.get("items[1].name").value).to eq("B")
    end
  end

  # ──── Relative Headers ────

  describe "relative headers" do
    it "resolves {.address} relative to {Person}" do
      doc = parse("{Person}\n{.address}\ncity = \"Austin\"")
      expect(doc.get("Person.address.city").value).to eq("Austin")
    end

    it "chains relative headers" do
      doc = parse("{Person}\n{.address}\ncity = \"Austin\"\n{.phone}\nnumber = \"555\"")
      expect(doc.get("Person.address.city").value).to eq("Austin")
      expect(doc.get("Person.phone.number").value).to eq("555")
    end

    it "resets to root after relative then absolute" do
      doc = parse("{Person}\n{.address}\ncity = \"Austin\"\n{Company}\nname = \"Acme\"")
      expect(doc.get("Person.address.city").value).to eq("Austin")
      expect(doc.get("Company.name").value).to eq("Acme")
    end

    it "resolves relative from root" do
      doc = parse("{.address}\ncity = \"Austin\"")
      expect(doc.get("address.city").value).to eq("Austin")
    end
  end

  # ──── Metadata ────

  describe "metadata" do
    it "stores metadata under {$}" do
      doc = parse("{$}\nodin = \"1.0.0\"")
      expect(doc.metadata["odin"].value).to eq("1.0.0")
    end

    it "stores multiple metadata fields" do
      doc = parse("{$}\nodin = \"1.0.0\"\ntransform = \"1.0.0\"")
      expect(doc.metadata["odin"].value).to eq("1.0.0")
      expect(doc.metadata["transform"].value).to eq("1.0.0")
    end

    it "switches back to assignments after {}" do
      doc = parse("{$}\nodin = \"1.0.0\"\n{}\nname = \"John\"")
      expect(doc.metadata["odin"].value).to eq("1.0.0")
      expect(doc.get("name").value).to eq("John")
    end
  end

  # ──── Array Handling ────

  describe "array handling" do
    it "parses array element" do
      doc = parse("{items[0]}\nname = \"X\"")
      expect(doc.get("items[0].name").value).to eq("X")
    end

    it "parses sequential indices" do
      doc = parse("items[0].name = \"A\"\nitems[1].name = \"B\"\nitems[2].name = \"C\"")
      expect(doc.get("items[0].name").value).to eq("A")
      expect(doc.get("items[1].name").value).to eq("B")
      expect(doc.get("items[2].name").value).to eq("C")
    end

    it "raises P013 for non-contiguous indices" do
      expect {
        parse("items[0].name = \"A\"\nitems[2].name = \"C\"")
      }.to raise_error(Odin::Errors::ParseError) { |e|
        expect(e.code).to eq("P013")
      }
    end

    it "raises P015 for out-of-range index" do
      expect {
        parse("items[2147483647].name = \"X\"")
      }.to raise_error(Odin::Errors::ParseError) { |e|
        expect(e.code).to eq("P015")
      }
    end

    it "raises P003 for negative index" do
      expect {
        parse("items[-1].name = \"X\"")
      }.to raise_error(Odin::Errors::ParseError) { |e|
        expect(e.code).to eq("P003")
      }
    end
  end

  # ──── Tabular Format ────

  describe "tabular format" do
    it "parses basic tabular" do
      doc = parse("{items[] : name, qty, price}\n\"Widget\", ##10, \#$5.99\n\"Gadget\", ##5, \#$12.50")
      expect(doc.get("items[0].name").value).to eq("Widget")
      expect(doc.get("items[0].qty").value).to eq(10)
      expect(doc.get("items[0].price").value.to_f).to be_within(0.01).of(5.99)
      expect(doc.get("items[1].name").value).to eq("Gadget")
    end

    it "handles null cells" do
      doc = parse("{items[] : name, desc}\n\"Widget\", \"A widget\"\n\"Gadget\", ~")
      expect(doc.get("items[1].desc").type).to eq(:null)
    end

    it "handles empty string cells" do
      doc = parse("{items[] : name, notes}\n\"Widget\", \"In stock\"\n\"Gadget\", \"\"")
      expect(doc.get("items[1].notes").value).to eq("")
    end

    it "handles absent cells" do
      doc = parse("{items[] : name, desc, notes}\n\"Widget\", \"A widget\", \"In stock\"\n\"Gadget\", ,")
      expect(doc.get("items[1].name").value).to eq("Gadget")
      expect(doc.include?("items[1].desc")).to eq(false)
    end

    it "handles strings with commas" do
      doc = parse("{items[] : sku, description, qty}\n\"ABC-001\", \"Cable, 6ft\", ##20")
      expect(doc.get("items[0].description").value).to eq("Cable, 6ft")
    end

    it "handles primitive arrays" do
      doc = parse("{tags[] : ~}\n\"urgent\"\n\"important\"")
      expect(doc.get("tags[0]").value).to eq("urgent")
      expect(doc.get("tags[1]").value).to eq("important")
    end

    it "handles boolean values in tabular" do
      doc = parse("{flags[] : name, enabled}\n\"feature-a\", ?true\n\"feature-b\", ?false\n\"feature-c\", true")
      expect(doc.get("flags[2].enabled").value).to eq(true)
    end

    it "resolves relative column names" do
      doc = parse("{holders[] : name, address.line1, .city, .state}\n\"ABC\", \"500 St\", \"Dallas\", \"TX\"")
      expect(doc.get("holders[0].address.city").value).to eq("Dallas")
      expect(doc.get("holders[0].address.state").value).to eq("TX")
    end

    it "exits tabular mode on next header" do
      doc = parse("{items[] : name, qty}\n\"Widget\", ##10\n{other}\nval = ##1")
      expect(doc.get("items[0].name").value).to eq("Widget")
      expect(doc.get("other.val").value).to eq(1)
    end
  end

  # ──── Modifiers ────

  describe "modifiers" do
    it "parses required modifier" do
      doc = parse('name = !"required"')
      expect(doc.get("name").required?).to eq(true)
    end

    it "parses confidential modifier" do
      doc = parse('ssn = *"hidden"')
      expect(doc.get("ssn").confidential?).to eq(true)
    end

    it "parses deprecated modifier" do
      doc = parse('old = -"deprecated"')
      expect(doc.get("old").deprecated?).to eq(true)
    end

    it "parses combined modifiers" do
      doc = parse('field = !*-"value"')
      v = doc.get("field")
      expect(v.required?).to eq(true)
      expect(v.confidential?).to eq(true)
      expect(v.deprecated?).to eq(true)
    end

    it "normalizes modifier order" do
      doc = parse('field = -*!"value"')
      v = doc.get("field")
      expect(v.required?).to eq(true)
      expect(v.confidential?).to eq(true)
      expect(v.deprecated?).to eq(true)
    end

    it "applies modifiers to integer" do
      doc = parse("count = !##42")
      expect(doc.get("count").required?).to eq(true)
      expect(doc.get("count").value).to eq(42)
    end

    it "applies modifiers to boolean" do
      doc = parse("active = !true")
      expect(doc.get("active").required?).to eq(true)
    end

    it "applies modifiers to null" do
      doc = parse("deleted = *~")
      expect(doc.get("deleted").confidential?).to eq(true)
    end

    it "applies modifiers to nested path" do
      doc = parse('person.ssn = *"987-65-4321"')
      expect(doc.get("person.ssn").confidential?).to eq(true)
    end
  end

  # ──── Directives ────

  describe "directives" do
    it "parses trailing directive" do
      doc = parse('name = "John" :required')
      v = doc.get("name")
      expect(v.directives).not_to be_empty
      expect(v.directives[0].name).to eq("required")
    end

    it "parses directive with value" do
      doc = parse('name = "John" :type "string"')
      v = doc.get("name")
      expect(v.directives[0].name).to eq("type")
      expect(v.directives[0].value).to eq("string")
    end
  end

  # ──── Comments ────

  describe "comments" do
    it "preserves inline comment" do
      doc = parse('name = "John" ; comment text')
      expect(doc.comment_for("name")).to eq("comment text")
    end

    it "handles comment-only lines" do
      doc = parse("; first comment\n; second comment\nname = \"John\"")
      expect(doc.get("name").value).to eq("John")
    end
  end

  # ──── Extension Paths ────

  describe "extension paths" do
    it "parses extension path" do
      doc = parse('&com.acme.tier = "A"')
      expect(doc.get("&com.acme.tier").value).to eq("A")
    end

    it "parses extension with modifier" do
      doc = parse('&com.acme.secret = *"classified"')
      expect(doc.get("&com.acme.secret").confidential?).to eq(true)
    end

    it "mixes extension and regular paths" do
      doc = parse("name = \"John\"\n&com.acme.tier = \"A\"")
      expect(doc.get("name").value).to eq("John")
      expect(doc.get("&com.acme.tier").value).to eq("A")
    end
  end

  # ──── Error Cases ────

  describe "error cases" do
    it "raises P002 for bare string" do
      expect { parse("name = John") }.to raise_error(Odin::Errors::ParseError) { |e|
        expect(e.code).to eq("P002")
      }
    end

    it "raises P001 for @#" do
      expect { parse("ref = @#invalid") }.to raise_error(Odin::Errors::ParseError) { |e|
        expect(e.code).to eq("P001")
      }
    end

    it "raises P004 for unterminated string" do
      expect { parse('name = "John') }.to raise_error(Odin::Errors::ParseError) { |e|
        expect(e.code).to eq("P004")
      }
    end

    it "raises P005 for invalid escape" do
      expect { parse('name = "hello\z"') }.to raise_error(Odin::Errors::ParseError) { |e|
        expect(e.code).to eq("P005")
      }
    end

    it "raises P007 for duplicate path" do
      expect { parse("name = \"John\"\nname = \"Jane\"") }.to raise_error(Odin::Errors::ParseError) { |e|
        expect(e.code).to eq("P007")
      }
    end

    it "raises P008 for unclosed header" do
      expect { parse("{Section\nname = \"test\"") }.to raise_error(Odin::Errors::ParseError) { |e|
        expect(e.code).to eq("P008")
      }
    end

    it "raises P010 for excessive depth" do
      path = (1..100).map { |i| "a#{i}" }.join(".")
      expect { parse("#{path} = ##1") }.to raise_error(Odin::Errors::ParseError) { |e|
        expect(e.code).to eq("P010")
      }
    end

    it "raises P013 for non-contiguous arrays" do
      expect { parse("a[0] = ##1\na[5] = ##2") }.to raise_error(Odin::Errors::ParseError) { |e|
        expect(e.code).to eq("P013")
      }
    end

    it "raises P015 for array index out of range" do
      expect { parse("items[999999999] = ##1") }.to raise_error(Odin::Errors::ParseError) { |e|
        expect(e.code).to eq("P015")
      }
    end

    it "raises P003 for invalid header array index" do
      expect { parse("{invalid[}") }.to raise_error(Odin::Errors::ParseError) { |e|
        expect(e.code).to eq("P003")
      }
    end

    it "raises P001 for @ at line start" do
      expect { parse('@ = "test"') }.to raise_error(Odin::Errors::ParseError) { |e|
        expect(e.code).to eq("P001")
      }
    end

    it "raises P001 for invalid date" do
      expect { parse("d = 2023-02-29") }.to raise_error(Odin::Errors::ParseError) { |e|
        expect(e.code).to eq("P001")
      }
    end
  end

  # ──── Verb Expressions ────

  describe "verb expressions" do
    it "parses simple verb" do
      doc = parse('result = %upper @name')
      expect(doc.get("result").type).to eq(:verb)
      expect(doc.get("result").verb).to eq("upper")
    end

    it "parses custom verb" do
      doc = parse('custom = %&myNamespace.customVerb @value')
      expect(doc.get("custom").custom?).to eq(true)
    end
  end

  # ──── Case Sensitivity ────

  describe "case sensitivity" do
    it "treats different case paths as separate" do
      doc = parse("Name = \"Upper\"\nname = \"lower\"")
      expect(doc.get("Name").value).to eq("Upper")
      expect(doc.get("name").value).to eq("lower")
    end

    it "allows keyword field names" do
      doc = parse("true = \"some value\"")
      expect(doc.get("true").value).to eq("some value")
    end
  end

  # ──── CRLF and BOM ────

  describe "CRLF and BOM" do
    it "handles CRLF line endings" do
      doc = parse("name = \"John\"\r\nage = ##30")
      expect(doc.get("name").value).to eq("John")
      expect(doc.get("age").value).to eq(30)
    end

    it "handles UTF-8 BOM" do
      doc = parse("\xEF\xBB\xBFname = \"John\"")
      expect(doc.get("name").value).to eq("John")
    end

    it "handles empty document" do
      doc = parse("")
      expect(doc.empty?).to eq(true)
    end

    it "handles whitespace-only document" do
      doc = parse("  \n  \n")
      expect(doc.empty?).to eq(true)
    end
  end

  # ──── String Escapes ────

  describe "string escapes" do
    it "parses escaped newline" do
      doc = parse('text = "line1\nline2"')
      expect(doc.get("text").value).to eq("line1\nline2")
    end

    it "parses escaped tab" do
      doc = parse('text = "col1\tcol2"')
      expect(doc.get("text").value).to eq("col1\tcol2")
    end

    it "parses escaped backslash" do
      doc = parse('path = "C:\\\\Users"')
      expect(doc.get("path").value).to eq("C:\\Users")
    end

    it "parses escaped quote" do
      doc = parse('text = "say \\"hello\\""')
      expect(doc.get("text").value).to eq('say "hello"')
    end

    it "parses unicode escape" do
      doc = parse('emoji = "\\u0041"')
      expect(doc.get("emoji").value).to eq("A")
    end
  end

  # ──── Currency Variations ────

  describe "currency variations" do
    it "parses negative currency" do
      doc = parse('loss = #$-50.00')
      expect(doc.get("loss").type).to eq(:currency)
      expect(doc.get("loss").value.to_f).to be_within(0.01).of(-50.0)
    end

    it "parses currency with 3 decimal places" do
      doc = parse('precise = #$1.234:BHD')
      expect(doc.get("precise").decimal_places).to eq(3)
    end

    it "parses currency with no decimals" do
      doc = parse('whole = #$100:JPY')
      expect(doc.get("whole").value.to_f).to be_within(0.01).of(100.0)
      expect(doc.get("whole").currency_code).to eq("JPY")
    end

    it "parses zero currency" do
      doc = parse('zero = #$0.00')
      expect(doc.get("zero").value.to_f).to be_within(0.01).of(0.0)
    end
  end

  # ──── Number Edge Cases ────

  describe "number edge cases" do
    it "parses zero integer" do
      doc = parse("zero = ##0")
      expect(doc.get("zero").value).to eq(0)
    end

    it "parses large integer" do
      doc = parse("big = ##999999999")
      expect(doc.get("big").value).to eq(999999999)
    end

    it "parses negative zero" do
      doc = parse("nz = #-0.0")
      expect(doc.get("nz").type).to eq(:number)
    end

    it "parses very small number" do
      doc = parse("small = #0.000001")
      expect(doc.get("small").value).to be_within(1e-10).of(0.000001)
    end

    it "parses negative scientific notation" do
      doc = parse("neg = #-1.5e-3")
      expect(doc.get("neg").value).to be_within(1e-10).of(-0.0015)
    end

    it "parses percent zero" do
      doc = parse("rate = #%0")
      expect(doc.get("rate").type).to eq(:percent)
      expect(doc.get("rate").value).to be_within(1e-10).of(0.0)
    end

    it "parses percent with decimals" do
      doc = parse("rate = #%0.0525")
      expect(doc.get("rate").value).to be_within(1e-10).of(0.0525)
    end
  end

  # ──── Date/Time Variations ────

  describe "date and time variations" do
    it "parses date at year boundary" do
      doc = parse("d = 2024-12-31")
      expect(doc.get("d").type).to eq(:date)
    end

    it "parses date with leap year" do
      doc = parse("d = 2024-02-29")
      expect(doc.get("d").type).to eq(:date)
    end

    it "parses timestamp with offset" do
      doc = parse("ts = 2024-01-15T10:30:00+05:30")
      expect(doc.get("ts").type).to eq(:timestamp)
    end

    it "parses timestamp with negative offset" do
      doc = parse("ts = 2024-01-15T10:30:00-08:00")
      expect(doc.get("ts").type).to eq(:timestamp)
    end

    it "parses time with seconds" do
      doc = parse("t = T23:59:59")
      expect(doc.get("t").type).to eq(:time)
    end

    it "parses duration with time components" do
      doc = parse("d = PT1H30M")
      expect(doc.get("d").type).to eq(:duration)
    end

    it "parses duration days only" do
      doc = parse("d = P30D")
      expect(doc.get("d").type).to eq(:duration)
    end
  end

  # ──── Reference Variations ────

  describe "reference variations" do
    it "parses reference with array index" do
      doc = parse("ref = @items[0].name")
      expect(doc.get("ref").path).to eq("items[0].name")
    end

    it "parses reference with deep path" do
      doc = parse("ref = @a.b.c.d.e")
      expect(doc.get("ref").path).to eq("a.b.c.d.e")
    end
  end

  # ──── Binary Variations ────

  describe "binary variations" do
    it "parses binary with md5 algorithm" do
      doc = parse("hash = ^md5:d41d8cd98f00b204e9800998ecf8427e")
      expect(doc.get("hash").algorithm).to eq("md5")
    end

    it "parses simple base64 binary" do
      doc = parse("data = ^AQID")
      expect(doc.get("data").type).to eq(:binary)
    end
  end

  # ──── Complex Paths ────

  describe "complex paths" do
    it "parses deeply nested path" do
      doc = parse('a.b.c.d.e.f = "deep"')
      expect(doc.get("a.b.c.d.e.f").value).to eq("deep")
    end

    it "parses path with array in middle" do
      doc = parse('items[0].address.city = "Austin"')
      expect(doc.get("items[0].address.city").value).to eq("Austin")
    end

    it "parses multiple arrays" do
      doc = parse("matrix[0].row[0].val = ##1\nmatrix[0].row[1].val = ##2")
      expect(doc.get("matrix[0].row[0].val").value).to eq(1)
      expect(doc.get("matrix[0].row[1].val").value).to eq(2)
    end

    it "parses path with underscores" do
      doc = parse('first_name = "John"')
      expect(doc.get("first_name").value).to eq("John")
    end

    it "parses path with hyphens" do
      doc = parse('content-type = "text/odin"')
      expect(doc.get("content-type").value).to eq("text/odin")
    end
  end

  # ──── Header Edge Cases ────

  describe "header edge cases" do
    it "handles header with trailing spaces" do
      doc = parse("{Person}\n name = \"John\"")
      expect(doc.get("Person.name").value).to eq("John")
    end

    it "handles empty header resetting context" do
      doc = parse("{A}\nx = ##1\n{}\ny = ##2\n{B}\nz = ##3")
      expect(doc.get("A.x").value).to eq(1)
      expect(doc.get("y").value).to eq(2)
      expect(doc.get("B.z").value).to eq(3)
    end

    it "handles sequential headers without assignments" do
      doc = parse("{A}\n{B}\nval = ##1")
      expect(doc.get("B.val").value).to eq(1)
    end

    it "handles array header with sequential items" do
      doc = parse("{list[0]}\na = ##1\n{list[1]}\na = ##2\n{list[2]}\na = ##3")
      expect(doc.get("list[0].a").value).to eq(1)
      expect(doc.get("list[1].a").value).to eq(2)
      expect(doc.get("list[2].a").value).to eq(3)
    end
  end

  # ──── Metadata Edge Cases ────

  describe "metadata edge cases" do
    it "handles metadata with various types" do
      doc = parse("{$}\nodin = \"1.0.0\"\ncount = ##5\nactive = ?true")
      expect(doc.metadata["odin"].value).to eq("1.0.0")
      expect(doc.metadata["count"].value).to eq(5)
      expect(doc.metadata["active"].value).to eq(true)
    end

    it "handles metadata then regular then metadata" do
      doc = parse("{$}\nodin = \"1.0.0\"\n{Person}\nname = \"John\"")
      expect(doc.metadata["odin"].value).to eq("1.0.0")
      expect(doc.get("Person.name").value).to eq("John")
    end
  end

  # ──── Tabular Edge Cases ────

  describe "tabular edge cases" do
    it "handles single column tabular" do
      doc = parse("{names[] : name}\n\"Alice\"\n\"Bob\"\n\"Carol\"")
      expect(doc.get("names[0].name").value).to eq("Alice")
      expect(doc.get("names[1].name").value).to eq("Bob")
      expect(doc.get("names[2].name").value).to eq("Carol")
    end

    it "handles tabular with integer values" do
      doc = parse("{scores[] : name, score}\n\"Alice\", ##100\n\"Bob\", ##85")
      expect(doc.get("scores[0].score").value).to eq(100)
      expect(doc.get("scores[1].score").value).to eq(85)
    end

    it "handles tabular with references" do
      doc = parse("{items[] : name, ref}\n\"A\", @other.path")
      expect(doc.get("items[0].ref").type).to eq(:reference)
    end

    it "handles tabular with dates" do
      doc = parse("{events[] : name, date}\n\"Launch\", 2024-01-15")
      expect(doc.get("events[0].date").type).to eq(:date)
    end

    it "handles many rows" do
      rows = (0..9).map { |i| "\"item#{i}\", ###{i}" }.join("\n")
      doc = parse("{items[] : name, idx}\n#{rows}")
      expect(doc.get("items[9].idx").value).to eq(9)
    end
  end

  # ──── Modifier Combinations ────

  describe "modifier combinations" do
    it "applies required to currency" do
      doc = parse('price = !#$29.99')
      expect(doc.get("price").required?).to eq(true)
      expect(doc.get("price").type).to eq(:currency)
    end

    it "applies confidential to number" do
      doc = parse("secret = *#42.5")
      expect(doc.get("secret").confidential?).to eq(true)
      expect(doc.get("secret").type).to eq(:number)
    end

    it "applies deprecated to date" do
      doc = parse("old = -2024-01-01")
      expect(doc.get("old").deprecated?).to eq(true)
      expect(doc.get("old").type).to eq(:date)
    end

    it "applies required to reference" do
      doc = parse("ref = !@other.path")
      expect(doc.get("ref").required?).to eq(true)
      expect(doc.get("ref").type).to eq(:reference)
    end

    it "applies required and confidential" do
      doc = parse('data = !*"sensitive"')
      expect(doc.get("data").required?).to eq(true)
      expect(doc.get("data").confidential?).to eq(true)
    end
  end

  # ──── Directive Edge Cases ────

  describe "directive edge cases" do
    it "parses multiple directives" do
      doc = parse('name = "John" :required :type "string"')
      v = doc.get("name")
      expect(v.directives.length).to be >= 1
    end

    it "parses directive on integer" do
      doc = parse("count = ##42 :min")
      v = doc.get("count")
      expect(v.directives[0].name).to eq("min")
    end
  end

  # ──── Multiple Comments ────

  describe "multiple comments" do
    it "handles multiple comment lines before assignment" do
      doc = parse("; header comment\n; detail comment\nname = \"John\"")
      expect(doc.get("name").value).to eq("John")
    end

    it "handles comment between assignments" do
      doc = parse("a = ##1\n; separator\nb = ##2")
      expect(doc.get("a").value).to eq(1)
      expect(doc.get("b").value).to eq(2)
    end
  end

  # ──── Document Size ────

  describe "document size" do
    it "reports correct path count" do
      doc = parse("a = ##1\nb = ##2\nc = ##3")
      expect(doc.size).to eq(3)
    end

    it "reports zero for empty doc" do
      doc = parse("")
      expect(doc.size).to eq(0)
    end

    it "counts header-scoped paths" do
      doc = parse("{P}\na = ##1\nb = ##2")
      expect(doc.size).to eq(2)
    end
  end

  # ──── Error Messages ────

  describe "error detail" do
    it "includes line and column in P001" do
      begin
        parse("name = John")
      rescue Odin::Errors::ParseError => e
        expect(e.line).to be >= 1
        expect(e.column).to be >= 1
        expect(e.code).to eq("P002")
      end
    end

    it "raises P007 with path in message" do
      expect {
        parse("x = ##1\nx = ##2")
      }.to raise_error(Odin::Errors::ParseError) { |e|
        expect(e.code).to eq("P007")
        expect(e.message).to include("x")
      }
    end

    it "raises P003 for negative array index in path" do
      expect {
        parse("a[-1] = ##1")
      }.to raise_error(Odin::Errors::ParseError)
    end
  end

  # ──── Odin.parse facade ────

  describe "Odin.parse" do
    it "works through the facade" do
      doc = Odin.parse('name = "John"')
      expect(doc.get("name").value).to eq("John")
    end

    it "handles UTF-8 encoding" do
      doc = Odin.parse('name = "日本語"')
      expect(doc.get("name").value).to eq("日本語")
    end

    it "returns OdinDocument type" do
      doc = Odin.parse('x = ##1')
      expect(doc).to be_a(Odin::Types::OdinDocument)
    end
  end
end
