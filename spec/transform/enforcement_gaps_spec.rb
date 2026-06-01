# frozen_string_literal: true

require_relative "../spec_helper"

# Transform engine enforcement gaps: stable error codes (T001, T003, T005,
# T006, T008, T009), onMissing policy for source fields, and @import resolution.
RSpec.describe "Transform enforcement gaps" do
  let(:parser) { Odin::Transform::TransformParser.new }
  let(:engine) { Odin::Transform::TransformEngine.new }

  # Build a transform header. `format` drives both the direction target and the
  # declared target.format; `target` adds {$target} options; `meta` adds {$} fields.
  def header(format: "odin", target: {}, meta: {})
    m = [
      'odin = "1.0.0"',
      'transform = "1.0.0"',
      %(direction = "odin->#{format}")
    ]
    meta.each { |k, v| m << "#{k} = #{v}" }
    t = [%(format = "#{format}")]
    target.each { |k, v| t << %(#{k} = "#{v}") }
    "{$}\n#{m.join("\n")}\n\n{$source}\nformat = \"odin\"\n\n{$target}\n#{t.join("\n")}\n\n"
  end

  def run(transform, input, format: "odin", target: {}, import_resolver: nil)
    text = header(format: format, target: target) + transform
    td = parser.parse(text)
    source = Odin::Types::DynValue.of_string(input)
    engine.execute(td, source, import_resolver: import_resolver)
  end

  # ── T001 — unknown verb ──

  describe "T001 — unknown verb" do
    it "emits T001 for an unknown built-in verb" do
      r = run("{out}\nx = %notAVerb @.a", "a = ##1")
      expect(r.success?).to be(false)
      expect(r.errors.first&.code).to eq("T001")
      expect(r.errors.first&.field).to eq("x")
    end

    it "does not raise for an unregistered custom %& verb (extension point)" do
      r = run("{out}\nx = %&my.thing @.a", 'a = "v"')
      expect(r.success?).to be(true)
      expect(r.errors).to be_empty
    end

    it "demotes T001 to a warning under onError = warn" do
      r = run("{out}\nx = %notAVerb @.a", "a = ##1", target: { "onError" => "warn" })
      expect(r.success?).to be(true)
      expect(r.warnings.any? { |w| w.respond_to?(:code) && w.code == "T001" }).to be(true)
    end
  end

  # ── T003 — lookup table not found ──

  describe "T003 — lookup table not found" do
    it "emits T003 (not T004) when the table is undeclared and onMissing = fail" do
      r = run(%({out}\nx = %lookup "GHOST.code" @.k), 'k = "active"', target: { "onMissing" => "fail" })
      expect(r.success?).to be(false)
      expect(r.errors.first&.code).to eq("T003")
    end

    it "stays silent for an undeclared table under the default policy" do
      r = run(%({out}\nx = %lookup "GHOST.code" @.k), 'k = "active"')
      expect(r.success?).to be(true)
      expect(r.errors).to be_empty
    end

    it "demotes T003 to a warning under onMissing = warn" do
      r = run(%({out}\nx = %lookup "GHOST.code" @.k), 'k = "active"', target: { "onMissing" => "warn" })
      expect(r.success?).to be(true)
      expect(r.warnings.any? { |w| w.respond_to?(:code) && w.code == "T003" }).to be(true)
    end

    it "still emits T004 for a missing key in a declared table" do
      transform = "{$table.T[name, code]}\n\"foo\", ##1\n\n{out}\nx = %lookup \"T.code\" @.k"
      r = run(transform, 'k = "bar"', target: { "onMissing" => "fail" })
      expect(r.success?).to be(false)
      expect(r.errors.first&.code).to eq("T004")
    end
  end

  # ── T005 — source path not found / onMissing ──

  describe "T005 — source path not found / onMissing" do
    it "emits T005 when a :required source path is absent" do
      r = run("{out}\nx = @.does.not.exist :required", "a = ##1")
      expect(r.success?).to be(false)
      expect(r.errors.first&.code).to eq("T005")
    end

    it "emits T005 for an absent path under onMissing = fail without :required" do
      r = run("{out}\nx = @.does.not.exist", "a = ##1", target: { "onMissing" => "fail" })
      expect(r.success?).to be(false)
      expect(r.errors.first&.code).to eq("T005")
    end

    it "warns for an absent path under onMissing = warn" do
      r = run("{out}\nx = @.does.not.exist", "a = ##1", target: { "onMissing" => "warn" })
      expect(r.success?).to be(true)
      expect(r.warnings.any? { |w| w.respond_to?(:code) && w.code == "T005" }).to be(true)
    end

    it "stays silent for an absent path under the default (skip) policy" do
      r = run("{out}\nx = @.does.not.exist", "a = ##1")
      expect(r.success?).to be(true)
      expect(r.errors).to be_empty
    end

    it "treats a present-but-null required field as SOURCE_MISSING, not T005" do
      r = run("{out}\nx = @.a :required", "a = ~")
      expect(r.success?).to be(false)
      expect(r.errors.first&.code).to eq("SOURCE_MISSING")
    end

    it "does not raise T005 when a verb result is null" do
      r = run("{out}\nx = %upper @.missing", "a = ##1", target: { "onMissing" => "fail" })
      expect(r.errors.any? { |e| e.code == "T005" }).to be(false)
    end
  end

  # ── T006 — invalid output format ──

  describe "T006 — invalid output format" do
    it "emits T006 for an unregistered target format" do
      r = run("{out}\nx = @.a", "a = ##1", format: "notaformat")
      expect(r.success?).to be(false)
      expect(r.errors.any? { |e| e.code == "T006" }).to be(true)
    end

    it "does not raise T006 for any known format" do
      %w[odin json xml csv fixed-width flat properties].each do |fmt|
        r = run("{out}\nx = @.a", "a = ##1", format: fmt)
        expect(r.errors.any? { |e| e.code == "T006" }).to be(false), "format #{fmt}"
      end
    end

    it "produces non-empty output for odin, json, and xml" do
      %w[odin json xml].each do |fmt|
        r = run("{out}\nx = @.a", "a = ##1", format: fmt)
        expect(r.formatted.length).to be > 0, "format #{fmt}"
      end
    end

    it "derives the format from the direction header when no target.format is declared" do
      text = "{$}\nodin = \"1.0.0\"\ntransform = \"1.0.0\"\ndirection = \"json->json\"\n\n{out}\nx = @.a"
      td = parser.parse(text)
      r = engine.execute(td, Odin::Types::DynValue.from_ruby({ "a" => 1 }))
      expect(r.errors.any? { |e| e.code == "T006" }).to be(false)
      expect(r.formatted.length).to be > 0
    end
  end

  # ── T009 — loop source not array ──

  describe "T009 — loop source not array" do
    it "emits T009 for a present non-array scalar" do
      r = run("{out[]}\n:loop notArr\nx = @.a", 'notArr = "scalar"')
      expect(r.success?).to be(false)
      expect(r.errors.first&.code).to eq("T009")
    end

    it "yields zero rows with no error for an absent loop source" do
      r = run("{out[]}\n:loop missing\nx = @.a", "a = ##1")
      expect(r.success?).to be(true)
      expect(r.errors).to be_empty
      expect(r.output["out"]).to eq([])
    end

    it "yields zero rows with no error for an empty loop source" do
      r = run("{out[]}\n:loop items\nx = @.a", "items = []")
      expect(r.success?).to be(true)
      expect(r.errors).to be_empty
      expect(r.output["out"]).to eq([])
    end

    it "demotes T009 to a warning under onError = warn" do
      r = run("{out[]}\n:loop notArr\nx = @.a", 'notArr = "scalar"', target: { "onError" => "warn" })
      expect(r.success?).to be(true)
      expect(r.warnings.any? { |w| w.respond_to?(:code) && w.code == "T009" }).to be(true)
    end
  end

  # ── T008 — accumulator overflow ──

  describe "T008 — accumulator overflow" do
    it "emits T008 when an integer accumulator exceeds safe capacity" do
      transform = "{$accumulator}\ntotal = ##0\n\n{out}\nx = %accumulate \"total\" @.a"
      r = run(transform, "a = ##99999999999999999999")
      expect(r.success?).to be(false)
      expect(r.errors.first&.code).to eq("T008")
    end

    it "does not raise for ordinary accumulation" do
      transform = "{$accumulator}\ntotal = ##0\n\n{out}\nx = %accumulate \"total\" @.a"
      r = run(transform, "a = ##5")
      expect(r.success?).to be(true)
      expect(r.errors).to be_empty
    end

    it "retains the last valid value after overflow" do
      transform = "{$accumulator}\ntotal = ##0\n\n{step1}\na = %accumulate \"total\" @.small\n\n" \
                  "{step2}\nb = %accumulate \"total\" @.big\n\n{out}\nfinal = @$accumulator.total"
      r = run(transform, "small = ##10\nbig = ##99999999999999999999")
      expect(r.errors.first&.code).to eq("T008")
      expect(r.output["out"]["final"]).to eq(10)
    end
  end

  # ── @import resolution ──

  describe "@import resolution" do
    let(:tables_doc) do
      <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "odin->odin"

        {$source}
        format = "odin"

        {$target}
        format = "odin"

        {$table.STATES[code, name]}
        "CA", "California"
        "TX", "Texas"
      ODIN
    end

    let(:shared_doc) do
      <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "odin->odin"

        {$source}
        format = "odin"

        {$target}
        format = "odin"

        {shared}
        greeting = "hello"
      ODIN
    end

    let(:main) do
      <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "odin->odin"

        @import ./tables/states.odin
        @import ./mappings/shared.odin

        {$source}
        format = "odin"

        {$target}
        format = "odin"
        onMissing = "fail"

        {out}
        state = %lookup "STATES.name" @.code
      ODIN
    end

    let(:resolver) do
      lambda do |p|
        next tables_doc if p.include?("states")
        next shared_doc if p.include?("shared")

        nil
      end
    end

    def parse_run(transform_text, input, resolver: nil)
      td = parser.parse(transform_text)
      source = Odin::Types::DynValue.of_string(input)
      doc = Odin.parse(input)
      # reconstruct nested DynValue from ODIN document
      engine.execute(td, source, import_resolver: resolver)
    end

    it "makes an imported $table usable by %lookup" do
      r = parse_run(main, 'code = "CA"', resolver: resolver)
      expect(r.success?).to be(true)
      expect(r.errors).to be_empty
      expect(r.formatted).to include("California")
    end

    it "merges an imported mapping segment into the output" do
      r = parse_run(main, 'code = "TX"', resolver: resolver)
      expect(r.formatted).to include("greeting")
      expect(r.formatted).to include("hello")
    end

    it "leaves the imported table unresolved without a resolver (T003)" do
      r = parse_run(main, 'code = "CA"')
      expect(r.success?).to be(false)
      expect(r.errors.first&.code).to eq("T003")
    end

    it "local declarations take precedence over imported ones" do
      local_table = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "odin->odin"

        @import ./tables/states.odin

        {$source}
        format = "odin"

        {$target}
        format = "odin"

        {$table.STATES[code, name]}
        "CA", "Local-California"

        {out}
        state = %lookup "STATES.name" @.code
      ODIN
      r = parse_run(local_table, 'code = "CA"', resolver: resolver)
      expect(r.formatted).to include("Local-California")
    end

    it "ignores an import the resolver cannot satisfy" do
      t = <<~ODIN
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "odin->odin"

        @import ./missing/nowhere.odin

        {$source}
        format = "odin"

        {$target}
        format = "odin"

        {out}
        x = @.a
      ODIN
      r = parse_run(t, "a = ##1", resolver: resolver)
      expect(r.success?).to be(true)
    end
  end
end
