# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "golden_helper"

RSpec.describe "Golden: Transform Corpus" do
  CORPUS_DIR = File.join(find_golden_dir, "transform-corpus")

  # Standard odin->odin header, prepended to each fixture's transform. targetFormat
  # defaults to odin; targetOptions inject {$target} fields; headerFields inject
  # extra {$}-level fields (raw ODIN values).
  def self.build_header(target_format, target_options, header_fields)
    meta = ['odin = "1.0.0"', 'transform = "1.0.0"', %(direction = "odin->#{target_format}")]
    (header_fields || {}).each { |k, v| meta << "#{k} = #{v}" }
    target = [%(format = "#{target_format}")]
    (target_options || {}).each { |k, v| target << %(#{k} = "#{v}") }
    "{$}\n#{meta.join("\n")}\n\n{$source}\nformat = \"odin\"\n\n{$target}\n#{target.join("\n")}\n\n"
  end

  def self.header_for(fixture)
    build_header(fixture["targetFormat"] || "odin", fixture["targetOptions"], fixture["headerFields"])
  end

  def self.discover_fixtures
    out = []
    Dir.children(CORPUS_DIR).sort.each do |family|
      family_path = File.join(CORPUS_DIR, family)
      next unless File.directory?(family_path)

      Dir.children(family_path).sort.each do |name|
        next unless name.end_with?(".json")
        next if name == "manifest.json"

        file = File.join(family_path, name)
        fixture = JSON.parse(File.read(file, encoding: "UTF-8"))
        out << [fixture, file]
      end
    end
    out.sort_by { |_, file| file }
  end

  def normalize(text)
    (text || "").gsub("\r\n", "\n").sub(/\s+\z/, "")
  end

  def parse_source(odin_text)
    doc = Odin.parse(odin_text)
    odin_doc_to_dynvalue(doc)
  end

  # Build a DynValue source from an ODIN document.
  def odin_doc_to_dynvalue(doc)
    result = {}
    doc.each_assignment do |path, value|
      next if path.start_with?("$")

      dv = odin_value_to_dyn(value)
      set_nested(result, path, dv)
    end
    wrap_nested_to_dynvalue(result)
  end

  def wrap_nested_to_dynvalue(obj)
    case obj
    when Odin::Types::DynValue
      obj
    when Hash
      Odin::Types::DynValue.of_object(obj.transform_values { |v| wrap_nested_to_dynvalue(v) })
    when Array
      Odin::Types::DynValue.of_array(obj.map { |v| wrap_nested_to_dynvalue(v) })
    else
      Odin::Types::DynValue.from_ruby(obj)
    end
  end

  def odin_value_to_dyn(val)
    case val
    when Odin::Types::OdinNull then Odin::Types::DynValue.of_null
    when Odin::Types::OdinBoolean then Odin::Types::DynValue.of_bool(val.value)
    when Odin::Types::OdinString then Odin::Types::DynValue.of_string(val.value)
    when Odin::Types::OdinInteger then Odin::Types::DynValue.of_integer(val.value)
    when Odin::Types::OdinNumber then Odin::Types::DynValue.of_float(val.value)
    when Odin::Types::OdinCurrency
      Odin::Types::DynValue.of_currency(val.value.to_f, val.decimal_places || 2, val.currency_code)
    when Odin::Types::OdinDate then Odin::Types::DynValue.of_date(val.raw || val.value.to_s)
    when Odin::Types::OdinTimestamp then Odin::Types::DynValue.of_timestamp(val.raw || val.value.to_s)
    when Odin::Types::OdinTime then Odin::Types::DynValue.of_time(val.value)
    when Odin::Types::OdinDuration then Odin::Types::DynValue.of_duration(val.value)
    when Odin::Types::OdinReference then Odin::Types::DynValue.of_reference(val.path)
    when Odin::Types::OdinBinary then Odin::Types::DynValue.of_binary(val.data)
    when Odin::Types::OdinPercent then Odin::Types::DynValue.of_percent(val.value)
    when Odin::Types::OdinArray
      items = val.items.map do |item|
        item.is_a?(Odin::Types::ArrayItem) ? odin_value_to_dyn(item.value) : odin_value_to_dyn(item)
      end
      Odin::Types::DynValue.of_array(items)
    when Odin::Types::OdinObject
      Odin::Types::DynValue.of_object(val.entries.transform_values { |v| odin_value_to_dyn(v) })
    else
      Odin::Types::DynValue.of_null
    end
  end

  def set_nested(obj, path, value)
    segments = parse_path_segments(path)
    current = obj
    segments[0...-1].each_with_index do |seg, idx|
      next_seg = segments[idx + 1]
      if seg.is_a?(Integer)
        current[seg] ||= next_seg.is_a?(Integer) ? [] : {}
        current = current[seg]
      else
        current[seg] ||= next_seg.is_a?(Integer) ? [] : {}
        current = current[seg]
      end
    end
    current[segments.last] = value
  end

  def parse_path_segments(path)
    segments = []
    path.split(".").each do |part|
      if part.include?("[")
        part.scan(/([^\[\]]+)|\[(\d+)\]/) do |name, index|
          segments << (index ? index.to_i : name)
        end
      else
        segments << part
      end
    end
    segments
  end

  def run_fixture(fixture)
    transform_text = self.class.header_for(fixture) + fixture["transform"]
    source = parse_source(fixture["input"])

    parser = Odin::Transform::TransformParser.new
    engine = Odin::Transform::TransformEngine.new

    # Error fixtures: assert the declared T-code surfaces (thrown, or in
    # result.errors/warnings). enforced:false fixtures are documented gaps.
    if fixture["family"] == "error"
      return if fixture["enforced"] == false

      code = fixture["code"]
      surfaced = +""
      begin
        transform_def = parser.parse(transform_text)
        result = engine.execute(transform_def, source)
        fmt = lambda do |xs|
          (xs || []).map { |e| "#{e.respond_to?(:code) ? e.code : nil} #{e.respond_to?(:message) ? e.message : e}" }.join("\n")
        end
        surfaced = "#{fmt.call(result.errors)}\n#{fmt.call(result.warnings)}"
      rescue StandardError => e
        c = e.respond_to?(:code) ? e.code : nil
        surfaced = "#{c} #{e.message}"
      end
      expect(surfaced).to include(code), "#{code} not surfaced"
      return
    end

    transform_def = parser.parse(transform_text)
    result = engine.execute(transform_def, source)
    expect(result.errors || []).to be_empty, "errors: #{(result.errors || []).map(&:message).join('; ')}"

    actual = normalize(result.formatted)
    expected = normalize(fixture["expectedOutput"])
    expect(actual).to eq(expected),
      "Formatted mismatch:\n  EXPECTED:\n#{expected}\n  ACTUAL:\n#{actual}"
  end

  discover_fixtures.each do |fixture, _file|
    next if fixture["tsOnly"] == true

    it "#{fixture['family']}/#{fixture['id']}" do
      run_fixture(fixture)
    end
  end
end
