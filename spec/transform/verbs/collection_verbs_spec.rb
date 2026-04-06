# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Collection Verbs" do
  let(:engine) { Odin::Transform::TransformEngine.new }
  let(:ctx) { Odin::Transform::VerbContext.new }
  let(:dv) { Odin::Types::DynValue }

  def invoke(name, *args)
    engine.invoke_verb(name, args, ctx)
  end

  def int(v) = dv.of_integer(v)
  def flt(v) = dv.of_float(v)
  def str(v) = dv.of_string(v)
  def bool(v) = dv.of_bool(v)
  def null_val = dv.of_null
  def arr(*items) = dv.of_array(items)
  def obj(h) = dv.of_object(h.transform_keys(&:to_s).transform_values { |v| v.is_a?(Odin::Types::DynValue) ? v : dv.from_ruby(v) })

  # ── filter ──

  describe "filter" do
    it "filters by field = value" do
      data = arr(obj(name: "Alice", age: 30), obj(name: "Bob", age: 25))
      result = invoke("filter", data, str("name"), str("="), str("Alice"))
      expect(result.value.length).to eq(1)
      expect(result.value[0].get("name").to_string).to eq("Alice")
    end

    it "filters by field != value" do
      data = arr(obj(name: "Alice"), obj(name: "Bob"))
      result = invoke("filter", data, str("name"), str("!="), str("Alice"))
      expect(result.value.length).to eq(1)
      expect(result.value[0].get("name").to_string).to eq("Bob")
    end

    it "filters by field < value" do
      data = arr(obj(name: "A", age: 10), obj(name: "B", age: 20), obj(name: "C", age: 30))
      result = invoke("filter", data, str("age"), str("<"), int(25))
      expect(result.value.length).to eq(2)
    end

    it "filters by field > value" do
      data = arr(obj(name: "A", age: 10), obj(name: "B", age: 20), obj(name: "C", age: 30))
      result = invoke("filter", data, str("age"), str(">"), int(15))
      expect(result.value.length).to eq(2)
    end

    it "filters by contains" do
      data = arr(obj(name: "Alice Smith"), obj(name: "Bob Jones"))
      result = invoke("filter", data, str("name"), str("contains"), str("Smith"))
      expect(result.value.length).to eq(1)
      expect(result.value[0].get("name").to_string).to eq("Alice Smith")
    end

    it "filters by startsWith" do
      data = arr(obj(name: "Alice"), obj(name: "Bob"))
      result = invoke("filter", data, str("name"), str("startsWith"), str("Al"))
      expect(result.value.length).to eq(1)
    end

    it "filters by endsWith" do
      data = arr(obj(name: "Alice"), obj(name: "Bob"))
      result = invoke("filter", data, str("name"), str("endsWith"), str("ce"))
      expect(result.value.length).to eq(1)
    end

    it "returns empty array for empty input" do
      result = invoke("filter", arr, str("name"), str("="), str("x"))
      expect(result.value).to be_empty
    end

    it "returns empty array when no matches" do
      data = arr(obj(name: "Alice"), obj(name: "Bob"))
      result = invoke("filter", data, str("name"), str("="), str("Charlie"))
      expect(result.value).to be_empty
    end

    it "filters truthy values with field" do
      data = arr(obj(active: true), obj(active: false))
      result = invoke("filter", data, str("active"))
      expect(result.value.length).to eq(1)
    end

    it "filters truthy values without field" do
      data = arr(int(1), int(0), str("hello"), str(""), null_val)
      result = invoke("filter", data)
      items = result.value
      expect(items.length).to eq(2) # 1 and "hello"
    end
  end

  describe "filter edge cases" do
    it "filters by <= operator" do
      data = arr(obj(age: 10), obj(age: 20), obj(age: 30))
      result = invoke("filter", data, str("age"), str("<="), int(20))
      expect(result.value.length).to eq(2)
    end

    it "filters by >= operator" do
      data = arr(obj(age: 10), obj(age: 20), obj(age: 30))
      result = invoke("filter", data, str("age"), str(">="), int(20))
      expect(result.value.length).to eq(2)
    end

    it "filters by == operator (alias for =)" do
      data = arr(obj(x: "a"), obj(x: "b"))
      result = invoke("filter", data, str("x"), str("=="), str("a"))
      expect(result.value.length).to eq(1)
    end

    it "filters by <> operator (alias for !=)" do
      data = arr(obj(x: "a"), obj(x: "b"))
      result = invoke("filter", data, str("x"), str("<>"), str("a"))
      expect(result.value.length).to eq(1)
    end
  end

  # ── flatten ──

  describe "flatten" do
    it "flattens one level of nesting" do
      data = arr(arr(int(1), int(2)), arr(int(3), int(4)))
      result = invoke("flatten", data)
      expect(result.value.map(&:to_number)).to eq([1, 2, 3, 4])
    end

    it "returns already flat array unchanged" do
      data = arr(int(1), int(2), int(3))
      result = invoke("flatten", data)
      expect(result.value.map(&:to_number)).to eq([1, 2, 3])
    end

    it "handles nested arrays mixed with scalars" do
      data = arr(int(1), arr(int(2), int(3)), int(4))
      result = invoke("flatten", data)
      expect(result.value.map(&:to_number)).to eq([1, 2, 3, 4])
    end
  end

  # ── distinct / unique ──

  describe "distinct" do
    it "removes duplicate primitives" do
      data = arr(int(1), int(2), int(1), int(3), int(2))
      result = invoke("distinct", data)
      expect(result.value.map(&:to_number)).to eq([1, 2, 3])
    end

    it "returns array with no duplicates unchanged" do
      data = arr(int(1), int(2), int(3))
      result = invoke("distinct", data)
      expect(result.value.map(&:to_number)).to eq([1, 2, 3])
    end

    it "removes duplicate strings" do
      data = arr(str("a"), str("b"), str("a"))
      result = invoke("distinct", data)
      expect(result.value.map(&:to_string)).to eq(["a", "b"])
    end
  end

  describe "unique" do
    it "is an alias for distinct" do
      data = arr(int(1), int(1), int(2))
      result = invoke("unique", data)
      expect(result.value.map(&:to_number)).to eq([1, 2])
    end
  end

  describe "flatten edge cases" do
    it "handles empty array" do
      result = invoke("flatten", arr)
      expect(result.value).to be_empty
    end
  end

  # ── sort / sortDesc ──

  describe "sort" do
    it "sorts numbers ascending" do
      data = arr(int(3), int(1), int(2))
      result = invoke("sort", data)
      expect(result.value.map(&:to_number)).to eq([1, 2, 3])
    end

    it "sorts strings ascending" do
      data = arr(str("cherry"), str("apple"), str("banana"))
      result = invoke("sort", data)
      expect(result.value.map(&:to_string)).to eq(["apple", "banana", "cherry"])
    end
  end

  describe "sortDesc" do
    it "sorts numbers descending" do
      data = arr(int(1), int(3), int(2))
      result = invoke("sortDesc", data)
      expect(result.value.map(&:to_number)).to eq([3, 2, 1])
    end

    it "sorts strings descending" do
      data = arr(str("apple"), str("cherry"), str("banana"))
      result = invoke("sortDesc", data)
      expect(result.value.map(&:to_string)).to eq(["cherry", "banana", "apple"])
    end
  end

  # ── sortBy ──

  describe "sortBy" do
    it "sorts objects by a field" do
      data = arr(obj(name: "C", age: 30), obj(name: "A", age: 10), obj(name: "B", age: 20))
      result = invoke("sortBy", data, str("age"))
      names = result.value.map { |v| v.get("name").to_string }
      expect(names).to eq(["A", "B", "C"])
    end

    it "sorts objects by string field" do
      data = arr(obj(name: "Charlie"), obj(name: "Alice"), obj(name: "Bob"))
      result = invoke("sortBy", data, str("name"))
      names = result.value.map { |v| v.get("name").to_string }
      expect(names).to eq(["Alice", "Bob", "Charlie"])
    end
  end

  # ── map / pluck ──

  describe "map" do
    it "extracts field from objects" do
      data = arr(obj(name: "Alice"), obj(name: "Bob"))
      result = invoke("map", data, str("name"))
      expect(result.value.map(&:to_string)).to eq(["Alice", "Bob"])
    end

    it "returns null for missing field" do
      data = arr(obj(name: "Alice"), obj(age: 25))
      result = invoke("map", data, str("name"))
      expect(result.value[0].to_string).to eq("Alice")
      expect(result.value[1].null?).to be true
    end
  end

  describe "pluck" do
    it "extracts field from objects" do
      data = arr(obj(x: 1), obj(x: 2), obj(x: 3))
      result = invoke("pluck", data, str("x"))
      expect(result.value.map(&:to_number)).to eq([1, 2, 3])
    end

    it "returns null for non-object items" do
      data = arr(int(1), obj(x: 2))
      result = invoke("pluck", data, str("x"))
      expect(result.value[0].null?).to be true
      expect(result.value[1].to_number).to eq(2)
    end
  end

  describe "map edge cases" do
    it "handles empty array" do
      result = invoke("map", arr, str("x"))
      expect(result.value).to be_empty
    end
  end

  # ── indexOf ──

  describe "indexOf" do
    it "returns index when found" do
      data = arr(str("a"), str("b"), str("c"))
      result = invoke("indexOf", data, str("b"))
      expect(result.value).to eq(1)
    end

    it "returns -1 when not found" do
      data = arr(str("a"), str("b"))
      result = invoke("indexOf", data, str("z"))
      expect(result.value).to eq(-1)
    end

    it "returns index for numeric values" do
      data = arr(int(10), int(20), int(30))
      result = invoke("indexOf", data, int(20))
      expect(result.value).to eq(1)
    end
  end

  # ── at ──

  describe "at" do
    it "returns element at positive index" do
      data = arr(str("a"), str("b"), str("c"))
      result = invoke("at", data, int(1))
      expect(result.to_string).to eq("b")
    end

    it "returns element at negative index" do
      data = arr(str("a"), str("b"), str("c"))
      result = invoke("at", data, int(-1))
      expect(result.to_string).to eq("c")
    end

    it "returns null for out of bounds" do
      data = arr(str("a"), str("b"))
      result = invoke("at", data, int(5))
      expect(result.null?).to be true
    end
  end

  # ── slice ──

  describe "slice" do
    it "slices with start and end" do
      data = arr(int(1), int(2), int(3), int(4), int(5))
      result = invoke("slice", data, int(1), int(4))
      expect(result.value.map(&:to_number)).to eq([2, 3, 4])
    end

    it "slices with negative start" do
      data = arr(int(1), int(2), int(3), int(4), int(5))
      result = invoke("slice", data, int(-3), int(5))
      expect(result.value.map(&:to_number)).to eq([3, 4, 5])
    end

    it "slices with only start" do
      data = arr(int(1), int(2), int(3), int(4))
      result = invoke("slice", data, int(2))
      expect(result.value.map(&:to_number)).to eq([3, 4])
    end

    it "slices with negative end" do
      data = arr(int(1), int(2), int(3), int(4), int(5))
      result = invoke("slice", data, int(1), int(-1))
      expect(result.value.map(&:to_number)).to eq([2, 3, 4])
    end
  end

  # ── reverse ──

  describe "reverse" do
    it "reverses an array" do
      data = arr(int(1), int(2), int(3))
      result = invoke("reverse", data)
      expect(result.value.map(&:to_number)).to eq([3, 2, 1])
    end

    it "reverses an empty array" do
      result = invoke("reverse", arr)
      expect(result.value).to be_empty
    end
  end

  # ── every ──

  describe "every" do
    it "returns true when all truthy" do
      data = arr(int(1), int(2), int(3))
      result = invoke("every", data)
      expect(result.value).to be true
    end

    it "returns false when one falsy" do
      data = arr(int(1), int(0), int(3))
      result = invoke("every", data)
      expect(result.value).to be false
    end

    it "returns true for empty array" do
      result = invoke("every", arr)
      expect(result.value).to be true
    end

    it "checks field on objects" do
      data = arr(obj(active: true), obj(active: true))
      result = invoke("every", data, str("active"))
      expect(result.value).to be true
    end

    it "returns false when one object field is falsy" do
      data = arr(obj(active: true), obj(active: false))
      result = invoke("every", data, str("active"))
      expect(result.value).to be false
    end
  end

  # ── some ──

  describe "some" do
    it "returns true when one truthy" do
      data = arr(int(0), int(1), int(0))
      result = invoke("some", data)
      expect(result.value).to be true
    end

    it "returns false when none truthy" do
      data = arr(int(0), null_val, bool(false))
      result = invoke("some", data)
      expect(result.value).to be false
    end

    it "returns false for empty array" do
      result = invoke("some", arr)
      expect(result.value).to be false
    end

    it "checks field on objects" do
      data = arr(obj(ok: false), obj(ok: true))
      result = invoke("some", data, str("ok"))
      expect(result.value).to be true
    end

    it "returns false when no object field is truthy" do
      data = arr(obj(ok: false), obj(ok: false))
      result = invoke("some", data, str("ok"))
      expect(result.value).to be false
    end
  end

  # ── find ──

  describe "find" do
    it "returns first truthy item" do
      data = arr(int(0), int(42), int(99))
      result = invoke("find", data)
      expect(result.to_number).to eq(42)
    end

    it "returns null when not found" do
      data = arr(int(0), null_val, bool(false))
      result = invoke("find", data)
      expect(result.null?).to be true
    end

    it "finds by field" do
      data = arr(obj(name: "A", ok: false), obj(name: "B", ok: true))
      result = invoke("find", data, str("ok"))
      expect(result.get("name").to_string).to eq("B")
    end
  end

  # ── findIndex ──

  describe "findIndex" do
    it "returns index of first truthy" do
      data = arr(int(0), int(0), int(5))
      result = invoke("findIndex", data)
      expect(result.value).to eq(2)
    end

    it "returns -1 when not found" do
      data = arr(int(0), null_val)
      result = invoke("findIndex", data)
      expect(result.value).to eq(-1)
    end

    it "finds index by field" do
      data = arr(obj(ok: false), obj(ok: true))
      result = invoke("findIndex", data, str("ok"))
      expect(result.value).to eq(1)
    end
  end

  # ── includes ──

  describe "includes" do
    it "returns true when value found" do
      data = arr(int(1), int(2), int(3))
      result = invoke("includes", data, int(2))
      expect(result.value).to be true
    end

    it "returns false when value not found" do
      data = arr(int(1), int(2), int(3))
      result = invoke("includes", data, int(99))
      expect(result.value).to be false
    end

    it "works with strings" do
      data = arr(str("a"), str("b"), str("c"))
      result = invoke("includes", data, str("b"))
      expect(result.value).to be true
    end
  end

  describe "includes edge cases" do
    it "returns false for empty array" do
      result = invoke("includes", arr, int(1))
      expect(result.value).to be false
    end
  end

  # ── concatArrays ──

  describe "concatArrays" do
    it "concatenates two arrays" do
      a = arr(int(1), int(2))
      b = arr(int(3), int(4))
      result = invoke("concatArrays", a, b)
      expect(result.value.map(&:to_number)).to eq([1, 2, 3, 4])
    end

    it "handles empty arrays" do
      a = arr
      b = arr(int(1))
      result = invoke("concatArrays", a, b)
      expect(result.value.map(&:to_number)).to eq([1])
    end

    it "concatenates multiple arrays" do
      a = arr(int(1))
      b = arr(int(2))
      c = arr(int(3))
      result = invoke("concatArrays", a, b, c)
      expect(result.value.map(&:to_number)).to eq([1, 2, 3])
    end
  end

  # ── zip ──

  describe "zip" do
    it "zips equal length arrays" do
      a = arr(int(1), int(2), int(3))
      b = arr(str("a"), str("b"), str("c"))
      result = invoke("zip", a, b)
      expect(result.value.length).to eq(3)
      expect(result.value[0].value[0].to_number).to eq(1)
      expect(result.value[0].value[1].to_string).to eq("a")
    end

    it "zips unequal length arrays with null padding" do
      a = arr(int(1), int(2))
      b = arr(str("a"))
      result = invoke("zip", a, b)
      expect(result.value.length).to eq(2)
      expect(result.value[1].value[1].null?).to be true
    end
  end

  # ── groupBy ──

  describe "groupBy" do
    it "groups objects by field" do
      data = arr(
        obj(dept: "eng", name: "A"),
        obj(dept: "sales", name: "B"),
        obj(dept: "eng", name: "C")
      )
      result = invoke("groupBy", data, str("dept"))
      expect(result.object?).to be true
      eng = result.get("eng")
      expect(eng.value.length).to eq(2)
      sales = result.get("sales")
      expect(sales.value.length).to eq(1)
    end
  end

  # ── partition ──

  describe "partition" do
    it "partitions by truthy field" do
      data = arr(obj(ok: true, n: 1), obj(ok: false, n: 2), obj(ok: true, n: 3))
      result = invoke("partition", data, str("ok"))
      pass = result.value[0].value
      fail_items = result.value[1].value
      expect(pass.length).to eq(2)
      expect(fail_items.length).to eq(1)
    end

    it "partitions by truthy value without field" do
      data = arr(int(1), int(0), int(3))
      result = invoke("partition", data)
      pass = result.value[0].value
      fail_items = result.value[1].value
      expect(pass.length).to eq(2)
      expect(fail_items.length).to eq(1)
    end
  end

  # ── take / limit ──

  describe "take" do
    it "takes first n elements" do
      data = arr(int(1), int(2), int(3), int(4))
      result = invoke("take", data, int(2))
      expect(result.value.map(&:to_number)).to eq([1, 2])
    end

    it "returns full array when n is larger" do
      data = arr(int(1), int(2))
      result = invoke("take", data, int(10))
      expect(result.value.map(&:to_number)).to eq([1, 2])
    end
  end

  describe "limit" do
    it "is an alias for take" do
      data = arr(int(1), int(2), int(3))
      result = invoke("limit", data, int(2))
      expect(result.value.map(&:to_number)).to eq([1, 2])
    end
  end

  # ── drop ──

  describe "drop" do
    it "drops first n elements" do
      data = arr(int(1), int(2), int(3), int(4))
      result = invoke("drop", data, int(2))
      expect(result.value.map(&:to_number)).to eq([3, 4])
    end

    it "returns empty when n is larger than array" do
      data = arr(int(1), int(2))
      result = invoke("drop", data, int(10))
      expect(result.value).to be_empty
    end
  end

  # ── chunk ──

  describe "chunk" do
    it "chunks evenly" do
      data = arr(int(1), int(2), int(3), int(4))
      result = invoke("chunk", data, int(2))
      expect(result.value.length).to eq(2)
      expect(result.value[0].value.map(&:to_number)).to eq([1, 2])
      expect(result.value[1].value.map(&:to_number)).to eq([3, 4])
    end

    it "chunks unevenly" do
      data = arr(int(1), int(2), int(3), int(4), int(5))
      result = invoke("chunk", data, int(2))
      expect(result.value.length).to eq(3)
      expect(result.value[2].value.map(&:to_number)).to eq([5])
    end

    it "handles chunk size larger than array" do
      data = arr(int(1), int(2))
      result = invoke("chunk", data, int(10))
      expect(result.value.length).to eq(1)
      expect(result.value[0].value.map(&:to_number)).to eq([1, 2])
    end
  end

  describe "chunk edge cases" do
    it "handles empty array" do
      result = invoke("chunk", arr, int(2))
      expect(result.value).to be_empty
    end
  end

  describe "drop edge cases" do
    it "drops zero elements" do
      data = arr(int(1), int(2))
      result = invoke("drop", data, int(0))
      expect(result.value.map(&:to_number)).to eq([1, 2])
    end
  end

  # ── range ──

  describe "range" do
    it "generates range with 1 arg (0 to n)" do
      result = invoke("range", int(5))
      expect(result.value.map(&:to_number)).to eq([0, 1, 2, 3, 4])
    end

    it "generates range with 2 args (start to end)" do
      result = invoke("range", int(2), int(6))
      expect(result.value.map(&:to_number)).to eq([2, 3, 4, 5])
    end

    it "generates range with 3 args (start, end, step)" do
      result = invoke("range", int(0), int(10), int(3))
      expect(result.value.map(&:to_number)).to eq([0, 3, 6, 9])
    end

    it "generates descending range" do
      result = invoke("range", int(5), int(0))
      expect(result.value.map(&:to_number)).to eq([5, 4, 3, 2, 1])
    end
  end

  # ── compact ──

  describe "compact" do
    it "removes nulls and empty strings" do
      data = arr(int(1), null_val, str(""), str("hello"), int(0))
      result = invoke("compact", data)
      expect(result.value.length).to eq(3)
      expect(result.value[0].to_number).to eq(1)
      expect(result.value[1].to_string).to eq("hello")
      expect(result.value[2].to_number).to eq(0)
    end

    it "returns array unchanged when no nulls or empty strings" do
      data = arr(int(1), int(2))
      result = invoke("compact", data)
      expect(result.value.map(&:to_number)).to eq([1, 2])
    end
  end

  describe "compact edge cases" do
    it "handles empty array" do
      result = invoke("compact", arr)
      expect(result.value).to be_empty
    end

    it "removes only nulls, keeps zero" do
      data = arr(int(0), null_val, bool(false))
      result = invoke("compact", data)
      expect(result.value.length).to eq(2)
    end
  end

  # ── rowNumber ──

  describe "rowNumber" do
    it "returns incrementing row numbers" do
      r1 = invoke("rowNumber")
      r2 = invoke("rowNumber")
      r3 = invoke("rowNumber")
      expect(r1.value).to eq(1)
      expect(r2.value).to eq(2)
      expect(r3.value).to eq(3)
    end
  end

  # ── sample ──

  describe "sample" do
    it "returns correct count with seed for determinism" do
      data = arr(int(1), int(2), int(3), int(4), int(5))
      result = invoke("sample", data, int(3), int(42))
      expect(result.value.length).to eq(3)
    end

    it "returns all items when count exceeds length" do
      data = arr(int(1), int(2))
      result = invoke("sample", data, int(5), int(42))
      expect(result.value.length).to eq(2)
    end

    it "returns same result with same seed" do
      data = arr(int(1), int(2), int(3), int(4), int(5))
      r1 = invoke("sample", data, int(3), int(99))
      r2 = invoke("sample", data, int(3), int(99))
      expect(r1.value.map(&:to_number)).to eq(r2.value.map(&:to_number))
    end
  end

  # ── dedupe ──

  describe "dedupe" do
    it "removes consecutive duplicates" do
      data = arr(int(1), int(1), int(2), int(2), int(1))
      result = invoke("dedupe", data)
      expect(result.value.map(&:to_number)).to eq([1, 2, 1])
    end

    it "removes consecutive duplicates by field" do
      data = arr(obj(cat: "A", v: 1), obj(cat: "A", v: 2), obj(cat: "B", v: 3))
      result = invoke("dedupe", data, str("cat"))
      expect(result.value.length).to eq(2)
      expect(result.value[0].get("v").to_number).to eq(1)
      expect(result.value[1].get("v").to_number).to eq(3)
    end
  end

  # ── cumsum ──

  describe "cumsum" do
    it "computes cumulative sum" do
      data = arr(int(1), int(2), int(3))
      result = invoke("cumsum", data)
      expect(result.value.map(&:to_number)).to eq([1, 3, 6])
    end

    it "handles single element" do
      data = arr(int(5))
      result = invoke("cumsum", data)
      expect(result.value.map(&:to_number)).to eq([5])
    end

    it "handles empty array" do
      result = invoke("cumsum", arr)
      expect(result.value).to be_empty
    end
  end

  # ── cumprod ──

  describe "cumprod" do
    it "computes cumulative product" do
      data = arr(int(1), int(2), int(3))
      result = invoke("cumprod", data)
      expect(result.value.map(&:to_number)).to eq([1, 2, 6])
    end

    it "handles zeros" do
      data = arr(int(1), int(0), int(3))
      result = invoke("cumprod", data)
      expect(result.value.map(&:to_number)).to eq([1, 0, 0])
    end
  end

  # ── diff ──

  describe "diff" do
    it "computes differences with default lag 1" do
      data = arr(int(1), int(3), int(6))
      result = invoke("diff", data)
      expect(result.value[0].null?).to be true
      expect(result.value[1].to_number).to eq(2)
      expect(result.value[2].to_number).to eq(3)
    end

    it "computes differences with lag 2" do
      data = arr(int(1), int(3), int(6), int(10))
      result = invoke("diff", data, int(2))
      expect(result.value[0].null?).to be true
      expect(result.value[1].null?).to be true
      expect(result.value[2].to_number).to eq(5)
      expect(result.value[3].to_number).to eq(7)
    end
  end

  # ── pctChange ──

  describe "pctChange" do
    it "computes percentage change" do
      data = arr(int(100), int(110), int(99))
      result = invoke("pctChange", data)
      expect(result.value[0].null?).to be true
      expect(result.value[1].value).to be_within(0.001).of(0.1)
      expect(result.value[2].value).to be_within(0.001).of(-0.1)
    end

    it "returns null for zero denominator" do
      data = arr(int(0), int(10))
      result = invoke("pctChange", data)
      expect(result.value[1].null?).to be true
    end
  end

  # ── shift ──

  describe "shift" do
    it "shifts by positive value" do
      data = arr(int(1), int(2), int(3))
      result = invoke("shift", data, int(1))
      expect(result.value[0].null?).to be true
      expect(result.value[1].to_number).to eq(1)
      expect(result.value[2].to_number).to eq(2)
    end

    it "shifts by negative value" do
      data = arr(int(1), int(2), int(3))
      result = invoke("shift", data, int(-1))
      expect(result.value[0].to_number).to eq(2)
      expect(result.value[1].to_number).to eq(3)
      expect(result.value[2].null?).to be true
    end

    it "uses fill value" do
      data = arr(int(1), int(2), int(3))
      result = invoke("shift", data, int(1), int(0))
      expect(result.value[0].to_number).to eq(0)
      expect(result.value[1].to_number).to eq(1)
    end
  end

  # ── lag ──

  describe "lag" do
    it "lags by default 1" do
      data = arr(int(10), int(20), int(30))
      result = invoke("lag", data)
      expect(result.value[0].null?).to be true
      expect(result.value[1].to_number).to eq(10)
      expect(result.value[2].to_number).to eq(20)
    end

    it "lags with custom n" do
      data = arr(int(10), int(20), int(30), int(40))
      result = invoke("lag", data, int(2))
      expect(result.value[0].null?).to be true
      expect(result.value[1].null?).to be true
      expect(result.value[2].to_number).to eq(10)
      expect(result.value[3].to_number).to eq(20)
    end

    it "lags with fill value" do
      data = arr(int(10), int(20), int(30))
      result = invoke("lag", data, int(1), int(0))
      expect(result.value[0].to_number).to eq(0)
      expect(result.value[1].to_number).to eq(10)
    end
  end

  # ── lead ──

  describe "lead" do
    it "leads by default 1" do
      data = arr(int(10), int(20), int(30))
      result = invoke("lead", data)
      expect(result.value[0].to_number).to eq(20)
      expect(result.value[1].to_number).to eq(30)
      expect(result.value[2].null?).to be true
    end

    it "leads with custom n" do
      data = arr(int(10), int(20), int(30), int(40))
      result = invoke("lead", data, int(2))
      expect(result.value[0].to_number).to eq(30)
      expect(result.value[1].to_number).to eq(40)
      expect(result.value[2].null?).to be true
      expect(result.value[3].null?).to be true
    end

    it "leads with fill value" do
      data = arr(int(10), int(20), int(30))
      result = invoke("lead", data, int(1), int(99))
      expect(result.value[2].to_number).to eq(99)
    end
  end

  # ── rank ──

  describe "rank" do
    it "ranks descending by default" do
      data = arr(int(30), int(10), int(20))
      result = invoke("rank", data)
      expect(result.value[0].value).to eq(1) # 30 is rank 1 desc
      expect(result.value[1].value).to eq(3) # 10 is rank 3 desc
      expect(result.value[2].value).to eq(2) # 20 is rank 2 desc
    end

    it "ranks ascending" do
      data = arr(int(30), int(10), int(20))
      result = invoke("rank", data, null_val, str("asc"))
      expect(result.value[0].value).to eq(3) # 30 is rank 3 asc
      expect(result.value[1].value).to eq(1) # 10 is rank 1 asc
      expect(result.value[2].value).to eq(2) # 20 is rank 2 asc
    end

    it "ranks by field" do
      data = arr(obj(score: 80), obj(score: 95), obj(score: 70))
      result = invoke("rank", data, str("score"), str("desc"))
      expect(result.value[0].value).to eq(2) # 80 is rank 2
      expect(result.value[1].value).to eq(1) # 95 is rank 1
      expect(result.value[2].value).to eq(3) # 70 is rank 3
    end
  end

  # ── fillMissing ──

  describe "fillMissing" do
    it "fills with forward strategy" do
      data = arr(int(1), null_val, null_val, int(4))
      result = invoke("fillMissing", data, str("forward"))
      expect(result.value.map(&:to_number)).to eq([1, 1, 1, 4])
    end

    it "fills with backward strategy" do
      data = arr(null_val, null_val, int(3), int(4))
      result = invoke("fillMissing", data, str("backward"))
      expect(result.value.map(&:to_number)).to eq([3, 3, 3, 4])
    end

    it "fills with value strategy" do
      data = arr(int(1), null_val, int(3))
      result = invoke("fillMissing", data, str("value"), int(0))
      expect(result.value.map(&:to_number)).to eq([1, 0, 3])
    end

    it "forward fill keeps null at start" do
      data = arr(null_val, int(2), null_val)
      result = invoke("fillMissing", data, str("forward"))
      expect(result.value[0].null?).to be true
      expect(result.value[1].to_number).to eq(2)
      expect(result.value[2].to_number).to eq(2)
    end

    it "backward fill keeps null at end" do
      data = arr(null_val, int(2), null_val)
      result = invoke("fillMissing", data, str("backward"))
      expect(result.value[0].to_number).to eq(2)
      expect(result.value[1].to_number).to eq(2)
      expect(result.value[2].null?).to be true
    end
  end
end
