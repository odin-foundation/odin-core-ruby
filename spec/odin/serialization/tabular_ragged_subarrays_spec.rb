# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Tabular ragged sub-arrays" do
  def build_doc(&block)
    builder = Odin::Types::OdinDocumentBuilder.new
    block.call(builder)
    builder.build
  end

  def stringify(doc, **opts)
    Odin::Serialization::Stringify.new(opts).stringify(doc)
  end

  def s(v) = Odin::Types::OdinString.new(v)
  def i(v) = Odin::Types::OdinInteger.new(v)

  context "rejects tabular when sub-arrays have variable length" do
    it "emits nested form for ragged string sub-arrays" do
      doc = build_doc do |b|
        b.set("records[0].name", s("Alice"))
        b.set("records[0].tags[0]", s("red"))
        b.set("records[0].tags[1]", s("green"))
        b.set("records[0].tags[2]", s("blue"))
        b.set("records[1].name", s("Bob"))
        b.set("records[1].tags[0]", s("yellow"))
      end

      text = stringify(doc)

      expect(text).not_to match(/\{records\[\][^}]*tags\[2\]/)
      expect(text).to include("{records[0]}")
      expect(text).to include("{records[1]}")
      expect(text).to match(/\{\.tags\[\]\s*:\s*~\}/)
    end

    it "emits nested form for ragged numeric sub-arrays" do
      doc = build_doc do |b|
        b.set("points[0].label", s("A"))
        b.set("points[0].coords[0]", i(1))
        b.set("points[0].coords[1]", i(2))
        b.set("points[1].label", s("B"))
        b.set("points[1].coords[0]", i(3))
        b.set("points[1].coords[1]", i(4))
        b.set("points[1].coords[2]", i(5))
        b.set("points[1].coords[3]", i(6))
      end

      text = stringify(doc)

      expect(text).not_to match(/\{points\[\][^}]*coords\[3\]/)
      expect(text).to include("{points[0]}")
      expect(text).to include("{points[1]}")
      expect(text).to match(/\{\.coords\[\]\s*:\s*~\}/)
    end

    it "round-trips ragged sub-arrays without data loss" do
      doc = build_doc do |b|
        b.set("entries[0].slug", s("a/one"))
        b.set("entries[0].title", s("One"))
        b.set("entries[0].types[0]", s("alpha"))
        b.set("entries[0].types[1]", s("beta"))
        b.set("entries[0].fields[0]", s("id"))
        b.set("entries[0].fields[1]", s("name"))
        b.set("entries[0].fields[2]", s("desc"))
        b.set("entries[1].slug", s("b/two"))
        b.set("entries[1].title", s("Two"))
        b.set("entries[1].types[0]", s("gamma"))
        b.set("entries[1].fields[0]", s("id"))
      end

      text = stringify(doc)
      reparsed = Odin.parse(text)

      expect(reparsed.assignments["entries[0].slug"].value).to eq("a/one")
      expect(reparsed.assignments["entries[0].types[0]"].value).to eq("alpha")
      expect(reparsed.assignments["entries[0].types[1]"].value).to eq("beta")
      expect(reparsed.assignments["entries[0].fields[2]"].value).to eq("desc")
      expect(reparsed.assignments["entries[1].slug"].value).to eq("b/two")
      expect(reparsed.assignments["entries[1].types[0]"].value).to eq("gamma")
      expect(reparsed.assignments["entries[1].fields[0]"].value).to eq("id")
      expect(reparsed.assignments["entries[1].types[1]"]).to be_nil
      expect(reparsed.assignments["entries[1].fields[1]"]).to be_nil
    end
  end

  context "preserves tabular for dense uniform shapes" do
    it "emits tabular for records with only scalar columns" do
      doc = build_doc do |b|
        b.set("rows[0].name", s("Alice"))
        b.set("rows[0].age", i(30))
        b.set("rows[1].name", s("Bob"))
        b.set("rows[1].age", i(25))
      end

      text = stringify(doc)

      expect(text).to match(/\{rows\[\]\s*:\s*[^}]*name[^}]*age/)
      expect(text).not_to include("{rows[0]}")
    end

    it "emits tabular for records with uniform-width sub-arrays" do
      doc = build_doc do |b|
        b.set("points[0].label", s("A"))
        b.set("points[0].coords[0]", i(1))
        b.set("points[0].coords[1]", i(2))
        b.set("points[1].label", s("B"))
        b.set("points[1].coords[0]", i(3))
        b.set("points[1].coords[1]", i(4))
      end

      text = stringify(doc)

      expect(text).to match(/\{points\[\]\s*:[^}]*coords\[0\][^}]*coords\[1\]/)
      expect(text).not_to include("{points[0]}")
    end
  end

  context "size guarantee" do
    it "produces output smaller than the equivalent padded-tabular form" do
      doc = build_doc do |b|
        20.times do |r|
          b.set("entries[#{r}].slug", s("record/#{r}"))
          b.set("entries[#{r}].title", s("Record #{r}"))
          tag_count = 1 + r * 2
          tag_count.times do |t|
            b.set("entries[#{r}].tags[#{t}]", s("tag-#{r}-#{t}"))
          end
        end
      end

      text = stringify(doc)

      expect(text).not_to match(/tags\[39\]/)
      expect(text).to include("{entries[0]}")
      expect(text).to include("{entries[19]}")
      expect(text).to match(/\{\.tags\[\]\s*:\s*~\}/)
    end
  end
end
