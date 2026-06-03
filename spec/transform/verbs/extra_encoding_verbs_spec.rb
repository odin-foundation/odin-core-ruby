# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe "Extra Encoding Verbs" do
  let(:engine) { Odin::Transform::TransformEngine.new }
  let(:ctx) { Odin::Transform::VerbContext.new }
  let(:dv) { Odin::Types::DynValue }

  def invoke(name, *args)
    engine.invoke_verb(name, args, ctx)
  end

  # ── base64urlEncode / base64urlDecode ──

  describe "base64urlEncode" do
    it "encodes URL-safe without padding" do
      result = invoke("base64urlEncode", dv.of_string("hello world?>>"))
      expect(result.value).to eq("aGVsbG8gd29ybGQ_Pj4")
    end

    it "encodes an empty string to empty" do
      expect(invoke("base64urlEncode", dv.of_string("")).value).to eq("")
    end

    it "returns null for no arguments" do
      expect(invoke("base64urlEncode").null?).to be true
    end
  end

  describe "base64urlDecode" do
    it "decodes URL-safe unpadded text" do
      result = invoke("base64urlDecode", dv.of_string("aGVsbG8gd29ybGQ_Pj4"))
      expect(result.value).to eq("hello world?>>")
    end

    it "decodes standard padded base64" do
      result = invoke("base64urlDecode", dv.of_string("SGVsbG8="))
      expect(result.value).to eq("Hello")
    end

    it "round-trips through encode" do
      encoded = invoke("base64urlEncode", dv.of_string("hello world?>>"))
      expect(invoke("base64urlDecode", encoded).value).to eq("hello world?>>")
    end

    it "decodes empty to empty" do
      expect(invoke("base64urlDecode", dv.of_string("")).value).to eq("")
    end
  end

  # ── hmac ──

  describe "hmac" do
    it "computes lowercase hex sha256 by default" do
      result = invoke("hmac", dv.of_string("message"), dv.of_string("secret"))
      expect(result.value).to eq("8b5f48702995c1598c573db1e21866a9b825d4a794d169d7060a03605796360b")
    end

    it "computes sha1 when requested" do
      result = invoke("hmac", dv.of_string("message"), dv.of_string("secret"), dv.of_string("sha1"))
      expect(result.value).to eq("0caf649feee4953d87bf903ac1176c45e028df16")
    end

    it "returns null with fewer than two arguments" do
      expect(invoke("hmac", dv.of_string("message")).null?).to be true
    end
  end

  # ── stableStringify ──

  describe "stableStringify" do
    it "sorts object keys recursively" do
      doc = dv.of_object({
        "b" => dv.of_integer(2),
        "a" => dv.of_integer(1),
        "nested" => dv.of_object({ "y" => dv.of_integer(2), "x" => dv.of_integer(1) })
      })
      result = invoke("stableStringify", doc)
      expect(result.value).to eq('{"a":1,"b":2,"nested":{"x":1,"y":2}}')
    end

    it "preserves array order" do
      arr = dv.of_array([dv.of_integer(3), dv.of_integer(1), dv.of_integer(2)])
      expect(invoke("stableStringify", arr).value).to eq("[3,1,2]")
    end

    it "stringifies a scalar" do
      expect(invoke("stableStringify", dv.of_integer(42)).value).to eq("42")
    end
  end

  # ── canonicalHash ──

  describe "canonicalHash" do
    it "hashes the canonical form, independent of key order" do
      a = dv.of_object({ "b" => dv.of_integer(2), "a" => dv.of_integer(1) })
      b = dv.of_object({ "a" => dv.of_integer(1), "b" => dv.of_integer(2) })
      expected = "43258cff783fe7036d8a43033f830adfc60ec037382473548ac742b888292777"
      expect(invoke("canonicalHash", a).value).to eq(expected)
      expect(invoke("canonicalHash", b).value).to eq(expected)
    end

    it "returns null for no arguments" do
      expect(invoke("canonicalHash").null?).to be true
    end
  end

  # ── parseUrl ──

  describe "parseUrl" do
    it "parses scheme, host, port, path, query, and fragment" do
      result = invoke("parseUrl", dv.of_string("https://example.com:8080/a/b?z=1&a=2#frag"))
      expect(result.get("scheme").value).to eq("https")
      expect(result.get("host").value).to eq("example.com")
      expect(result.get("port").value).to eq(8080)
      expect(result.get("path").value).to eq("/a/b")
      expect(result.get("fragment").value).to eq("frag")
      expect(result.get("query").value.keys).to eq(%w[a z])
    end

    it "reports a null port when none is specified" do
      result = invoke("parseUrl", dv.of_string("https://example.com/x"))
      expect(result.get("port").null?).to be true
      expect(result.get("path").value).to eq("/x")
      expect(result.get("fragment").value).to eq("")
    end

    it "returns null for an invalid url" do
      expect(invoke("parseUrl", dv.of_string("not a url")).null?).to be true
    end
  end

  # ── buildUrl ──

  describe "buildUrl" do
    it "builds a url with sorted query keys" do
      parts = dv.of_object({
        "scheme" => dv.of_string("https"),
        "host" => dv.of_string("example.com"),
        "port" => dv.of_integer(8080),
        "path" => dv.of_string("/a/b"),
        "query" => dv.of_object({ "z" => dv.of_integer(1), "a" => dv.of_integer(2) }),
        "fragment" => dv.of_string("frag")
      })
      result = invoke("buildUrl", parts)
      expect(result.value).to eq("https://example.com:8080/a/b?a=2&z=1#frag")
    end

    it "returns null when scheme is missing" do
      parts = dv.of_object({ "host" => dv.of_string("example.com") })
      expect(invoke("buildUrl", parts).null?).to be true
    end
  end

  # ── parseQuery ──

  describe "parseQuery" do
    it "parses a query string with sorted keys" do
      result = invoke("parseQuery", dv.of_string("z=1&a=2"))
      expect(result.value.keys).to eq(%w[a z])
      expect(result.get("a").value).to eq("2")
    end

    it "strips a leading question mark" do
      result = invoke("parseQuery", dv.of_string("?a=2"))
      expect(result.get("a").value).to eq("2")
    end
  end

  # ── buildQuery ──

  describe "buildQuery" do
    it "builds a query string with sorted keys" do
      params = dv.of_object({ "z" => dv.of_integer(1), "a" => dv.of_integer(2) })
      expect(invoke("buildQuery", params).value).to eq("a=2&z=1")
    end

    it "skips null values" do
      params = dv.of_object({ "a" => dv.of_integer(1), "b" => dv.of_null })
      expect(invoke("buildQuery", params).value).to eq("a=1")
    end

    it "returns null for a non-object" do
      expect(invoke("buildQuery", dv.of_string("x")).null?).to be true
    end
  end
end
