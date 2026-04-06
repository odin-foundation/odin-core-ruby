# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Odin::Errors" do
  describe Odin::Errors::ParseErrorCode do
    it "defines P001 through P015" do
      expect(described_class::UNEXPECTED_CHARACTER).to eq("P001")
      expect(described_class::BARE_STRING_NOT_ALLOWED).to eq("P002")
      expect(described_class::INVALID_ARRAY_INDEX).to eq("P003")
      expect(described_class::UNTERMINATED_STRING).to eq("P004")
      expect(described_class::INVALID_ESCAPE_SEQUENCE).to eq("P005")
      expect(described_class::INVALID_TYPE_PREFIX).to eq("P006")
      expect(described_class::DUPLICATE_PATH_ASSIGNMENT).to eq("P007")
      expect(described_class::INVALID_HEADER_SYNTAX).to eq("P008")
      expect(described_class::INVALID_DIRECTIVE).to eq("P009")
      expect(described_class::MAXIMUM_DEPTH_EXCEEDED).to eq("P010")
      expect(described_class::MAXIMUM_DOCUMENT_SIZE_EXCEEDED).to eq("P011")
      expect(described_class::INVALID_UTF8_SEQUENCE).to eq("P012")
      expect(described_class::NON_CONTIGUOUS_ARRAY_INDICES).to eq("P013")
      expect(described_class::EMPTY_DOCUMENT).to eq("P014")
      expect(described_class::ARRAY_INDEX_OUT_OF_RANGE).to eq("P015")
    end

    it "has 15 error codes" do
      expect(described_class::ALL.size).to eq(15)
    end

    it "all codes have messages" do
      described_class::ALL.each do |code, msg|
        expect(msg).to be_a(String)
        expect(msg).not_to be_empty
      end
    end

    it ".message returns correct message" do
      expect(described_class.message("P001")).to eq("Unexpected character")
      expect(described_class.message("P004")).to eq("Unterminated string")
    end

    it ".message returns 'Unknown error' for invalid code" do
      expect(described_class.message("P999")).to eq("Unknown error")
    end
  end

  describe Odin::Errors::ValidationErrorCode do
    it "defines V001 through V013" do
      expect(described_class::REQUIRED_FIELD_MISSING).to eq("V001")
      expect(described_class::TYPE_MISMATCH).to eq("V002")
      expect(described_class::VALUE_OUT_OF_BOUNDS).to eq("V003")
      expect(described_class::PATTERN_MISMATCH).to eq("V004")
      expect(described_class::INVALID_ENUM_VALUE).to eq("V005")
      expect(described_class::ARRAY_LENGTH_VIOLATION).to eq("V006")
      expect(described_class::UNIQUE_CONSTRAINT_VIOLATION).to eq("V007")
      expect(described_class::INVARIANT_VIOLATION).to eq("V008")
      expect(described_class::CARDINALITY_CONSTRAINT_VIOLATION).to eq("V009")
      expect(described_class::CONDITIONAL_REQUIREMENT_NOT_MET).to eq("V010")
      expect(described_class::UNKNOWN_FIELD).to eq("V011")
      expect(described_class::CIRCULAR_REFERENCE).to eq("V012")
      expect(described_class::UNRESOLVED_REFERENCE).to eq("V013")
    end

    it "has 13 error codes" do
      expect(described_class::ALL.size).to eq(13)
    end

    it "all codes have messages" do
      described_class::ALL.each do |code, msg|
        expect(msg).to be_a(String)
        expect(msg).not_to be_empty
      end
    end

    it ".message returns correct message" do
      expect(described_class.message("V001")).to eq("Required field missing")
    end
  end

  describe Odin::Errors::ParseError do
    it "includes code, line, column" do
      err = described_class.new("P001", 10, 5)
      expect(err.code).to eq("P001")
      expect(err.line).to eq(10)
      expect(err.column).to eq(5)
      expect(err.message).to include("P001")
      expect(err.message).to include("line 10")
      expect(err.message).to include("column 5")
    end

    it "includes detail when provided" do
      err = described_class.new("P004", 1, 1, "expected closing quote")
      expect(err.message).to include("expected closing quote")
    end

    it "is a StandardError" do
      expect(described_class.new("P001", 1, 1)).to be_a(StandardError)
    end
  end

  describe Odin::Errors::ValidationError do
    it "stores all fields" do
      err = described_class.new(
        code: "V001", path: "name", message: "Required",
        expected: "string", actual: nil, schema_path: "$.name"
      )
      expect(err.code).to eq("V001")
      expect(err.path).to eq("name")
      expect(err.message).to eq("Required")
      expect(err.expected).to eq("string")
      expect(err.actual).to be_nil
      expect(err.schema_path).to eq("$.name")
    end

    it "to_s includes code and path" do
      err = described_class.new(code: "V002", path: "age", message: "Type mismatch")
      expect(err.to_s).to include("V002")
      expect(err.to_s).to include("age")
    end
  end

  describe Odin::Errors::ValidationResult do
    it ".valid returns valid result" do
      r = described_class.valid
      expect(r.valid?).to be true
      expect(r.errors).to be_empty
    end

    it ".with_errors returns invalid result" do
      errs = [Odin::Errors::ValidationError.new(code: "V001", path: "x", message: "missing")]
      r = described_class.with_errors(errs)
      expect(r.valid?).to be false
      expect(r.errors.size).to eq(1)
    end
  end

  describe Odin::Errors::PatchError do
    it "stores path and message" do
      err = described_class.new("conflict", "a.b.c")
      expect(err.path).to eq("a.b.c")
      expect(err.message).to include("conflict")
      expect(err.message).to include("a.b.c")
    end
  end
end
