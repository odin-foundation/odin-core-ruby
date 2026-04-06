# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "Path Resolution" do
  let(:engine) { Odin::Transform::TransformEngine.new }

  let(:source) do
    Odin::Types::DynValue.from_ruby({
      "name" => "Alice",
      "age" => 30,
      "address" => {
        "city" => "Portland",
        "state" => "OR",
        "zip" => "97201"
      },
      "items" => [
        { "id" => 1, "name" => "Widget" },
        { "id" => 2, "name" => "Gadget" }
      ],
      "a" => {
        "b" => {
          "c" => {
            "d" => {
              "e" => "deep_value"
            }
          }
        }
      },
      "tags" => ["ruby", "odin", "transform"]
    })
  end

  let(:context) do
    ctx = Odin::Transform::VerbContext.new
    ctx.source = source
    ctx
  end

  describe "simple path resolution" do
    it "resolves simple field: .name" do
      result = engine.send(:resolve_dotted_path, source, ".name")
      expect(result).to eq(Odin::Types::DynValue.of_string("Alice"))
    end

    it "resolves simple field without leading dot: name" do
      result = engine.send(:resolve_dotted_path, source, "name")
      expect(result).to eq(Odin::Types::DynValue.of_string("Alice"))
    end

    it "resolves integer field: age" do
      result = engine.send(:resolve_dotted_path, source, "age")
      expect(result).to eq(Odin::Types::DynValue.of_integer(30))
    end
  end

  describe "nested path resolution" do
    it "resolves nested path: .address.city" do
      result = engine.send(:resolve_dotted_path, source, ".address.city")
      expect(result).to eq(Odin::Types::DynValue.of_string("Portland"))
    end

    it "resolves nested path: address.state" do
      result = engine.send(:resolve_dotted_path, source, "address.state")
      expect(result).to eq(Odin::Types::DynValue.of_string("OR"))
    end

    it "resolves nested path: address.zip" do
      result = engine.send(:resolve_dotted_path, source, "address.zip")
      expect(result).to eq(Odin::Types::DynValue.of_string("97201"))
    end
  end

  describe "array index resolution" do
    it "resolves array index: .items[0]" do
      result = engine.send(:resolve_dotted_path, source, ".items[0]")
      expect(result.object?).to be true
      expect(result.get("id")).to eq(Odin::Types::DynValue.of_integer(1))
    end

    it "resolves array index: items[1]" do
      result = engine.send(:resolve_dotted_path, source, "items[1]")
      expect(result.object?).to be true
      expect(result.get("name")).to eq(Odin::Types::DynValue.of_string("Gadget"))
    end

    it "resolves nested array: .items[0].name" do
      result = engine.send(:resolve_dotted_path, source, ".items[0].name")
      expect(result).to eq(Odin::Types::DynValue.of_string("Widget"))
    end

    it "resolves nested array: items[1].id" do
      result = engine.send(:resolve_dotted_path, source, "items[1].id")
      expect(result).to eq(Odin::Types::DynValue.of_integer(2))
    end

    it "resolves simple array element: tags[0]" do
      result = engine.send(:resolve_dotted_path, source, "tags[0]")
      expect(result).to eq(Odin::Types::DynValue.of_string("ruby"))
    end

    it "resolves simple array element: tags[2]" do
      result = engine.send(:resolve_dotted_path, source, "tags[2]")
      expect(result).to eq(Odin::Types::DynValue.of_string("transform"))
    end
  end

  describe "bare @ (source root)" do
    it "returns source root for empty path" do
      result = engine.send(:resolve_path, "", context)
      expect(result).to eq(source)
    end

    it "returns source root for nil path" do
      result = engine.send(:resolve_path, nil, context)
      expect(result).to eq(source)
    end
  end

  describe "missing path resolution" do
    it "returns null for missing field" do
      result = engine.send(:resolve_dotted_path, source, "nonexistent")
      expect(result).to eq(Odin::Types::DynValue.of_null)
    end

    it "returns null for missing nested field" do
      result = engine.send(:resolve_dotted_path, source, "address.country")
      expect(result).to eq(Odin::Types::DynValue.of_null)
    end

    it "returns null for out-of-bounds array index" do
      result = engine.send(:resolve_dotted_path, source, "items[99]")
      expect(result).to eq(Odin::Types::DynValue.of_null)
    end

    it "returns null for path into non-object" do
      result = engine.send(:resolve_dotted_path, source, "name.something")
      expect(result).to eq(Odin::Types::DynValue.of_null)
    end

    it "returns null for array index on non-array" do
      result = engine.send(:resolve_dotted_path, source, "name[0]")
      expect(result).to eq(Odin::Types::DynValue.of_null)
    end
  end

  describe "deep nesting" do
    it "resolves deep path: .a.b.c.d.e" do
      result = engine.send(:resolve_dotted_path, source, ".a.b.c.d.e")
      expect(result).to eq(Odin::Types::DynValue.of_string("deep_value"))
    end
  end

  describe "resolve_path with context" do
    it "resolves path starting with ." do
      result = engine.send(:resolve_path, ".name", context)
      expect(result).to eq(Odin::Types::DynValue.of_string("Alice"))
    end

    it "resolves constant path" do
      context.constants["greeting"] = Odin::Types::DynValue.of_string("hello")
      result = engine.send(:resolve_path, "$const.greeting", context)
      expect(result).to eq(Odin::Types::DynValue.of_string("hello"))
    end

    it "resolves accumulator path" do
      context.set_accumulator("count", Odin::Types::DynValue.of_integer(5))
      result = engine.send(:resolve_path, "$accumulator.count", context)
      expect(result).to eq(Odin::Types::DynValue.of_integer(5))
    end

    it "resolves _index in loop" do
      context.loop_vars["_index"] = Odin::Types::DynValue.of_integer(3)
      context.current_item = Odin::Types::DynValue.of_string("x")
      result = engine.send(:resolve_path, "_index", context)
      expect(result).to eq(Odin::Types::DynValue.of_integer(3))
    end

    it "resolves _length in loop" do
      context.loop_vars["_length"] = Odin::Types::DynValue.of_integer(10)
      context.current_item = Odin::Types::DynValue.of_string("x")
      result = engine.send(:resolve_path, "_length", context)
      expect(result).to eq(Odin::Types::DynValue.of_integer(10))
    end

    it "resolves from current_item in loop" do
      item = Odin::Types::DynValue.from_ruby({ "x" => 42 })
      context.current_item = item
      result = engine.send(:resolve_path, ".x", context)
      expect(result).to eq(Odin::Types::DynValue.of_integer(42))
    end
  end

  describe "parse_path_segments" do
    it "parses simple path" do
      segs = engine.send(:parse_path_segments, "name")
      expect(segs).to eq(["name"])
    end

    it "parses dotted path" do
      segs = engine.send(:parse_path_segments, "a.b.c")
      expect(segs).to eq(%w[a b c])
    end

    it "parses path with array index" do
      segs = engine.send(:parse_path_segments, "items[0].name")
      expect(segs).to eq(["items", 0, "name"])
    end

    it "parses multiple array indices" do
      segs = engine.send(:parse_path_segments, "a[0].b[1].c")
      expect(segs).to eq(["a", 0, "b", 1, "c"])
    end
  end
end
