# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Odin.collapse_chain" do
  # --- replace ---
  it "replaces a repeated path and keeps untouched paths" do
    current = Odin.collapse_chain(
      "{person}\nname = \"John\"\nage = ##30\ncity = \"Austin\"\n\n---\n\n{person}\nage = ##31\nstate = \"TX\""
    )
    expect(current.get("person.name").value).to eq("John")
    expect(current.get("person.age").value).to eq(31)
    expect(current.get("person.city").value).to eq("Austin")
    expect(current.get("person.state").value).to eq("TX")
  end

  # --- null removal ---
  it "removes a field assigned ~" do
    current = Odin.collapse_chain(
      "{person}\nname = \"John\"\ntemporary = \"gone\"\n\n---\n\n{person}\ntemporary = ~"
    )
    expect(current.get("person.name").value).to eq("John")
    expect(current.get("person.temporary")).to be_nil
  end

  # --- subtree removal ---
  it "removes nested descendants when a parent is assigned ~" do
    current = Odin.collapse_chain(
      "{p}\na.b = \"x\"\na.c = \"y\"\nkeep = \"z\"\n\n---\n\n{p}\na = ~"
    )
    expect(current.get("p.keep").value).to eq("z")
    expect(current.get("p.a.b")).to be_nil
    expect(current.get("p.a.c")).to be_nil
  end

  # --- reassign after removal ---
  it "allows a removed field to be reassigned by a later document" do
    current = Odin.collapse_chain(
      "{p}\nx = \"old\"\n\n---\n\n{p}\nx = ~\n\n---\n\n{p}\nx = \"new\""
    )
    expect(current.get("p.x").value).to eq("new")
  end

  # --- array clear ---
  it "clears all elements of an array with field[] = ~" do
    current = Odin.collapse_chain(
      "{p}\ntags[0] = \"x\"\ntags[1] = \"y\"\nkeep = \"z\"\n\n---\n\n{p}\ntags[] = ~"
    )
    expect(current.get("p.keep").value).to eq("z")
    expect(current.get("p.tags[0]")).to be_nil
    expect(current.get("p.tags[1]")).to be_nil
  end

  # --- repopulate ---
  it "repopulates a cleared array in a later document" do
    current = Odin.collapse_chain(
      "{p}\ntags[0] = \"x\"\n\n---\n\n{p}\ntags[] = ~\n\n---\n\n{p}\ntags[0] = \"fresh\""
    )
    expect(current.get("p.tags[0]").value).to eq("fresh")
  end

  # --- metadata isolation ---
  it "carries only the final document's metadata" do
    current = Odin.collapse_chain(
      "{$}\nid = \"first\"\nrole = \"base\"\n\n{p}\nn = \"A\"\n\n---\n\n{$}\nid = \"second\"\n\n{p}\nn = \"B\""
    )
    expect(current.get("p.n").value).to eq("B")
    expect(current.metadata["id"].value).to eq("second")
    expect(current.metadata["role"]).to be_nil
  end

  # --- multi-doc ---
  it "resolves a three-document chain to the last assigned value" do
    current = Odin.collapse_chain(
      "{p}\nv = \"1\"\nstable = \"keep\"\n\n---\n\n{p}\nv = \"2\"\n\n---\n\n{p}\nv = \"3\""
    )
    expect(current.get("p.v").value).to eq("3")
    expect(current.get("p.stable").value).to eq("keep")
  end

  # --- single-doc passthrough ---
  it "returns a single document unchanged" do
    current = Odin.collapse_chain("{p}\nname = \"Solo\"\nage = ##42")
    expect(current.get("p.name").value).to eq("Solo")
    expect(current.get("p.age").value).to eq(42)
  end

  # --- accepts a pre-parsed document list ---
  it "accepts a pre-parsed list of documents" do
    docs = Odin.parse_documents("{p}\nx = \"1\"\n\n---\n\n{p}\nx = \"2\"")
    current = Odin.collapse_chain(docs)
    expect(current.get("p.x").value).to eq("2")
  end
end
