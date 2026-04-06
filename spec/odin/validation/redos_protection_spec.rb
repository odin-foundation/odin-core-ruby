# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Odin::Validation::ReDoSProtection do
  # ── Safe patterns ──

  describe "safe patterns" do
    it "accepts simple pattern" do
      expect(described_class.safe?("^[a-z]+$")).to be true
    end

    it "accepts anchored digit pattern" do
      expect(described_class.safe?("^\\d{5}$")).to be true
    end

    it "accepts bounded quantifier" do
      expect(described_class.safe?("[A-Z]{3,10}")).to be true
    end

    it "accepts character class" do
      expect(described_class.safe?("[a-zA-Z0-9_]+")).to be true
    end

    it "accepts alternation without quantifier" do
      expect(described_class.safe?("cat|dog|bird")).to be true
    end

    it "accepts email-like pattern" do
      expect(described_class.safe?("^[^@]+@[^@]+\\.[^@]+$")).to be true
    end

    it "returns :safe status for safe pattern" do
      expect(described_class.check_pattern("^\\d+$")).to eq(:safe)
    end
  end

  # ── Dangerous patterns ──

  describe "dangerous patterns" do
    it "detects nested quantifiers: (a+)+" do
      expect(described_class.safe?("(a+)+")).to be false
    end

    it "detects nested quantifiers: (a*)*" do
      expect(described_class.safe?("(a*)*")).to be false
    end

    it "detects overlapping alternation with quantifier" do
      expect(described_class.safe?("(a|a)+")).to be false
    end

    it "detects greedy dot-star repeated" do
      expect(described_class.safe?("(.*)*")).to be false
    end

    it "returns :dangerous status" do
      expect(described_class.check_pattern("(a+)+")).to eq(:dangerous)
    end
  end

  # ── Too long patterns ──

  describe "pattern length" do
    it "rejects pattern exceeding max length" do
      long_pattern = "a" * 1001
      expect(described_class.safe?(long_pattern)).to be false
    end

    it "returns :too_long status" do
      long_pattern = "a" * 1001
      expect(described_class.check_pattern(long_pattern)).to eq(:too_long)
    end

    it "accepts pattern at max length" do
      pattern = "a" * 1000
      expect(described_class.safe?(pattern)).to be true
    end
  end

  # ── compile_safe ──

  describe ".compile_safe" do
    it "compiles safe pattern to Regexp" do
      regex = described_class.compile_safe("^[A-Z]{3}$")
      expect(regex).to be_a(Regexp)
      expect("ABC").to match(regex)
    end

    it "raises for dangerous pattern" do
      expect {
        described_class.compile_safe("(a+)+")
      }.to raise_error(Odin::Errors::OdinError)
    end

    it "raises for too-long pattern" do
      expect {
        described_class.compile_safe("a" * 1001)
      }.to raise_error(Odin::Errors::OdinError)
    end

    it "compiled regex matches expected strings" do
      regex = described_class.compile_safe("^\\d{5}$")
      expect("12345").to match(regex)
      expect("1234").not_to match(regex)
    end

    it "error message includes reason" do
      expect {
        described_class.compile_safe("(a+)+")
      }.to raise_error(Odin::Errors::OdinError, /dangerous/)
    end
  end

  # ── safe_test ──

  describe ".safe_test" do
    it "returns matched: true for matching value" do
      regex = Regexp.new("^\\d+$")
      result = described_class.safe_test(regex, "12345")
      expect(result[:matched]).to be true
    end

    it "returns matched: false for non-matching value" do
      regex = Regexp.new("^\\d+$")
      result = described_class.safe_test(regex, "abc")
      expect(result[:matched]).to be false
    end

    it "rejects value exceeding max length" do
      regex = Regexp.new(".*")
      long_value = "a" * 10_001
      result = described_class.safe_test(regex, long_value)
      expect(result[:reason]).to eq(:value_too_long)
    end

    it "includes execution time" do
      regex = Regexp.new("^\\d+$")
      result = described_class.safe_test(regex, "123")
      expect(result[:execution_time_ms]).to be_a(Float)
    end
  end
end
