# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "golden_helper"

RSpec.describe "Golden End-to-End Tests" do
  E2E_GOLDEN_DIR = find_golden_dir

  # No known gaps — all golden tests must pass

  def self.discover_e2e_tests
    tests = []
    e2e_dir = File.join(E2E_GOLDEN_DIR, "end-to-end")
    manifest_file = File.join(e2e_dir, "manifest.json")
    return tests unless File.exist?(manifest_file)

    manifest = JSON.parse(File.read(manifest_file))
    manifest["categories"].each do |category|
      cat_id = category["id"]
      cat_path = category["path"]
      cat_dir = File.join(e2e_dir, cat_path)
      cat_manifest_path = File.join(cat_dir, "manifest.json")
      next unless File.exist?(cat_manifest_path)

      cat_data = JSON.parse(File.read(cat_manifest_path))
      (cat_data["tests"] || []).each do |test|
        test_id = test["id"]
        tests << [cat_id, test_id, test, cat_dir]
      end
    end
    tests
  end

  def normalize(text)
    text.gsub("\r\n", "\n")
        .gsub(/(\d)\.0e([+-]?\d)/, '\1e\2')  # 1.0e-18 → 1e-18 (normalize scientific notation)
        .strip
  end

  def source_format(direction)
    direction.to_s.split("->").first || "odin"
  end

  def parse_input(raw, fmt)
    case fmt
    when "json"
      Odin::Transform::SourceParsers.parse_json(raw)
    when "xml"
      Odin::Transform::SourceParsers.parse_xml(raw)
    when "csv", "delimited"
      Odin::Types::DynValue.of_string(raw)
    when "yaml"
      Odin::Transform::SourceParsers.parse_yaml(raw)
    when "flat", "properties", "flat-kvp"
      Odin::Transform::SourceParsers.parse_flat_kvp(raw)
    when "odin"
      doc = Odin.parse(raw)
      odin_doc_to_dynvalue(doc)
    when "fixed-width"
      Odin::Types::DynValue.of_string(raw)
    else
      Odin::Types::DynValue.of_string(raw)
    end
  end

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
      wrapped = obj.transform_values { |v| wrap_nested_to_dynvalue(v) }
      Odin::Types::DynValue.of_object(wrapped)
    when Array
      wrapped = obj.map { |v| wrap_nested_to_dynvalue(v) }
      Odin::Types::DynValue.of_array(wrapped)
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
    when Odin::Types::OdinCurrency then Odin::Types::DynValue.of_currency(val.value)
    when Odin::Types::OdinDate then Odin::Types::DynValue.of_date(val.raw || val.value.to_s)
    when Odin::Types::OdinTimestamp then Odin::Types::DynValue.of_timestamp(val.raw || val.value.to_s)
    when Odin::Types::OdinTime then Odin::Types::DynValue.of_time(val.value)
    when Odin::Types::OdinDuration then Odin::Types::DynValue.of_duration(val.value)
    when Odin::Types::OdinReference then Odin::Types::DynValue.of_reference(val.path)
    when Odin::Types::OdinBinary then Odin::Types::DynValue.of_binary(val.data)
    when Odin::Types::OdinPercent then Odin::Types::DynValue.of_percent(val.value)
    when Odin::Types::OdinArray
      items = val.items.map { |item|
        item.is_a?(Odin::Types::ArrayItem) ? odin_value_to_dyn(item.value) : odin_value_to_dyn(item)
      }
      Odin::Types::DynValue.of_array(items)
    when Odin::Types::OdinObject
      entries = val.entries.transform_values { |v| odin_value_to_dyn(v) }
      Odin::Types::DynValue.of_object(entries)
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
        if next_seg.is_a?(Integer)
          current[seg] ||= []
        else
          current[seg] ||= {}
        end
        current = current[seg]
      end
    end

    last = segments.last
    current[last] = value
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

  def run_transform_test(test, cat_dir)
    test_id = test["id"]
    direction = test["direction"] || "odin->odin"
    src_fmt = source_format(direction)

    input_raw = normalize(File.read(File.join(cat_dir, test["input"]), encoding: "UTF-8"))
    transform_text = normalize(File.read(File.join(cat_dir, test["transform"]), encoding: "UTF-8"))
    expected = normalize(File.read(File.join(cat_dir, test["expected"]), encoding: "UTF-8"))

    parser = Odin::Transform::TransformParser.new
    transform_def = parser.parse(transform_text)
    source = parse_input(input_raw, src_fmt)

    engine = Odin::Transform::TransformEngine.new
    result = engine.execute(transform_def, source)

    formatted = normalize(result.formatted || "")
    expect(formatted).to eq(expected),
      "[#{test_id}] Formatted output mismatch:\n  EXPECTED:\n#{expected}\n  ACTUAL:\n#{formatted}"
  end

  def run_roundtrip_test(test, cat_dir)
    test_id = test["id"]
    direction = test["direction"] || "fixed-width->fixed-width"
    src_fmt = source_format(direction)

    input_raw = normalize(File.read(File.join(cat_dir, test["input"]), encoding: "UTF-8"))
    import_text = normalize(File.read(File.join(cat_dir, test["importTransform"]), encoding: "UTF-8"))
    export_text = normalize(File.read(File.join(cat_dir, test["exportTransform"]), encoding: "UTF-8"))
    expected = normalize(File.read(File.join(cat_dir, test["expected"]), encoding: "UTF-8"))

    parser = Odin::Transform::TransformParser.new
    engine = Odin::Transform::TransformEngine.new

    # Step 1: Import
    import_transform = parser.parse(import_text)
    source = parse_input(input_raw, src_fmt)
    import_result = engine.execute(import_transform, source)

    # Step 2: Export (use DynValue output to preserve types like currency decimal places)
    export_transform = parser.parse(export_text)
    export_source = import_result.output_dv || import_result.output
    export_result = engine.execute(export_transform, export_source)

    formatted = normalize(export_result.formatted || "")
    expect(formatted).to eq(expected),
      "[#{test_id}] Roundtrip output mismatch:\n  EXPECTED:\n#{expected}\n  ACTUAL:\n#{formatted}"
  end

  def run_direct_export_test(test, cat_dir)
    test_id = test["id"]
    input_text = normalize(File.read(File.join(cat_dir, test["input"]), encoding: "UTF-8"))
    expected = normalize(File.read(File.join(cat_dir, test["expected"]), encoding: "UTF-8"))

    doc = Odin.parse(input_text)
    method = test["method"] || "toJSON"
    options = test["options"] || {}

    actual = case method
             when "toJSON"
               Odin::Export.to_json(doc, pretty: true)
             when "toXML"
               Odin::Export.to_xml(doc,
                 root: "root",
                 preserve_types: options["preserveTypes"] || false,
                 preserve_modifiers: options["preserveModifiers"] || false)
             else
               raise "Unknown export method: #{method}"
             end

    actual = normalize(actual)
    expect(actual).to eq(expected),
      "[#{test_id}] #{method} output mismatch:\n  EXPECTED:\n#{expected}\n  ACTUAL:\n#{actual}"
  end

  discover_e2e_tests.each do |cat_id, test_id, test, cat_dir|
    it "#{cat_id}/#{test_id}" do
      if test["method"]
        run_direct_export_test(test, cat_dir)
      elsif test["importTransform"] && test["exportTransform"]
        run_roundtrip_test(test, cat_dir)
      elsif test["transform"]
        run_transform_test(test, cat_dir)
      else
        fail "[#{test_id}] No transform/method specified"
      end
    end
  end
end
