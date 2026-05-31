# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "Transform conformance (Wave 3)" do
  let(:engine) { Odin::Transform::TransformEngine.new }
  let(:parser) { Odin::Transform::TransformParser.new }

  def run(transform_text, source)
    transform_def = parser.parse(transform_text)
    engine.execute(transform_def, source)
  end

  # ── Bare segment-directive lines ──

  describe "bare segment-directive lines" do
    it "treats a bare :loop line like a loop source" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {rows[]}
        :loop items
        sku = "@.sku"
      ODIN
      result = run(text, { "items" => [{ "sku" => "A" }, { "sku" => "B" }] })
      expect(result.output["rows"]).to eq([{ "sku" => "A" }, { "sku" => "B" }])
    end

    it "exposes a bare :counter by name and through the accumulator reference" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {rows[]}
        :loop items
        :counter rownum
        sku = "@.sku"
        n = "@rownum"
        m = "@$accumulator.rownum"
      ODIN
      result = run(text, { "items" => [{ "sku" => "A" }, { "sku" => "B" }, { "sku" => "C" }] })
      expect(result.output["rows"]).to eq([
        { "sku" => "A", "n" => 0, "m" => 0 },
        { "sku" => "B", "n" => 1, "m" => 1 },
        { "sku" => "C", "n" => 2, "m" => 2 }
      ])
    end
  end

  # ── Header-inline :loop / :counter / :from ──

  describe "header-inline loop directives" do
    it "runs a header-inline :loop" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {rows[] :loop items}
        sku = "@.sku"
      ODIN
      result = run(text, { "items" => [{ "sku" => "X" }, { "sku" => "Y" }] })
      expect(result.output["rows"]).to eq([{ "sku" => "X" }, { "sku" => "Y" }])
    end

    it "runs a header-inline :from with :counter" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {rows[] :from items :counter i}
        n = "@i"
      ODIN
      result = run(text, { "items" => [{}, {}] })
      expect(result.output["rows"]).to eq([{ "n" => 0 }, { "n" => 1 }])
    end
  end

  # ── Validation modifiers ──

  describe "validation modifiers" do
    let(:transform) do
      <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"
        target.onValidation = "POLICY"

        {Record}
        status = "@.status :enum A,P,C"
        year = "@.year :range 1900..2100"
      ODIN
    end

    it "emits but warns when onValidation = warn" do
      text = transform.sub("POLICY", "warn")
      result = run(text, { "status" => "Z", "year" => 1850 })
      expect(result.output["Record"]["status"]).to eq("Z")
      expect(result.output["Record"]["year"]).to eq(1850)
    end

    it "drops invalid fields when onValidation = skip" do
      text = transform.sub("POLICY", "skip")
      result = run(text, { "status" => "Z", "year" => 1850 })
      expect(result.output["Record"]).to be_nil
    end

    it "records a T013 error when onValidation = fail" do
      text = transform.sub("POLICY", "fail")
      result = run(text, { "status" => "Z", "year" => 1850 })
      expect(result.errors.map(&:code)).to include("T013")
    end

    it "passes valid values" do
      text = transform.sub("POLICY", "fail")
      result = run(text, { "status" => "A", "year" => 2000 })
      expect(result.output["Record"]).to eq({ "status" => "A", "year" => 2000 })
      expect(result.errors).to be_empty
    end

    it "validates against a :validate pattern" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"
        target.onValidation = "skip"

        {Record}
        email = "@.email :validate \\"^[^@]+@[^@]+$\\""
      ODIN
      ok = run(text, { "email" => "a@b" })
      bad = run(text, { "email" => "nope" })
      expect(ok.output["Record"]["email"]).to eq("a@b")
      expect(bad.output["Record"]).to be_nil
    end
  end

  # ── :object / :raw / :array ──

  describe "structural modifiers" do
    it "builds a nested object with :object" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Quote}
        contact = ":object {name = @.name, phone = @.phone}"
      ODIN
      result = run(text, { "name" => "John", "phone" => "555" })
      expect(result.output["Quote"]["contact"]).to eq({ "name" => "John", "phone" => "555" })
    end

    it "emits inline JSON structurally with :raw" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Document}
        metadata = "@.json :raw"
      ODIN
      result = run(text, { "json" => '{"version":2,"tags":["a","b"]}' })
      expect(result.output["Document"]["metadata"]).to eq({ "version" => 2, "tags" => %w[a b] })
    end

    it "wraps a value in a single-element array with :array" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Policy}
        codes = "@.code :array"
      ODIN
      result = run(text, { "code" => "COLL" })
      expect(result.output["Policy"]["codes"]).to eq(["COLL"])
    end
  end

  # ── Field :if comparison ──

  describe "field :if comparison" do
    let(:transform) do
      <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Quote}
        discount = "@.discount :if @.tier = gold"
        surcharge = "@.surcharge :if @.tier = bronze"
      ODIN
    end

    it "emits only the field whose comparison holds" do
      result = run(transform, { "tier" => "gold", "discount" => 15, "surcharge" => 40 })
      expect(result.output["Quote"]).to eq({ "discount" => 15 })
    end

    it "supports :unless" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {Quote}
        discount = "@.discount :unless @.tier = bronze"
      ODIN
      result = run(text, { "tier" => "gold", "discount" => 15 })
      expect(result.output["Quote"]).to eq({ "discount" => 15 })
    end
  end

  # ── Computation-only sink sections ──

  describe "sink sections" do
    it "omits a _-prefixed looping computation section from output" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->json"

        {$accumulator}
        total = ##0

        {_sumItems[]}
        :loop items
        _ = "%accumulate total @.amount"

        {Summary}
        total = "@$accumulator.total"
      ODIN
      result = run(text, { "items" => [{ "amount" => 10 }, { "amount" => 20 }, { "amount" => 30 }] })
      expect(result.output).to eq({ "Summary" => { "total" => 60 } })
    end
  end

  # ── XML :cdata ──

  describe "xml :cdata" do
    it "wraps element text in a CDATA section" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->xml"
        target.format = "xml"
        emitTypeHints = ?false

        {Policy}
        Description = "@.description :cdata"
      ODIN
      result = run(text, { "description" => "a < 500 & b > 0" })
      expect(result.formatted).to include("<Description><![CDATA[a < 500 & b > 0]]></Description>")
    end
  end

  # ── Fixed-width lineWidth ──

  describe "fixed-width lineWidth" do
    it "pads each record to the configured width with padChar" do
      text = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->fixed-width"
        target.format = "fixed-width"

        {$target}
        lineWidth = ##20
        padChar = "."

        {record}
        code = @.code :pos 0 :len 5 :rightPad " "
        name = @.name :pos 5 :len 8 :rightPad " "
      ODIN
      result = run(text, { "code" => "AB", "name" => "WIDGET" })
      expect(result.formatted).to eq("AB   WIDGET  .......")
    end
  end
end
