# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Odin::Transform::TransformParser do
  let(:parser) { described_class.new }
  let(:dv) { Odin::Types::DynValue }

  # ── Helper: Build a minimal valid transform ──
  def make_transform(body, header: nil)
    header ||= <<~ODIN
      {$}
      odin = "1.0.0"
      transform = "1.0.0"
      direction = "json->json"
    ODIN
    "#{header}\n#{body}"
  end

  # ── Header Parsing ──

  describe "header parsing" do
    it "parses direction" do
      text = make_transform("")
      result = parser.parse(text)
      expect(result.header.direction).to eq("json->json")
    end

    it "parses odin version" do
      text = make_transform("")
      result = parser.parse(text)
      expect(result.header.odin_version).to eq("1.0.0")
    end

    it "parses transform version" do
      text = make_transform("")
      result = parser.parse(text)
      expect(result.header.transform_version).to eq("1.0.0")
    end

    it "parses json->odin direction" do
      header = "{$}\nodin = \"1.0.0\"\ntransform = \"1.0.0\"\ndirection = \"json->odin\""
      result = parser.parse(header)
      expect(result.header.direction).to eq("json->odin")
      expect(result.target_format).to eq("odin")
    end

    it "parses explicit target.format" do
      header = "{$}\nodin = \"1.0.0\"\ntransform = \"1.0.0\"\ndirection = \"json->json\"\ntarget.format = \"csv\""
      result = parser.parse(header)
      expect(result.header.target_format).to eq("csv")
    end

    it "parses enforceConfidential = redact" do
      header = "{$}\nodin = \"1.0.0\"\ntransform = \"1.0.0\"\ndirection = \"json->json\"\nenforceConfidential = \"redact\""
      result = parser.parse(header)
      expect(result.header.enforce_confidential).to eq(Odin::Transform::ConfidentialMode::REDACT)
    end

    it "parses enforceConfidential = mask" do
      header = "{$}\nodin = \"1.0.0\"\ntransform = \"1.0.0\"\ndirection = \"json->json\"\nenforceConfidential = \"mask\""
      result = parser.parse(header)
      expect(result.header.enforce_confidential).to eq(Odin::Transform::ConfidentialMode::MASK)
    end

    it "parses source options" do
      header = "{$}\nodin = \"1.0.0\"\ntransform = \"1.0.0\"\ndirection = \"csv->odin\"\nsource.delimiter = \"|\""
      result = parser.parse(header)
      expect(result.header.source_options["delimiter"]).to eq("|")
    end

    it "parses target options" do
      header = "{$}\nodin = \"1.0.0\"\ntransform = \"1.0.0\"\ndirection = \"json->xml\"\ntarget.rootElement = \"data\""
      result = parser.parse(header)
      expect(result.header.target_options["rootElement"]).to eq("data")
    end

    it "infers target format from direction" do
      header = "{$}\nodin = \"1.0.0\"\ntransform = \"1.0.0\"\ndirection = \"json->odin\""
      result = parser.parse(header)
      expect(result.target_format).to eq("odin")
    end

    it "infers source format from direction" do
      header = "{$}\nodin = \"1.0.0\"\ntransform = \"1.0.0\"\ndirection = \"csv->odin\""
      result = parser.parse(header)
      expect(result.source_format).to eq("csv")
    end
  end

  # ── Error Cases ──

  describe "error cases" do
    it "raises on nil input" do
      expect { parser.parse(nil) }.to raise_error(Odin::Transform::TransformParser::ParseError)
    end

    it "raises on empty input" do
      expect { parser.parse("") }.to raise_error(Odin::Transform::TransformParser::ParseError)
    end

    it "raises on whitespace-only input" do
      expect { parser.parse("   ") }.to raise_error(Odin::Transform::TransformParser::ParseError)
    end
  end

  # ── Expression Parsing: Literals ──

  describe "literal expression parsing" do
    it "parses quoted string" do
      expr, = parser.parse_expression_string('"hello"')
      expect(expr).to be_a(Odin::Transform::LiteralExpr)
      expect(expr.value).to eq(dv.of_string("hello"))
    end

    it "parses integer literal ##42" do
      expr, = parser.parse_expression_string("##42")
      expect(expr).to be_a(Odin::Transform::LiteralExpr)
      expect(expr.value).to eq(dv.of_integer(42))
    end

    it "parses negative integer ##-10" do
      expr, = parser.parse_expression_string("##-10")
      expect(expr).to be_a(Odin::Transform::LiteralExpr)
      expect(expr.value).to eq(dv.of_integer(-10))
    end

    it "parses float literal #3.14" do
      expr, = parser.parse_expression_string("#3.14")
      expect(expr).to be_a(Odin::Transform::LiteralExpr)
      expect(expr.value).to eq(dv.of_float(3.14))
    end

    it "parses currency literal #$99.99" do
      expr, = parser.parse_expression_string('#$99.99')
      expect(expr).to be_a(Odin::Transform::LiteralExpr)
      expect(expr.value.currency?).to be true
      expect(expr.value.value).to be_within(0.01).of(99.99)
    end

    it "parses boolean true" do
      expr, = parser.parse_expression_string("?true")
      expect(expr).to be_a(Odin::Transform::LiteralExpr)
      expect(expr.value).to eq(dv.of_bool(true))
    end

    it "parses boolean false" do
      expr, = parser.parse_expression_string("?false")
      expect(expr).to be_a(Odin::Transform::LiteralExpr)
      expect(expr.value).to eq(dv.of_bool(false))
    end

    it "parses unqualified true" do
      expr, = parser.parse_expression_string("true")
      expect(expr).to be_a(Odin::Transform::LiteralExpr)
      expect(expr.value).to eq(dv.of_bool(true))
    end

    it "parses unqualified false" do
      expr, = parser.parse_expression_string("false")
      expect(expr).to be_a(Odin::Transform::LiteralExpr)
      expect(expr.value).to eq(dv.of_bool(false))
    end

    it "parses null ~" do
      expr, = parser.parse_expression_string("~")
      expect(expr).to be_a(Odin::Transform::LiteralExpr)
      expect(expr.value).to eq(dv.of_null)
    end

    it "parses empty/nil as null" do
      expr, = parser.parse_expression_string("")
      expect(expr).to be_a(Odin::Transform::LiteralExpr)
      expect(expr.value).to eq(dv.of_null)
    end

    it "parses string with escaped characters" do
      expr, = parser.parse_expression_string('"hello\\nworld"')
      expect(expr).to be_a(Odin::Transform::LiteralExpr)
      expect(expr.value.value).to eq("hello\nworld")
    end
  end

  # ── Expression Parsing: Copy ──

  describe "copy expression parsing" do
    it "parses simple copy @.name" do
      expr, = parser.parse_expression_string("@.name")
      expect(expr).to be_a(Odin::Transform::CopyExpr)
      expect(expr.source_path).to eq(".name")
    end

    it "parses nested copy @.address.city" do
      expr, = parser.parse_expression_string("@.address.city")
      expect(expr).to be_a(Odin::Transform::CopyExpr)
      expect(expr.source_path).to eq(".address.city")
    end

    it "parses array index copy @.items[0]" do
      expr, = parser.parse_expression_string("@.items[0]")
      expect(expr).to be_a(Odin::Transform::CopyExpr)
      expect(expr.source_path).to eq(".items[0]")
    end

    it "parses nested array copy @.items[0].name" do
      expr, = parser.parse_expression_string("@.items[0].name")
      expect(expr).to be_a(Odin::Transform::CopyExpr)
      expect(expr.source_path).to eq(".items[0].name")
    end

    it "parses bare @ (source root)" do
      expr, = parser.parse_expression_string("@")
      expect(expr).to be_a(Odin::Transform::CopyExpr)
      expect(expr.source_path).to eq("")
    end

    it "rejects @# as P001" do
      expect {
        parser.parse_expression_string("@#")
      }.to raise_error(Odin::Transform::TransformParser::ParseError) { |e|
        expect(e.code).to eq("P001")
      }
    end

    it "parses deep path @.a.b.c.d" do
      expr, = parser.parse_expression_string("@.a.b.c.d")
      expect(expr).to be_a(Odin::Transform::CopyExpr)
      expect(expr.source_path).to eq(".a.b.c.d")
    end
  end

  # ── Expression Parsing: Simple Verbs ──

  describe "simple verb expression parsing" do
    it "parses arity-0 verb %today" do
      expr, = parser.parse_expression_string("%today")
      expect(expr).to be_a(Odin::Transform::VerbExpr)
      expect(expr.verb_name).to eq("today")
      expect(expr.arguments).to be_empty
    end

    it "parses arity-0 verb %now" do
      expr, = parser.parse_expression_string("%now")
      expect(expr).to be_a(Odin::Transform::VerbExpr)
      expect(expr.verb_name).to eq("now")
      expect(expr.arguments).to be_empty
    end

    it "parses arity-1 verb %upper @.name" do
      expr, = parser.parse_expression_string("%upper @.name")
      expect(expr).to be_a(Odin::Transform::VerbExpr)
      expect(expr.verb_name).to eq("upper")
      expect(expr.arguments.length).to eq(1)
      expect(expr.arguments[0]).to be_a(Odin::Transform::CopyExpr)
      expect(expr.arguments[0].source_path).to eq(".name")
    end

    it "parses arity-1 verb %lower @.city" do
      expr, = parser.parse_expression_string("%lower @.city")
      expect(expr).to be_a(Odin::Transform::VerbExpr)
      expect(expr.verb_name).to eq("lower")
      expect(expr.arguments.length).to eq(1)
    end

    it "parses arity-1 verb with literal %abs ##-5" do
      expr, = parser.parse_expression_string("%abs ##-5")
      expect(expr).to be_a(Odin::Transform::VerbExpr)
      expect(expr.verb_name).to eq("abs")
      expect(expr.arguments[0]).to be_a(Odin::Transform::LiteralExpr)
      expect(expr.arguments[0].value).to eq(dv.of_integer(-5))
    end

    it "parses arity-2 verb %add @.a @.b" do
      expr, = parser.parse_expression_string("%add @.a @.b")
      expect(expr).to be_a(Odin::Transform::VerbExpr)
      expect(expr.verb_name).to eq("add")
      expect(expr.arguments.length).to eq(2)
    end

    it "parses arity-2 verb %eq @.status \"active\"" do
      expr, = parser.parse_expression_string('%eq @.status "active"')
      expect(expr).to be_a(Odin::Transform::VerbExpr)
      expect(expr.verb_name).to eq("eq")
      expect(expr.arguments.length).to eq(2)
      expect(expr.arguments[0]).to be_a(Odin::Transform::CopyExpr)
      expect(expr.arguments[1]).to be_a(Odin::Transform::LiteralExpr)
      expect(expr.arguments[1].value).to eq(dv.of_string("active"))
    end

    it "parses arity-3 verb %ifElse with literals" do
      expr, = parser.parse_expression_string('%ifElse ?true "yes" "no"')
      expect(expr).to be_a(Odin::Transform::VerbExpr)
      expect(expr.verb_name).to eq("ifElse")
      expect(expr.arguments.length).to eq(3)
    end

    it "parses arity-3 verb %substring" do
      expr, = parser.parse_expression_string("%substring @.text ##0 ##5")
      expect(expr).to be_a(Odin::Transform::VerbExpr)
      expect(expr.verb_name).to eq("substring")
      expect(expr.arguments.length).to eq(3)
    end

    it "parses arity-4 verb %filter" do
      expr, = parser.parse_expression_string('%filter @.items "status" "eq" "active"')
      expect(expr).to be_a(Odin::Transform::VerbExpr)
      expect(expr.verb_name).to eq("filter")
      expect(expr.arguments.length).to eq(4)
    end

    it "parses arity-5 verb %distance" do
      expr, = parser.parse_expression_string("%distance #40.0 #-74.0 #34.0 #-118.0 \"km\"")
      expect(expr).to be_a(Odin::Transform::VerbExpr)
      expect(expr.verb_name).to eq("distance")
      expect(expr.arguments.length).to eq(5)
    end

    it "parses arity-6 verb %inBoundingBox" do
      expr, = parser.parse_expression_string("%inBoundingBox #40.0 #-74.0 #40.0 #-74.0 #41.0 #-73.0")
      expect(expr).to be_a(Odin::Transform::VerbExpr)
      expect(expr.verb_name).to eq("inBoundingBox")
      expect(expr.arguments.length).to eq(6)
    end
  end

  # ── Nested Verb Expressions ──

  describe "nested verb expression parsing" do
    it "parses nested: %concat %upper @.first \" \" %lower @.last" do
      expr, = parser.parse_expression_string('%concat %upper @.first " " %lower @.last')
      expect(expr).to be_a(Odin::Transform::VerbExpr)
      expect(expr.verb_name).to eq("concat")
      expect(expr.arguments.length).to eq(3)
      expect(expr.arguments[0]).to be_a(Odin::Transform::VerbExpr)
      expect(expr.arguments[0].verb_name).to eq("upper")
      expect(expr.arguments[1]).to be_a(Odin::Transform::LiteralExpr)
      expect(expr.arguments[2]).to be_a(Odin::Transform::VerbExpr)
      expect(expr.arguments[2].verb_name).to eq("lower")
    end

    it "parses deeply nested: %ifElse %eq @.type \"A\" %upper @.name %lower @.name" do
      expr, = parser.parse_expression_string('%ifElse %eq @.type "A" %upper @.name %lower @.name')
      expect(expr).to be_a(Odin::Transform::VerbExpr)
      expect(expr.verb_name).to eq("ifElse")
      expect(expr.arguments.length).to eq(3)

      # First arg: %eq @.type "A"
      eq_expr = expr.arguments[0]
      expect(eq_expr).to be_a(Odin::Transform::VerbExpr)
      expect(eq_expr.verb_name).to eq("eq")
      expect(eq_expr.arguments.length).to eq(2)

      # Second arg: %upper @.name
      upper_expr = expr.arguments[1]
      expect(upper_expr).to be_a(Odin::Transform::VerbExpr)
      expect(upper_expr.verb_name).to eq("upper")

      # Third arg: %lower @.name
      lower_expr = expr.arguments[2]
      expect(lower_expr).to be_a(Odin::Transform::VerbExpr)
      expect(lower_expr.verb_name).to eq("lower")
    end

    it "parses complex: %ifElse %eq @.a @.b %accumulate passed ##1 %accumulate failed ##1" do
      raw = '%ifElse %eq @.a @.b %accumulate "passed" ##1 %accumulate "failed" ##1'
      expr, = parser.parse_expression_string(raw)
      expect(expr).to be_a(Odin::Transform::VerbExpr)
      expect(expr.verb_name).to eq("ifElse")
      expect(expr.arguments.length).to eq(3)

      # Condition: %eq @.a @.b
      cond = expr.arguments[0]
      expect(cond.verb_name).to eq("eq")

      # Then: %accumulate "passed" ##1
      then_expr = expr.arguments[1]
      expect(then_expr.verb_name).to eq("accumulate")
      expect(then_expr.arguments.length).to eq(2)

      # Else: %accumulate "failed" ##1
      else_expr = expr.arguments[2]
      expect(else_expr.verb_name).to eq("accumulate")
      expect(else_expr.arguments.length).to eq(2)
    end

    it "parses three levels deep" do
      raw = '%ifElse %gt %add @.a @.b ##10 "big" "small"'
      expr, = parser.parse_expression_string(raw)
      expect(expr.verb_name).to eq("ifElse")

      # Condition: %gt %add @.a @.b ##10
      gt_expr = expr.arguments[0]
      expect(gt_expr.verb_name).to eq("gt")
      expect(gt_expr.arguments[0].verb_name).to eq("add")
    end
  end

  # ── Variadic Verbs ──

  describe "variadic verb parsing" do
    it "parses variadic concat with multiple args" do
      expr, = parser.parse_expression_string('%concat @.a " " @.b " " @.c')
      expect(expr).to be_a(Odin::Transform::VerbExpr)
      expect(expr.verb_name).to eq("concat")
      expect(expr.arguments.length).to eq(5)
    end

    it "parses variadic coalesce" do
      expr, = parser.parse_expression_string("%coalesce @.primary @.secondary @.default")
      expect(expr).to be_a(Odin::Transform::VerbExpr)
      expect(expr.verb_name).to eq("coalesce")
      expect(expr.arguments.length).to eq(3)
    end

    it "parses variadic minOf" do
      expr, = parser.parse_expression_string("%minOf @.a @.b @.c @.d")
      expect(expr).to be_a(Odin::Transform::VerbExpr)
      expect(expr.verb_name).to eq("minOf")
      expect(expr.arguments.length).to eq(4)
    end

    it "parses variadic maxOf" do
      expr, = parser.parse_expression_string("%maxOf ##1 ##5 ##3")
      expect(expr).to be_a(Odin::Transform::VerbExpr)
      expect(expr.verb_name).to eq("maxOf")
      expect(expr.arguments.length).to eq(3)
    end
  end

  # ── Custom Verbs ──

  describe "custom verb parsing" do
    it "parses custom verb %&myVerb" do
      expr, = parser.parse_expression_string("%&myVerb @.name")
      expect(expr).to be_a(Odin::Transform::VerbExpr)
      expect(expr.verb_name).to eq("myVerb")
      expect(expr.custom).to be true
    end

    it "parses custom verb with namespace %&ns.verb" do
      expr, = parser.parse_expression_string("%&ns.verb @.x @.y")
      expect(expr).to be_a(Odin::Transform::VerbExpr)
      expect(expr.verb_name).to eq("ns.verb")
      expect(expr.custom).to be true
    end
  end

  # ── Directive Parsing ──

  describe "directive parsing" do
    it "parses :required modifier" do
      text = make_transform("{Customer}\nName = @.name :required")
      result = parser.parse(text)
      seg = result.segments.find { |s| s.name == "Customer" }
      mapping = seg.field_mappings.find { |m| m.target_field == "Name" }
      expect(mapping.modifiers).to include(Odin::Transform::FieldModifier::REQUIRED)
    end

    it "parses :confidential modifier" do
      text = make_transform("{Customer}\nSSN = @.ssn :confidential")
      result = parser.parse(text)
      seg = result.segments.find { |s| s.name == "Customer" }
      mapping = seg.field_mappings.find { |m| m.target_field == "SSN" }
      expect(mapping.modifiers).to include(Odin::Transform::FieldModifier::CONFIDENTIAL)
    end

    it "parses :deprecated modifier" do
      text = make_transform("{Customer}\nOldField = @.old :deprecated")
      result = parser.parse(text)
      seg = result.segments.find { |s| s.name == "Customer" }
      mapping = seg.field_mappings.find { |m| m.target_field == "OldField" }
      expect(mapping.modifiers).to include(Odin::Transform::FieldModifier::DEPRECATED)
    end

    it "parses extraction directive :pos" do
      expr, _ = parser.parse_expression_string("@.raw :pos 0")
      expect(expr).to be_a(Odin::Transform::CopyExpr)
      pos_dir = expr.directives.find { |d| d.name == "pos" }
      expect(pos_dir).not_to be_nil
      expect(pos_dir.value).to eq(0)
    end

    it "parses extraction directive :len" do
      expr, _ = parser.parse_expression_string("@.raw :len 10")
      expect(expr).to be_a(Odin::Transform::CopyExpr)
      len_dir = expr.directives.find { |d| d.name == "len" }
      expect(len_dir).not_to be_nil
      expect(len_dir.value).to eq(10)
    end

    it "parses :field directive" do
      expr, _ = parser.parse_expression_string('@.raw :field "Column Name"')
      expect(expr).to be_a(Odin::Transform::CopyExpr)
      field_dir = expr.directives.find { |d| d.name == "field" }
      expect(field_dir).not_to be_nil
      expect(field_dir.value).to eq("Column Name")
    end

    it "parses :trim directive" do
      expr, _ = parser.parse_expression_string("@.raw :trim")
      expect(expr).to be_a(Odin::Transform::CopyExpr)
      trim_dir = expr.directives.find { |d| d.name == "trim" }
      expect(trim_dir).not_to be_nil
    end

    it "parses :type directive" do
      _, directives = parser.parse_expression_string("@.val :type integer")
      type_dir = directives.find { |d| d.name == "type" }
      expect(type_dir).not_to be_nil
      expect(type_dir.value).to eq("integer")
    end

    it "parses :date directive" do
      _, directives = parser.parse_expression_string('@.date :date "yyyy-MM-dd"')
      date_dir = directives.find { |d| d.name == "date" }
      expect(date_dir).not_to be_nil
      expect(date_dir.value).to eq("yyyy-MM-dd")
    end

    it "parses :time directive" do
      _, directives = parser.parse_expression_string('@.time :time "HH:mm"')
      time_dir = directives.find { |d| d.name == "time" }
      expect(time_dir).not_to be_nil
      expect(time_dir.value).to eq("HH:mm")
    end

    it "parses multiple directives" do
      expr, _ = parser.parse_expression_string("@.raw :pos 0 :len 10 :trim")
      expect(expr).to be_a(Odin::Transform::CopyExpr)
      expect(expr.directives.length).to eq(3)
      expect(expr.directives.map(&:name)).to include("pos", "len", "trim")
    end
  end

  # ── Segment Parsing ──

  describe "segment parsing" do
    it "parses segment with simple mappings" do
      text = make_transform("{Customer}\nName = @.name\nAge = @.age")
      result = parser.parse(text)
      seg = result.segments.find { |s| s.name == "Customer" }
      expect(seg).not_to be_nil
      expect(seg.field_mappings.length).to eq(2)
    end

    it "parses segment with _discriminator" do
      text = make_transform("{Auto}\n_discriminator = @.type\n_discriminatorValue = \"auto\"\nMake = @.make")
      result = parser.parse(text)
      seg = result.segments.find { |s| s.name == "Auto" }
      expect(seg.discriminator).not_to be_nil
    end

    it "parses segment with _each" do
      text = make_transform("{Items[]}\n_each = @.items\nName = @.name")
      result = parser.parse(text)
      seg = result.segments.find { |s| s.name == "Items" }
      expect(seg).not_to be_nil
      expect(seg.each_source).to eq("@.items")
      expect(seg.is_array).to be true
    end

    it "parses segment with _loop" do
      text = make_transform("{Orders[]}\n_loop = @.orders\nId = @.id")
      result = parser.parse(text)
      seg = result.segments.find { |s| s.name == "Orders" }
      expect(seg.each_source).to eq("@.orders")
    end

    it "parses segment with _when" do
      text = make_transform("{Active}\n_when = @.status = \"active\"\nName = @.name")
      result = parser.parse(text)
      seg = result.segments.find { |s| s.name == "Active" }
      expect(seg.when_condition).not_to be_nil
    end

    it "parses segment with _if" do
      text = make_transform("{Details}\n_if = @.hasDetails\nInfo = @.info")
      result = parser.parse(text)
      seg = result.segments.find { |s| s.name == "Details" }
      expect(seg.if_condition).not_to be_nil
    end

    it "parses segment with array index {Items[0]}" do
      text = make_transform("{Items[0]}\nName = @.items[0].name")
      result = parser.parse(text)
      seg = result.segments.find { |s| s.name == "Items" }
      expect(seg).not_to be_nil
      expect(seg.array_index).to eq(0)
    end

    it "parses segment with array notation {Items[]}" do
      text = make_transform("{Items[]}\n_each = @.items\nName = @.name")
      result = parser.parse(text)
      seg = result.segments.find { |s| s.name == "Items" }
      expect(seg.is_array).to be true
    end

    it "parses segment with _pass" do
      text = make_transform("{Summary}\n_pass = ##2\nTotal = @.total")
      result = parser.parse(text)
      seg = result.segments.find { |s| s.name == "Summary" }
      expect(seg.pass).to eq(2)
    end

    it "extracts passes from segments" do
      text = make_transform("{First}\n_pass = ##1\nA = @.a\n\n{Second}\n_pass = ##2\nB = @.b")
      result = parser.parse(text)
      expect(result.passes).to eq([1, 2])
    end
  end

  # ── Constants Parsing ──

  describe "constants parsing" do
    it "parses Constants section" do
      text = make_transform("{Constants}\ngreeting = \"hello\"\ncount = ##5")
      result = parser.parse(text)
      expect(result.constants["greeting"]).to eq(dv.of_string("hello"))
      expect(result.constants["count"]).to eq(dv.of_integer(5))
    end
  end

  # ── Tables Parsing ──

  describe "tables parsing" do
    it "parses lookup table from header" do
      header = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"
        table.rates[0].code = "USD"
        table.rates[0].value = #1.0
        table.rates[1].code = "EUR"
        table.rates[1].value = #0.85
      ODIN
      result = parser.parse(header)
      rates = result.tables["rates"]
      expect(rates).not_to be_nil
      expect(rates.rows.length).to eq(2)
      expect(rates.rows[0]["code"]).to eq(dv.of_string("USD"))
    end
  end

  # ── Verb Arity Table Completeness ──

  describe "verb arity table" do
    it "contains today as arity 0" do
      expect(Odin::Transform::TransformParser::VERB_ARITY["today"]).to eq(0)
    end

    it "contains now as arity 0" do
      expect(Odin::Transform::TransformParser::VERB_ARITY["now"]).to eq(0)
    end

    it "contains upper as arity 1" do
      expect(Odin::Transform::TransformParser::VERB_ARITY["upper"]).to eq(1)
    end

    it "contains add as arity 2" do
      expect(Odin::Transform::TransformParser::VERB_ARITY["add"]).to eq(2)
    end

    it "contains ifElse as arity 3" do
      expect(Odin::Transform::TransformParser::VERB_ARITY["ifElse"]).to eq(3)
    end

    it "contains rate as arity 4" do
      expect(Odin::Transform::TransformParser::VERB_ARITY["rate"]).to eq(4)
    end

    it "contains distance as arity 5" do
      expect(Odin::Transform::TransformParser::VERB_ARITY["distance"]).to eq(5)
    end

    it "contains inBoundingBox as arity 6" do
      expect(Odin::Transform::TransformParser::VERB_ARITY["inBoundingBox"]).to eq(6)
    end

    it "concat is variadic (not in arity table)" do
      expect(Odin::Transform::TransformParser::VERB_ARITY["concat"]).to be_nil
      expect(Odin::Transform::TransformParser::VARIADIC_VERBS).to include("concat")
    end

    it "coalesce is variadic" do
      expect(Odin::Transform::TransformParser::VERB_ARITY["coalesce"]).to be_nil
      expect(Odin::Transform::TransformParser::VARIADIC_VERBS).to include("coalesce")
    end

    it "has at least 140 verb entries" do
      total = Odin::Transform::TransformParser::VERB_ARITY.size + Odin::Transform::TransformParser::VARIADIC_VERBS.size
      expect(total).to be >= 140
    end

    # Spot-check various arity levels
    %w[trim isNull length abs floor ceil negate sum count keys values flatten sort distinct].each do |verb|
      it "#{verb} is arity 1" do
        expect(Odin::Transform::TransformParser::VERB_ARITY[verb]).to eq(1)
      end
    end

    %w[eq ne lt gt contains startsWith multiply divide accumulate set].each do |verb|
      it "#{verb} is arity 2" do
        expect(Odin::Transform::TransformParser::VERB_ARITY[verb]).to eq(2)
      end
    end

    %w[substring replace clamp safeDivide slice get].each do |verb|
      it "#{verb} is arity 3" do
        expect(Odin::Transform::TransformParser::VERB_ARITY[verb]).to eq(3)
      end
    end

    %w[filter every some find].each do |verb|
      it "#{verb} is arity 4" do
        expect(Odin::Transform::TransformParser::VERB_ARITY[verb]).to eq(4)
      end
    end
  end

  # ── Full Transform Parse End-to-End ──

  describe "full transform parsing" do
    it "parses a complete json->json transform" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Customer}
        Name = @.name
        City = @.address.city
        Upper = %upper @.name
      ODIN

      result = parser.parse(text)
      expect(result.direction).to eq("json->json")
      expect(result.segments.length).to eq(1)

      seg = result.segments[0]
      expect(seg.name).to eq("Customer")
      expect(seg.field_mappings.length).to eq(3)

      name_mapping = seg.field_mappings.find { |m| m.target_field == "Name" }
      expect(name_mapping.expression).to be_a(Odin::Transform::CopyExpr)

      upper_mapping = seg.field_mappings.find { |m| m.target_field == "Upper" }
      expect(upper_mapping.expression).to be_a(Odin::Transform::VerbExpr)
      expect(upper_mapping.expression.verb_name).to eq("upper")
    end

    it "parses transform with multiple segments" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Person}
        Name = @.name

        {Address}
        City = @.address.city
      ODIN

      result = parser.parse(text)
      expect(result.segments.length).to eq(2)
    end

    it "parses transform with literal values" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Record}
        Status = "active"
        Count = ##0
        Rate = #1.5
        Active = ?true
      ODIN

      result = parser.parse(text)
      seg = result.segments[0]
      expect(seg.field_mappings.length).to eq(4)
    end
  end
end
