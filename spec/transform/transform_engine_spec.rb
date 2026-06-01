# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Odin::Transform::TransformEngine do
  let(:engine) { described_class.new }
  let(:parser) { Odin::Transform::TransformParser.new }
  let(:dv) { Odin::Types::DynValue }

  def execute_transform(transform_text, source)
    transform_def = parser.parse(transform_text)
    engine.execute(transform_def, source)
  end

  # ── Simple Copy ──

  describe "simple copy operations" do
    it "copies a simple field" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Customer}
        Name = @.name
      ODIN
      result = execute_transform(text, { "name" => "Alice" })
      expect(result.output["Customer"]["Name"]).to eq("Alice")
    end

    it "copies nested field" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Customer}
        City = @.address.city
      ODIN
      result = execute_transform(text, { "address" => { "city" => "Portland" } })
      expect(result.output["Customer"]["City"]).to eq("Portland")
    end

    it "copies array element" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Customer}
        First = @.items[0]
      ODIN
      result = execute_transform(text, { "items" => ["a", "b", "c"] })
      expect(result.output["Customer"]["First"]).to eq("a")
    end

    it "returns nil for missing path" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Customer}
        Name = @.nonexistent
      ODIN
      result = execute_transform(text, { "name" => "Alice" })
      expect(result.output["Customer"]["Name"]).to be_nil
    end
  end

  # ── Literal Values ──

  describe "literal value operations" do
    it "assigns string literal" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Record}
        Status = "active"
      ODIN
      result = execute_transform(text, {})
      expect(result.output["Record"]["Status"]).to eq("active")
    end

    it "assigns integer literal" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Record}
        Count = ##42
      ODIN
      result = execute_transform(text, {})
      expect(result.output["Record"]["Count"]).to eq(42)
    end

    it "assigns float literal" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Record}
        Rate = #3.14
      ODIN
      result = execute_transform(text, {})
      expect(result.output["Record"]["Rate"]).to be_within(0.01).of(3.14)
    end

    it "assigns boolean literal" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Record}
        Active = ?true
      ODIN
      result = execute_transform(text, {})
      expect(result.output["Record"]["Active"]).to be true
    end

    it "assigns null literal" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Record}
        Empty = ~
      ODIN
      result = execute_transform(text, {})
      expect(result.output["Record"]["Empty"]).to be_nil
    end
  end

  # ── Verb Execution ──

  describe "verb execution" do
    it "executes %upper" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Customer}
        Name = %upper @.name
      ODIN
      result = execute_transform(text, { "name" => "alice" })
      expect(result.output["Customer"]["Name"]).to eq("ALICE")
    end

    it "executes %lower" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Customer}
        Name = %lower @.name
      ODIN
      result = execute_transform(text, { "name" => "ALICE" })
      expect(result.output["Customer"]["Name"]).to eq("alice")
    end

    it "executes %trim" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Customer}
        Name = %trim @.name
      ODIN
      result = execute_transform(text, { "name" => "  alice  " })
      expect(result.output["Customer"]["Name"]).to eq("alice")
    end

    it "executes nested %concat %upper" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Customer}
        Full = %concat %upper @.first " " @.last
      ODIN
      result = execute_transform(text, { "first" => "alice", "last" => "Smith" })
      expect(result.output["Customer"]["Full"]).to eq("ALICE Smith")
    end

    it "executes %add" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Math}
        Sum = %add @.a @.b
      ODIN
      result = execute_transform(text, { "a" => 10, "b" => 20 })
      expect(result.output["Math"]["Sum"]).to eq(30)
    end

    it "executes %subtract" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Math}
        Diff = %subtract @.a @.b
      ODIN
      result = execute_transform(text, { "a" => 30, "b" => 10 })
      expect(result.output["Math"]["Diff"]).to eq(20)
    end

    it "executes %multiply" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Math}
        Product = %multiply @.a @.b
      ODIN
      result = execute_transform(text, { "a" => 5, "b" => 6 })
      expect(result.output["Math"]["Product"]).to eq(30)
    end

    it "executes %eq" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Check}
        Same = %eq @.a @.b
      ODIN
      result = execute_transform(text, { "a" => "x", "b" => "x" })
      expect(result.output["Check"]["Same"]).to be true
    end

    it "executes %ne" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Check}
        Different = %ne @.a @.b
      ODIN
      result = execute_transform(text, { "a" => "x", "b" => "y" })
      expect(result.output["Check"]["Different"]).to be true
    end

    it "executes %ifNull" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Record}
        Name = %ifNull @.name "default"
      ODIN
      result = execute_transform(text, { "name" => nil })
      expect(result.output["Record"]["Name"]).to eq("default")
    end

    it "executes %isNull" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Record}
        IsNull = %isNull @.missing
      ODIN
      result = execute_transform(text, {})
      expect(result.output["Record"]["IsNull"]).to be true
    end

    it "executes %coalesce" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Record}
        Value = %coalesce @.first @.second @.third
      ODIN
      result = execute_transform(text, { "first" => nil, "second" => nil, "third" => "found" })
      expect(result.output["Record"]["Value"]).to eq("found")
    end

    it "executes %abs" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Math}
        Pos = %abs @.val
      ODIN
      result = execute_transform(text, { "val" => -42 })
      expect(result.output["Math"]["Pos"]).to eq(42)
    end

    it "executes %length on string" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Record}
        Len = %length @.name
      ODIN
      result = execute_transform(text, { "name" => "hello" })
      expect(result.output["Record"]["Len"]).to eq(5)
    end

    it "executes %length on array" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Record}
        Count = %length @.items
      ODIN
      result = execute_transform(text, { "items" => [1, 2, 3] })
      expect(result.output["Record"]["Count"]).to eq(3)
    end
  end

  # ── ifElse (Lazy Evaluation) ──

  describe "ifElse lazy evaluation" do
    it "evaluates true branch" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Record}
        Result = %ifElse %eq @.type "A" "Type A" "Other"
      ODIN
      result = execute_transform(text, { "type" => "A" })
      expect(result.output["Record"]["Result"]).to eq("Type A")
    end

    it "evaluates false branch" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Record}
        Result = %ifElse %eq @.type "A" "Type A" "Other"
      ODIN
      result = execute_transform(text, { "type" => "B" })
      expect(result.output["Record"]["Result"]).to eq("Other")
    end
  end

  # ── _each Loop Iteration ──

  describe "_each iteration" do
    it "iterates over array" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Items[]}
        _each = @.items
        Name = @.name
        Price = @.price
      ODIN
      source = {
        "items" => [
          { "name" => "Widget", "price" => 9.99 },
          { "name" => "Gadget", "price" => 19.99 }
        ]
      }
      result = execute_transform(text, source)
      items = result.output["Items"]
      expect(items).to be_an(Array)
      expect(items.length).to eq(2)
      expect(items[0]["Name"]).to eq("Widget")
      expect(items[1]["Name"]).to eq("Gadget")
    end

    it "provides _index in loop" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Items[]}
        _each = @.items
        Name = @.name
      ODIN
      source = {
        "items" => [
          { "name" => "First" },
          { "name" => "Second" }
        ]
      }
      result = execute_transform(text, source)
      expect(result.output["Items"].length).to eq(2)
    end

    it "handles empty array" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Items[]}
        _each = @.items
        Name = @.name
      ODIN
      result = execute_transform(text, { "items" => [] })
      expect(result.output).to have_key("Items")
      expect(result.output["Items"]).to eq([])
    end
  end

  # ── _when Conditional Segments ──

  describe "_when conditional segments" do
    it "processes segment when condition is true" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Active}
        _when = @.status = "active"
        Name = @.name
      ODIN
      result = execute_transform(text, { "status" => "active", "name" => "Alice" })
      expect(result.output["Active"]["Name"]).to eq("Alice")
    end

    it "skips segment when condition is false" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Active}
        _when = @.status = "active"
        Name = @.name
      ODIN
      result = execute_transform(text, { "status" => "inactive", "name" => "Alice" })
      expect(result.output).not_to have_key("Active")
    end
  end

  # ── _if Conditional Fields ──

  describe "_if conditional" do
    it "includes segment when _if is truthy" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Details}
        _if = @.hasDetails
        Info = @.info
      ODIN
      result = execute_transform(text, { "hasDetails" => true, "info" => "detail text" })
      expect(result.output["Details"]["Info"]).to eq("detail text")
    end

    it "skips segment when _if is falsy" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Details}
        _if = @.hasDetails
        Info = @.info
      ODIN
      result = execute_transform(text, { "hasDetails" => false, "info" => "detail text" })
      expect(result.output).not_to have_key("Details")
    end
  end

  # ── Header-Inline :if Conditional Sections ──

  describe "header-inline :if conditional" do
    it "includes section when condition holds" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {DuiDetails :if "@driver.has_dui = true"}
        State = @driver.dui.state
      ODIN
      source = { "driver" => { "has_dui" => true, "dui" => { "state" => "TX" } } }
      result = execute_transform(text, source)
      expect(result.output["DuiDetails"]["State"]).to eq("TX")
    end

    it "omits section when condition fails" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {DuiDetails :if "@driver.has_dui = true"}
        State = @driver.dui.state
      ODIN
      source = { "driver" => { "has_dui" => false } }
      result = execute_transform(text, source)
      expect(result.output).not_to have_key("DuiDetails")
    end
  end

  # ── Discriminator ──

  describe "discriminator-based segment selection" do
    it "processes segment matching discriminator value" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Auto}
        _discriminator = @.type
        _discriminatorValue = "auto"
        Make = @.make
      ODIN
      result = execute_transform(text, { "type" => "auto", "make" => "Honda" })
      expect(result.output["Auto"]["Make"]).to eq("Honda")
    end

    it "skips segment not matching discriminator" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Auto}
        _discriminator = @.type
        _discriminatorValue = "auto"
        Make = @.make
      ODIN
      result = execute_transform(text, { "type" => "home", "make" => "Honda" })
      expect(result.output).not_to have_key("Auto")
    end
  end

  # ── Accumulator ──

  describe "accumulator operations" do
    it "accumulates values across loop iterations" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"
        accumulator.total = ##0

        {Items[]}
        _each = @.items
        Name = @.name
        Running = %accumulate "total" @.amount
      ODIN
      source = {
        "items" => [
          { "name" => "A", "amount" => 10 },
          { "name" => "B", "amount" => 20 },
          { "name" => "C", "amount" => 30 }
        ]
      }
      result = execute_transform(text, source)
      items = result.output["Items"]
      expect(items.last["Running"]).to eq(60.0)
    end
  end

  # ── Confidential Enforcement ──

  describe "confidential enforcement" do
    it "redacts confidential fields" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"
        enforceConfidential = "redact"

        {Customer}
        Name = @.name
        SSN = @.ssn :confidential
      ODIN
      result = execute_transform(text, { "name" => "Alice", "ssn" => "123-45-6789" })
      expect(result.output["Customer"]["Name"]).to eq("Alice")
      expect(result.output["Customer"]["SSN"]).to be_nil
    end

    it "masks confidential string fields" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"
        enforceConfidential = "mask"

        {Customer}
        Name = @.name
        SSN = @.ssn :confidential
      ODIN
      result = execute_transform(text, { "name" => "Alice", "ssn" => "123-45-6789" })
      expect(result.output["Customer"]["Name"]).to eq("Alice")
      ssn = result.output["Customer"]["SSN"]
      expect(ssn).to match(/\A\*+\z/)
    end
  end

  # ── format_output ──

  describe "format_output" do
    it "produces JSON string for json target" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Customer}
        Name = @.name
      ODIN
      result = execute_transform(text, { "name" => "Alice" })
      expect(result.formatted).to be_a(String)
      parsed = JSON.parse(result.formatted)
      expect(parsed["Customer"]["Name"]).to eq("Alice")
    end

    it "produces ODIN string for odin target" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->odin"

        {Customer}
        Name = @.name
      ODIN
      result = execute_transform(text, { "name" => "Alice" })
      expect(result.formatted).to be_a(String)
      expect(result.formatted).to include("Customer")
      expect(result.formatted).to include("Alice")
    end

    it "produces CSV string for csv target" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->csv"
        target.format = "csv"

        {Items[]}
        _each = @.items
        Name = @.name
        Price = @.price
      ODIN
      source = {
        "items" => [
          { "name" => "Widget", "price" => 9.99 },
          { "name" => "Gadget", "price" => 19.99 }
        ]
      }
      result = execute_transform(text, source)
      expect(result.formatted).to be_a(String)
      expect(result.formatted).to include("Name")
      expect(result.formatted).to include("Widget")
    end

    it "produces XML string for xml target" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->xml"
        target.format = "xml"

        {Customer}
        Name = @.name
      ODIN
      result = execute_transform(text, { "name" => "Alice" })
      expect(result.formatted).to be_a(String)
      expect(result.formatted).to include("<?xml")
      expect(result.formatted).to include("Alice")
    end
  end

  # ── Type Directives ──

  describe "type directives" do
    it "coerces to integer via :type" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Record}
        Count = @.count :type integer
      ODIN
      result = execute_transform(text, { "count" => "42" })
      expect(result.output["Record"]["Count"]).to eq(42)
    end
  end

  # ── Multiple Segments ──

  describe "multiple segments" do
    it "processes multiple segments" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Person}
        Name = @.name

        {Location}
        City = @.city
      ODIN
      result = execute_transform(text, { "name" => "Alice", "city" => "Portland" })
      expect(result.output["Person"]["Name"]).to eq("Alice")
      expect(result.output["Location"]["City"]).to eq("Portland")
    end
  end

  # ── Constants ──

  describe "constants" do
    it "uses constants in expressions" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Constants}
        version = "2.0"

        {Record}
        Name = @.name
      ODIN
      result = execute_transform(text, { "name" => "test" })
      expect(result.output["Record"]["Name"]).to eq("test")
    end
  end

  # ── Cross-Segment References ──

  describe "cross-segment references" do
    it "multiple segments produce nested output" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Header}
        Title = "Report"

        {Body}
        Content = @.content
      ODIN
      result = execute_transform(text, { "content" => "data here" })
      expect(result.output["Header"]["Title"]).to eq("Report")
      expect(result.output["Body"]["Content"]).to eq("data here")
    end
  end

  # ── Error Handling ──

  describe "error handling" do
    it "raises a coded T001 for an unknown verb" do
      ctx = Odin::Transform::VerbContext.new
      expect {
        engine.invoke_verb("nonExistentVerb", [], ctx)
      }.to raise_error(Odin::Transform::TransformEngine::CodedTransformError) { |e|
        expect(e.transform_error.code).to eq("T001")
      }
    end
  end

  # ── Direct Verb Invocation (invoke_verb) ──

  describe "invoke_verb" do
    let(:ctx) { Odin::Transform::VerbContext.new }

    it "invokes upper" do
      result = engine.invoke_verb("upper", [dv.of_string("hello")], ctx)
      expect(result).to eq(dv.of_string("HELLO"))
    end

    it "invokes lower" do
      result = engine.invoke_verb("lower", [dv.of_string("HELLO")], ctx)
      expect(result).to eq(dv.of_string("hello"))
    end

    it "invokes concat" do
      result = engine.invoke_verb("concat", [dv.of_string("a"), dv.of_string("b"), dv.of_string("c")], ctx)
      expect(result).to eq(dv.of_string("abc"))
    end

    it "invokes add with integers" do
      result = engine.invoke_verb("add", [dv.of_integer(10), dv.of_integer(20)], ctx)
      expect(result).to eq(dv.of_integer(30))
    end

    it "invokes subtract" do
      result = engine.invoke_verb("subtract", [dv.of_integer(30), dv.of_integer(10)], ctx)
      expect(result).to eq(dv.of_integer(20))
    end

    it "invokes multiply" do
      result = engine.invoke_verb("multiply", [dv.of_integer(5), dv.of_integer(6)], ctx)
      expect(result).to eq(dv.of_integer(30))
    end

    it "invokes divide" do
      result = engine.invoke_verb("divide", [dv.of_float(10.0), dv.of_float(3.0)], ctx)
      expect(result.value).to be_within(0.001).of(3.333)
    end

    it "divide by zero returns null" do
      result = engine.invoke_verb("divide", [dv.of_integer(10), dv.of_integer(0)], ctx)
      expect(result.null?).to be true
    end

    it "invokes eq" do
      result = engine.invoke_verb("eq", [dv.of_string("a"), dv.of_string("a")], ctx)
      expect(result).to eq(dv.of_bool(true))
    end

    it "invokes ne" do
      result = engine.invoke_verb("ne", [dv.of_string("a"), dv.of_string("b")], ctx)
      expect(result).to eq(dv.of_bool(true))
    end

    it "invokes isNull true" do
      result = engine.invoke_verb("isNull", [dv.of_null], ctx)
      expect(result).to eq(dv.of_bool(true))
    end

    it "invokes isNull false" do
      result = engine.invoke_verb("isNull", [dv.of_string("x")], ctx)
      expect(result).to eq(dv.of_bool(false))
    end

    it "invokes not" do
      result = engine.invoke_verb("not", [dv.of_bool(true)], ctx)
      expect(result).to eq(dv.of_bool(false))
    end

    it "invokes and" do
      result = engine.invoke_verb("and", [dv.of_bool(true), dv.of_bool(false)], ctx)
      expect(result).to eq(dv.of_bool(false))
    end

    it "invokes or" do
      result = engine.invoke_verb("or", [dv.of_bool(false), dv.of_bool(true)], ctx)
      expect(result).to eq(dv.of_bool(true))
    end

    it "invokes lt" do
      result = engine.invoke_verb("lt", [dv.of_integer(1), dv.of_integer(2)], ctx)
      expect(result).to eq(dv.of_bool(true))
    end

    it "invokes gt" do
      result = engine.invoke_verb("gt", [dv.of_integer(2), dv.of_integer(1)], ctx)
      expect(result).to eq(dv.of_bool(true))
    end

    it "invokes contains" do
      result = engine.invoke_verb("contains", [dv.of_string("hello world"), dv.of_string("world")], ctx)
      expect(result).to eq(dv.of_bool(true))
    end

    it "invokes startsWith" do
      result = engine.invoke_verb("startsWith", [dv.of_string("hello"), dv.of_string("hel")], ctx)
      expect(result).to eq(dv.of_bool(true))
    end

    it "invokes endsWith" do
      result = engine.invoke_verb("endsWith", [dv.of_string("hello"), dv.of_string("llo")], ctx)
      expect(result).to eq(dv.of_bool(true))
    end

    it "invokes substring" do
      result = engine.invoke_verb("substring", [dv.of_string("hello world"), dv.of_integer(0), dv.of_integer(5)], ctx)
      expect(result).to eq(dv.of_string("hello"))
    end

    it "invokes replace" do
      result = engine.invoke_verb("replace", [dv.of_string("hello world"), dv.of_string("world"), dv.of_string("ruby")], ctx)
      expect(result).to eq(dv.of_string("hello ruby"))
    end

    it "invokes abs" do
      result = engine.invoke_verb("abs", [dv.of_integer(-42)], ctx)
      expect(result).to eq(dv.of_integer(42))
    end

    it "invokes floor" do
      result = engine.invoke_verb("floor", [dv.of_float(3.7)], ctx)
      expect(result).to eq(dv.of_integer(3))
    end

    it "invokes ceil" do
      result = engine.invoke_verb("ceil", [dv.of_float(3.2)], ctx)
      expect(result).to eq(dv.of_integer(4))
    end

    it "invokes round" do
      result = engine.invoke_verb("round", [dv.of_float(3.456), dv.of_integer(2)], ctx)
      expect(result.value).to be_within(0.001).of(3.46)
    end

    it "invokes negate" do
      result = engine.invoke_verb("negate", [dv.of_integer(42)], ctx)
      expect(result).to eq(dv.of_integer(-42))
    end

    it "invokes mod" do
      result = engine.invoke_verb("mod", [dv.of_integer(10), dv.of_integer(3)], ctx)
      expect(result).to eq(dv.of_integer(1))
    end

    it "invokes coerceString" do
      result = engine.invoke_verb("coerceString", [dv.of_integer(42)], ctx)
      expect(result).to eq(dv.of_string("42"))
    end

    it "invokes coerceInteger" do
      result = engine.invoke_verb("coerceInteger", [dv.of_string("42")], ctx)
      expect(result).to eq(dv.of_integer(42))
    end

    it "invokes coerceNumber" do
      result = engine.invoke_verb("coerceNumber", [dv.of_string("3.14")], ctx)
      expect(result.value).to be_within(0.001).of(3.14)
    end

    it "invokes coerceBoolean" do
      result = engine.invoke_verb("coerceBoolean", [dv.of_string("hello")], ctx)
      expect(result).to eq(dv.of_bool(true))
    end

    it "invokes coerceTimestamp" do
      result = engine.invoke_verb("coerceTimestamp", [dv.of_string("2024-06-15T09:30:00Z")], ctx)
      expect(result.timestamp?).to be true
      expect(result.to_string).to eq("2024-06-15T09:30:00.000Z")
    end

    it "coerceTimestamp returns null for an unparseable value" do
      result = engine.invoke_verb("coerceTimestamp", [dv.of_string("not a date")], ctx)
      expect(result.null?).to be true
    end

    it "invokes isString" do
      expect(engine.invoke_verb("isString", [dv.of_string("x")], ctx)).to eq(dv.of_bool(true))
      expect(engine.invoke_verb("isString", [dv.of_integer(1)], ctx)).to eq(dv.of_bool(false))
    end

    it "invokes isNumber" do
      expect(engine.invoke_verb("isNumber", [dv.of_float(1.0)], ctx)).to eq(dv.of_bool(true))
      expect(engine.invoke_verb("isNumber", [dv.of_string("x")], ctx)).to eq(dv.of_bool(false))
    end

    it "invokes typeOf" do
      expect(engine.invoke_verb("typeOf", [dv.of_string("x")], ctx).value).to eq("string")
      expect(engine.invoke_verb("typeOf", [dv.of_integer(1)], ctx).value).to eq("integer")
      expect(engine.invoke_verb("typeOf", [dv.of_null], ctx).value).to eq("null")
    end

    it "invokes length on string" do
      result = engine.invoke_verb("length", [dv.of_string("hello")], ctx)
      expect(result).to eq(dv.of_integer(5))
    end

    it "invokes length on array" do
      result = engine.invoke_verb("length", [dv.of_array([dv.of_integer(1), dv.of_integer(2)])], ctx)
      expect(result).to eq(dv.of_integer(2))
    end

    it "invokes ifNull with non-null" do
      result = engine.invoke_verb("ifNull", [dv.of_string("x"), dv.of_string("default")], ctx)
      expect(result).to eq(dv.of_string("x"))
    end

    it "invokes ifNull with null" do
      result = engine.invoke_verb("ifNull", [dv.of_null, dv.of_string("default")], ctx)
      expect(result).to eq(dv.of_string("default"))
    end

    it "invokes ifEmpty with empty string" do
      result = engine.invoke_verb("ifEmpty", [dv.of_string(""), dv.of_string("default")], ctx)
      expect(result).to eq(dv.of_string("default"))
    end

    it "invokes coalesce" do
      result = engine.invoke_verb("coalesce", [dv.of_null, dv.of_null, dv.of_string("found")], ctx)
      expect(result).to eq(dv.of_string("found"))
    end

    it "invokes keys" do
      obj = dv.of_object({ "a" => dv.of_integer(1), "b" => dv.of_integer(2) })
      result = engine.invoke_verb("keys", [obj], ctx)
      expect(result.array?).to be true
      expect(result.value.map(&:value)).to contain_exactly("a", "b")
    end

    it "invokes values" do
      obj = dv.of_object({ "a" => dv.of_integer(1), "b" => dv.of_integer(2) })
      result = engine.invoke_verb("values", [obj], ctx)
      expect(result.array?).to be true
    end

    it "invokes has" do
      obj = dv.of_object({ "a" => dv.of_integer(1) })
      expect(engine.invoke_verb("has", [obj, dv.of_string("a")], ctx)).to eq(dv.of_bool(true))
      expect(engine.invoke_verb("has", [obj, dv.of_string("b")], ctx)).to eq(dv.of_bool(false))
    end

    it "invokes merge" do
      a = dv.of_object({ "x" => dv.of_integer(1) })
      b = dv.of_object({ "y" => dv.of_integer(2) })
      result = engine.invoke_verb("merge", [a, b], ctx)
      expect(result.object?).to be true
      expect(result.get("x")).to eq(dv.of_integer(1))
      expect(result.get("y")).to eq(dv.of_integer(2))
    end

    it "invokes first/last" do
      arr = dv.of_array([dv.of_integer(1), dv.of_integer(2), dv.of_integer(3)])
      expect(engine.invoke_verb("first", [arr], ctx)).to eq(dv.of_integer(1))
      expect(engine.invoke_verb("last", [arr], ctx)).to eq(dv.of_integer(3))
    end

    it "invokes count" do
      arr = dv.of_array([dv.of_integer(1), dv.of_integer(2)])
      result = engine.invoke_verb("count", [arr], ctx)
      expect(result).to eq(dv.of_integer(2))
    end

    it "invokes sum" do
      arr = dv.of_array([dv.of_integer(10), dv.of_integer(20), dv.of_integer(30)])
      result = engine.invoke_verb("sum", [arr], ctx)
      expect(result.value).to eq(60.0)
    end

    it "invokes join" do
      arr = dv.of_array([dv.of_string("a"), dv.of_string("b"), dv.of_string("c")])
      result = engine.invoke_verb("join", [arr, dv.of_string("-")], ctx)
      expect(result).to eq(dv.of_string("a-b-c"))
    end

    it "invokes sequence" do
      r1 = engine.invoke_verb("sequence", [dv.of_string("seq1")], ctx)
      r2 = engine.invoke_verb("sequence", [dv.of_string("seq1")], ctx)
      expect(r1).to eq(dv.of_integer(1))
      expect(r2).to eq(dv.of_integer(2))
    end

    it "invokes at" do
      arr = dv.of_array([dv.of_string("a"), dv.of_string("b")])
      result = engine.invoke_verb("at", [arr, dv.of_integer(1)], ctx)
      expect(result).to eq(dv.of_string("b"))
    end

    it "invokes get with default" do
      obj = dv.of_object({ "x" => dv.of_integer(1) })
      result = engine.invoke_verb("get", [obj, dv.of_string("y"), dv.of_string("default")], ctx)
      expect(result).to eq(dv.of_string("default"))
    end
  end

  # ── Condition Evaluation ──

  describe "condition evaluation" do
    let(:ctx) { Odin::Transform::VerbContext.new }

    it "evaluates equality condition" do
      source = dv.from_ruby({ "status" => "active" })
      ctx.source = source
      result = engine.send(:evaluate_condition, '@.status = "active"', source, ctx)
      expect(result).to be true
    end

    it "evaluates inequality condition" do
      source = dv.from_ruby({ "status" => "inactive" })
      ctx.source = source
      result = engine.send(:evaluate_condition, '@.status != "active"', source, ctx)
      expect(result).to be true
    end

    it "evaluates numeric comparison" do
      source = dv.from_ruby({ "age" => 25 })
      ctx.source = source
      result = engine.send(:evaluate_condition, "@.age > 18", source, ctx)
      expect(result).to be true
    end

    it "evaluates truthy check" do
      source = dv.from_ruby({ "flag" => true })
      ctx.source = source
      result = engine.send(:evaluate_condition, "@.flag", source, ctx)
      expect(result).to be true
    end

    it "evaluates falsy check" do
      source = dv.from_ruby({ "flag" => false })
      ctx.source = source
      result = engine.send(:evaluate_condition, "@.flag", source, ctx)
      expect(result).to be false
    end
  end

  # ── Verb-Expression Segment Conditions ──

  describe "verb-expression segment conditions" do
    def header
      <<~HDR
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"
      HDR
    end

    it "includes section when verb condition is truthy" do
      text = header + <<~ODIN
        {Detail :if %eq @.status "active"}
        flag = "yes"
      ODIN
      result = execute_transform(text, { "status" => "active" })
      expect(result.output["Detail"]).to eq({ "flag" => "yes" })
    end

    it "omits section when verb condition is falsy" do
      text = header + <<~ODIN
        {Detail :if %eq @.status "active"}
        flag = "yes"
      ODIN
      result = execute_transform(text, { "status" => "inactive" })
      expect(result.output).not_to have_key("Detail")
    end

    it "evaluates %and" do
      text = header + <<~ODIN
        {Detail :if %and @.a @.b}
        flag = "yes"
      ODIN
      expect(execute_transform(text, { "a" => true, "b" => true }).output).to have_key("Detail")
      expect(execute_transform(text, { "a" => true, "b" => false }).output).not_to have_key("Detail")
    end

    it "evaluates %or" do
      text = header + <<~ODIN
        {Detail :if %or @.a @.b}
        flag = "yes"
      ODIN
      expect(execute_transform(text, { "a" => false, "b" => true }).output).to have_key("Detail")
      expect(execute_transform(text, { "a" => false, "b" => false }).output).not_to have_key("Detail")
    end

    it "evaluates %not" do
      text = header + <<~ODIN
        {Detail :if %not @.disabled}
        flag = "yes"
      ODIN
      expect(execute_transform(text, { "disabled" => false }).output).to have_key("Detail")
      expect(execute_transform(text, { "disabled" => true }).output).not_to have_key("Detail")
    end

    it "evaluates %lt" do
      text = header + <<~ODIN
        {Detail :if %lt @.age ##25}
        flag = "yes"
      ODIN
      expect(execute_transform(text, { "age" => 20 }).output).to have_key("Detail")
      expect(execute_transform(text, { "age" => 30 }).output).not_to have_key("Detail")
    end

    it "supports legacy quoted-infix condition (back-compat)" do
      text = header + <<~ODIN
        {Detail}
        _if = "@.status = 'active'"
        flag = "yes"
      ODIN
      expect(execute_transform(text, { "status" => "active" }).output).to have_key("Detail")
      expect(execute_transform(text, { "status" => "off" }).output).not_to have_key("Detail")
    end

    it "accepts a verb-expression body condition (_if = %verb)" do
      text = header + <<~ODIN
        {Detail}
        _if = %eq @.status "active"
        flag = "yes"
      ODIN
      expect(execute_transform(text, { "status" => "active" }).output).to have_key("Detail")
      expect(execute_transform(text, { "status" => "off" }).output).not_to have_key("Detail")
    end
  end

  # ── Conditional Chains (if/elif/else) ──

  describe "conditional chains" do
    def chain_transform
      <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {High :if %eq @.tier "dui"}
        band = "high"

        {Young :elif %lt @.age ##25}
        band = "young"

        {Standard :else}
        band = "standard"
      ODIN
    end

    it "emits only the if branch when its condition holds" do
      result = execute_transform(chain_transform, { "tier" => "dui", "age" => 30 })
      expect(result.output).to have_key("High")
      expect(result.output).not_to have_key("Young")
      expect(result.output).not_to have_key("Standard")
      expect(result.success?).to be true
    end

    it "falls through to a matching elif branch" do
      result = execute_transform(chain_transform, { "tier" => "standard", "age" => 20 })
      expect(result.output).not_to have_key("High")
      expect(result.output["Young"]).to eq({ "band" => "young" })
      expect(result.output).not_to have_key("Standard")
    end

    it "emits the else branch when no condition matches" do
      result = execute_transform(chain_transform, { "tier" => "standard", "age" => 40 })
      expect(result.output).not_to have_key("High")
      expect(result.output).not_to have_key("Young")
      expect(result.output["Standard"]).to eq({ "band" => "standard" })
    end

    it "supports an if-only chain" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {High :if %eq @.tier "dui"}
        band = "high"
      ODIN
      expect(execute_transform(text, { "tier" => "dui" }).output).to have_key("High")
      expect(execute_transform(text, { "tier" => "std" }).output).not_to have_key("High")
    end

    it "raises T012 for an orphan elif" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Orphan :elif %eq @.tier "dui"}
        band = "x"
      ODIN
      result = execute_transform(text, { "tier" => "dui" })
      expect(result.success?).to be false
      expect(result.errors.first.code).to eq("T012")
      expect(result.errors.first.message).to eq("'elif' segment has no preceding 'if'")
    end

    it "raises T012 for an orphan else" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Orphan :else}
        band = "x"
      ODIN
      result = execute_transform(text, {})
      expect(result.success?).to be false
      expect(result.errors.first.code).to eq("T012")
      expect(result.errors.first.message).to eq("'else' segment has no preceding 'if'")
    end
  end

  # ── Prefix Coercion on References ──

  describe "prefix coercion on references" do
    def coercion_transform(mappings)
      header = "{$}\n" \
               "odin = \"1.0.0\"\n" \
               "transform = \"1.0.0\"\n" \
               "direction = \"json->odin\"\n\n" \
               "{$source}\nformat = \"json\"\n\n" \
               "{$target}\nformat = \"odin\"\n\n" \
               "{vehicle}\n"
      header + mappings
    end

    it "coerces a string reference to an integer with ##" do
      text = coercion_transform("year = ##@.year\n")
      result = execute_transform(text, { "year" => "2021" })
      expect(result.output["vehicle"]["year"]).to eq(2021)
      expect(result.formatted).to include("year = ##2021")
    end

    it 'coerces a string reference to currency with #$' do
      text = coercion_transform('premium = #$@.premium' + "\n")
      result = execute_transform(text, { "premium" => "1499.50" })
      expect(result.formatted).to include('premium = #$1499.50')
    end

    it "coerces a string reference to a number with #" do
      text = coercion_transform("rate = #@.rate\n")
      result = execute_transform(text, { "rate" => "3.5" })
      expect(result.output["vehicle"]["rate"]).to be_within(0.001).of(3.5)
    end

    it 'coerces a string reference to a percent with #%' do
      text = coercion_transform('pct = #%@.pct' + "\n")
      result = execute_transform(text, { "pct" => "42" })
      expect(result.formatted).to include('pct = #%42')
    end
  end

  # ── String Interpolation ──

  describe "string interpolation" do
    def interp_transform(mappings)
      "{$}\n" \
        "odin = \"1.0.0\"\n" \
        "transform = \"1.0.0\"\n" \
        "direction = \"json->json\"\n\n" \
        "{Receipt}\n" + mappings
    end

    it "interpolates a source path reference" do
      text = interp_transform("name = \"${@.name}\"\n")
      result = execute_transform(text, { "name" => "Alice" })
      expect(result.output["Receipt"]["name"]).to eq("Alice")
    end

    it "interpolates a value within surrounding text" do
      text = interp_transform("greeting = \"Hello, ${@.name}!\"\n")
      result = execute_transform(text, { "name" => "Bob" })
      expect(result.output["Receipt"]["greeting"]).to eq("Hello, Bob!")
    end

    it "treats \\$ as a literal dollar sign" do
      text = interp_transform("price = \"Total: \\$${@.amount}\"\n")
      result = execute_transform(text, { "amount" => "42.00" })
      expect(result.output["Receipt"]["price"]).to eq("Total: $42.00")
    end

    it "preserves a literal ${...} when escaped with \\${" do
      text = interp_transform("template = \"Use \\${@.field} for the value\"\n")
      result = execute_transform(text, { "field" => "X" })
      expect(result.output["Receipt"]["template"]).to eq("Use ${@.field} for the value")
    end
  end

  # ── Nested Loops (cross-product) ──

  describe "nested :loop directives" do
    def loop_header(body)
      <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"
        target.format = "json"

        #{body}
      ODIN
    end

    # happy: two-level cross-product
    it "iterates a two-level cross-product binding each :as alias" do
      text = loop_header(<<~SEG)
        {rows[]}
        :loop vehicles :as veh
        :loop .coverages :as cov
        vin = "@veh.vin"
        code = "@cov.code"
      SEG
      src = {
        "vehicles" => [
          { "vin" => "A", "coverages" => [{ "code" => "X" }, { "code" => "Y" }] },
          { "vin" => "B", "coverages" => [{ "code" => "Z" }] }
        ]
      }
      result = execute_transform(text, src)
      expect(result.output["rows"]).to eq([
        { "vin" => "A", "code" => "X" },
        { "vin" => "A", "code" => "Y" },
        { "vin" => "B", "code" => "Z" }
      ])
    end

    # happy: three-level cross-product
    it "iterates a three-level cross-product" do
      text = loop_header(<<~SEG)
        {rows[]}
        :loop regions :as r
        :loop .stores :as s
        :loop .items :as i
        region = "@r.name"
        store = "@s.id"
        sku = "@i.sku"
      SEG
      src = {
        "regions" => [
          { "name" => "West", "stores" => [{ "id" => "S1", "items" => [{ "sku" => "X" }, { "sku" => "Y" }] }] },
          { "name" => "East", "stores" => [{ "id" => "S2", "items" => [{ "sku" => "Z" }] }] }
        ]
      }
      result = execute_transform(text, src)
      expect(result.output["rows"]).to eq([
        { "region" => "West", "store" => "S1", "sku" => "X" },
        { "region" => "West", "store" => "S1", "sku" => "Y" },
        { "region" => "East", "store" => "S2", "sku" => "Z" }
      ])
    end

    # edge: counter binds innermost index and resets per outer item
    it "binds :counter to the innermost index and resets per outer item" do
      text = loop_header(<<~SEG)
        {rows[]}
        :loop vehicles :as veh
        :loop .coverages :as cov
        :counter idx
        vin = "@veh.vin"
        code = "@cov.code"
        cov_index = "@idx"
      SEG
      src = {
        "vehicles" => [
          { "vin" => "V1", "coverages" => [{ "code" => "A" }, { "code" => "B" }] },
          { "vin" => "V3", "coverages" => [{ "code" => "C" }] }
        ]
      }
      result = execute_transform(text, src)
      expect(result.output["rows"]).to eq([
        { "vin" => "V1", "code" => "A", "cov_index" => 0 },
        { "vin" => "V1", "code" => "B", "cov_index" => 1 },
        { "vin" => "V3", "code" => "C", "cov_index" => 0 }
      ])
    end

    # error/edge: an outer item with a missing or non-array inner yields no rows
    it "yields no rows for an outer item whose inner source is absent" do
      text = loop_header(<<~SEG)
        {rows[]}
        :loop vehicles :as veh
        :loop .coverages :as cov
        vin = "@veh.vin"
        code = "@cov.code"
      SEG
      src = {
        "vehicles" => [
          { "vin" => "V1", "coverages" => [{ "code" => "A" }] },
          { "vin" => "V2" },
          { "vin" => "V3", "coverages" => [{ "code" => "C" }] }
        ]
      }
      result = execute_transform(text, src)
      expect(result.output["rows"]).to eq([
        { "vin" => "V1", "code" => "A" },
        { "vin" => "V3", "code" => "C" }
      ])
      expect(result.errors).to be_empty
    end

    # edge: a present non-array outermost source raises T009
    it "raises T009 when the outermost source is a present non-array scalar" do
      text = loop_header(<<~SEG)
        {rows[]}
        :loop vehicles :as veh
        :loop .coverages :as cov
        vin = "@veh.vin"
      SEG
      result = execute_transform(text, { "vehicles" => "not-an-array" })
      expect(result.errors.first&.code).to eq("T009")
    end
  end

  # ── :literal Blocks ──

  describe ":literal block segments" do
    def fwf_literal(body)
      <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->fixed-width"
        target.format = "fixed-width"

        #{body}
      ODIN
    end

    # happy: path and verb interpolation
    it "interpolates path and verb expressions in a literal block" do
      text = fwf_literal(<<~SEG)
        {HDR}
        :literal
        """
        HDR|${@.number}|${%upper @.code}
        """
      SEG
      result = execute_transform(text, { "number" => "P-100", "code" => "abc" })
      expect(result.formatted).to eq("HDR|P-100|ABC")
    end

    # happy: a literal block renders once per loop item
    it "renders a literal block once per loop item" do
      text = fwf_literal(<<~SEG)
        {DET[]}
        :loop @items
        :literal
        """
        DET|${@.sku}|${@.qty}
        """
      SEG
      src = { "items" => [{ "sku" => "A1", "qty" => "2" }, { "sku" => "B2", "qty" => "5" }] }
      result = execute_transform(text, src)
      expect(result.formatted).to eq("DET|A1|2\nDET|B2|5")
    end

    # edge: escapes \${ -> ${, \$ -> $, \\ -> \
    it "applies literal-block escapes" do
      text = fwf_literal(<<~SEG)
        {NOTE}
        :literal
        """
        NOTE|literal:\\${@.number} dollar:\\$ slash:\\\\ value:${@.number}
        """
      SEG
      result = execute_transform(text, { "number" => "P-100" })
      expect(result.formatted).to eq("NOTE|literal:${@.number} dollar:$ slash:\\ value:P-100")
    end

    # edge: interior blank lines are preserved verbatim
    it "preserves interior blank lines in a literal body" do
      text = fwf_literal("{B}\n:literal\n\"\"\"\nfirst\n\nlast\n\"\"\"\n")
      result = execute_transform(text, {})
      expect(result.formatted).to eq("first\n\nlast")
    end

    # error: nested interpolation is rejected with T014
    it "rejects nested interpolation with a T014 error" do
      text = fwf_literal("{X}\n:literal\n\"\"\"\nval:${@.a ${@.b}}\n\"\"\"\n")
      result = execute_transform(text, { "a" => "1", "b" => "2" })
      codes = result.errors.map(&:code)
      expect(codes).to include("T014")
    end
  end
end
