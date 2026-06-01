# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Odin::Validation::FormatValidators do
  # ── Email ──

  describe "email validation" do
    it "validates simple email" do
      expect(described_class.validate("email", "user@example.com")).to be true
    end

    it "validates email with dots in local part" do
      expect(described_class.validate("email", "first.last@example.com")).to be true
    end

    it "validates email with plus sign" do
      expect(described_class.validate("email", "user+tag@example.com")).to be true
    end

    it "rejects email without @" do
      expect(described_class.validate("email", "userexample.com")).to be false
    end

    it "rejects email without domain" do
      expect(described_class.validate("email", "user@")).to be false
    end

    it "rejects email without domain dot" do
      expect(described_class.validate("email", "user@localhost")).to be false
    end

    it "rejects empty string" do
      expect(described_class.validate("email", "")).to be false
    end

    it "rejects email with spaces" do
      expect(described_class.validate("email", "user @example.com")).to be false
    end
  end

  # ── URI ──

  describe "URI validation" do
    it "validates http URI" do
      expect(described_class.validate("uri", "http://example.com")).to be true
    end

    it "validates https URI" do
      expect(described_class.validate("uri", "https://example.com/path")).to be true
    end

    it "validates ftp URI" do
      expect(described_class.validate("uri", "ftp://files.example.com")).to be true
    end

    it "validates mailto URI" do
      expect(described_class.validate("uri", "mailto:user@example.com")).to be true
    end

    it "rejects missing scheme" do
      expect(described_class.validate("uri", "example.com")).to be false
    end

    it "validates urn URI" do
      expect(described_class.validate("uri", "urn:isbn:0451450523")).to be true
    end

    it "rejects relative path without scheme" do
      expect(described_class.validate("uri", "/relative/path")).to be false
    end

    it "rejects URI containing whitespace" do
      expect(described_class.validate("uri", "http://exa mple.com")).to be false
    end
  end

  # ── UUID ──

  describe "UUID validation" do
    it "validates standard UUID" do
      expect(described_class.validate("uuid", "550e8400-e29b-41d4-a716-446655440000")).to be true
    end

    it "validates uppercase UUID" do
      expect(described_class.validate("uuid", "550E8400-E29B-41D4-A716-446655440000")).to be true
    end

    it "rejects wrong length" do
      expect(described_class.validate("uuid", "550e8400-e29b-41d4")).to be false
    end

    it "rejects missing dashes" do
      expect(described_class.validate("uuid", "550e8400e29b41d4a716446655440000")).to be false
    end
  end

  # ── IPv4 ──

  describe "IPv4 validation" do
    it "validates 192.168.1.1" do
      expect(described_class.validate("ipv4", "192.168.1.1")).to be true
    end

    it "validates 0.0.0.0" do
      expect(described_class.validate("ipv4", "0.0.0.0")).to be true
    end

    it "validates 255.255.255.255" do
      expect(described_class.validate("ipv4", "255.255.255.255")).to be true
    end

    it "rejects 256.0.0.0" do
      expect(described_class.validate("ipv4", "256.0.0.0")).to be false
    end

    it "rejects non-numeric" do
      expect(described_class.validate("ipv4", "abc.def.ghi.jkl")).to be false
    end

    it "rejects too few octets" do
      expect(described_class.validate("ipv4", "192.168.1")).to be false
    end

    it "rejects too many octets" do
      expect(described_class.validate("ipv4", "192.168.1.1.1")).to be false
    end
  end

  # ── IPv6 ──

  describe "IPv6 validation" do
    it "validates ::1 (loopback)" do
      expect(described_class.validate("ipv6", "::1")).to be true
    end

    it "validates full address" do
      expect(described_class.validate("ipv6", "2001:0db8:85a3:0000:0000:8a2e:0370:7334")).to be true
    end

    it "validates fe80::" do
      expect(described_class.validate("ipv6", "fe80::")).to be true
    end

    it "rejects non-hex characters" do
      expect(described_class.validate("ipv6", "xyz::1")).to be false
    end
  end

  # ── Hostname ──

  describe "hostname validation" do
    it "validates simple hostname" do
      expect(described_class.validate("hostname", "example.com")).to be true
    end

    it "validates subdomain" do
      expect(described_class.validate("hostname", "sub.example.com")).to be true
    end

    it "validates single label" do
      expect(described_class.validate("hostname", "localhost")).to be true
    end

    it "rejects too long hostname" do
      long = "a" * 254
      expect(described_class.validate("hostname", long)).to be false
    end
  end

  # ── Date/Time formats ──

  describe "date format validation" do
    it "validates ISO date" do
      expect(described_class.validate("date", "2024-01-15")).to be true
    end

    it "rejects non-date string" do
      expect(described_class.validate("date", "not-a-date")).to be false
    end

    it "rejects partial date" do
      expect(described_class.validate("date", "2024-01")).to be false
    end
  end

  describe "datetime format validation" do
    it "validates ISO datetime" do
      expect(described_class.validate("date-time", "2024-01-15T10:30:00Z")).to be true
    end

    it "validates datetime alias" do
      expect(described_class.validate("datetime", "2024-01-15T10:30:00Z")).to be true
    end

    it "rejects non-datetime" do
      expect(described_class.validate("date-time", "not-a-datetime")).to be false
    end
  end

  describe "time format validation" do
    it "validates HH:MM:SS" do
      expect(described_class.validate("time", "10:30:00")).to be true
    end

    it "validates HH:MM" do
      expect(described_class.validate("time", "10:30")).to be true
    end

    it "validates with T prefix" do
      expect(described_class.validate("time", "T10:30:00")).to be true
    end

    it "rejects non-time" do
      expect(described_class.validate("time", "not-time")).to be false
    end
  end

  describe "duration format validation" do
    it "validates P6M" do
      expect(described_class.validate("duration", "P6M")).to be true
    end

    it "validates P1Y2M3D" do
      expect(described_class.validate("duration", "P1Y2M3D")).to be true
    end

    it "validates PT1H30M" do
      expect(described_class.validate("duration", "PT1H30M")).to be true
    end

    it "rejects non-duration" do
      expect(described_class.validate("duration", "6 months")).to be false
    end
  end

  # ── Specialized formats ──

  describe "SSN validation" do
    it "validates proper SSN" do
      expect(described_class.validate("ssn", "123-45-6789")).to be true
    end

    it "rejects wrong format" do
      expect(described_class.validate("ssn", "12345-6789")).to be false
    end
  end

  describe "EIN validation" do
    it "validates proper EIN" do
      expect(described_class.validate("ein", "12-3456789")).to be true
    end

    it "rejects wrong format" do
      expect(described_class.validate("ein", "123456789")).to be false
    end
  end

  describe "ZIP validation" do
    it "validates 5-digit ZIP" do
      expect(described_class.validate("zip", "12345")).to be true
    end

    it "validates ZIP+4" do
      expect(described_class.validate("zip", "12345-6789")).to be true
    end

    it "rejects wrong format" do
      expect(described_class.validate("zip", "1234")).to be false
    end
  end

  describe "VIN validation" do
    it "validates proper VIN" do
      expect(described_class.validate("vin", "1HGBH41JXMN109186")).to be true
    end

    it "rejects wrong length" do
      expect(described_class.validate("vin", "1HGBH41J")).to be false
    end
  end

  describe "phone validation" do
    it "validates international format" do
      expect(described_class.validate("phone", "+1-555-555-5555")).to be true
    end

    it "validates simple format" do
      expect(described_class.validate("phone", "555-555-5555")).to be true
    end
  end

  describe "hostname extended validation" do
    it "rejects label starting with hyphen" do
      expect(described_class.validate("hostname", "-bad.example.com")).to be false
    end

    it "rejects underscore" do
      expect(described_class.validate("hostname", "bad_underscore.com")).to be false
    end
  end

  describe "datetime extended validation" do
    it "validates datetime without zone" do
      expect(described_class.validate("datetime", "2024-06-15T10:30:00")).to be true
    end

    it "rejects space separator" do
      expect(described_class.validate("datetime", "2024-06-15 10:30:00")).to be false
    end

    it "rejects date-only value" do
      expect(described_class.validate("datetime", "2024-06-15")).to be false
    end

    it "rejects slash date for date-time alias" do
      expect(described_class.validate("date-time", "06/15/2024")).to be false
    end
  end

  describe "credit-card validation" do
    it "validates a number passing Luhn" do
      expect(described_class.validate("credit-card", "4111111111111111")).to be true
    end

    it "rejects a number failing Luhn" do
      expect(described_class.validate("credit-card", "4111111111111112")).to be false
    end

    it "rejects fewer than 13 digits" do
      expect(described_class.validate("credit-card", "411111111111")).to be false
    end

    it "rejects digits with spaces" do
      expect(described_class.validate("credit-card", "4111 1111 1111 1111")).to be false
    end
  end

  describe "IBAN validation" do
    it "validates GB IBAN" do
      expect(described_class.validate("iban", "GB82WEST12345698765432")).to be true
    end

    it "validates DE IBAN" do
      expect(described_class.validate("iban", "DE89370400440532013000")).to be true
    end

    it "rejects IBAN without leading country letters" do
      expect(described_class.validate("iban", "1234WEST")).to be false
    end
  end

  describe "BIC/SWIFT validation" do
    it "validates 8-character BIC" do
      expect(described_class.validate("bic", "DEUTDEFF")).to be true
    end

    it "validates 11-character BIC" do
      expect(described_class.validate("bic", "DEUTDEFF500")).to be true
    end

    it "rejects 9-character BIC" do
      expect(described_class.validate("bic", "DEUTDEFF5")).to be false
    end

    it "validates SWIFT alias" do
      expect(described_class.validate("swift", "BOFAUS3N")).to be true
    end

    it "rejects too-short SWIFT" do
      expect(described_class.validate("swift", "BOFAUS3")).to be false
    end
  end

  describe "routing validation" do
    it "validates 9-digit routing number" do
      expect(described_class.validate("routing", "021000021")).to be true
    end

    it "rejects 8-digit routing number" do
      expect(described_class.validate("routing", "12345678")).to be false
    end
  end

  describe "CUSIP validation" do
    it "validates 9-character CUSIP" do
      expect(described_class.validate("cusip", "037833100")).to be true
    end

    it "rejects too-short CUSIP" do
      expect(described_class.validate("cusip", "03783310")).to be false
    end

    it "rejects CUSIP with symbol" do
      expect(described_class.validate("cusip", "037833$00")).to be false
    end
  end

  describe "ISIN validation" do
    it "validates ISIN" do
      expect(described_class.validate("isin", "US0378331005")).to be true
    end

    it "rejects too-short ISIN" do
      expect(described_class.validate("isin", "US037833100")).to be false
    end

    it "rejects ISIN with non-digit check character" do
      expect(described_class.validate("isin", "US037833100X")).to be false
    end
  end

  describe "LEI validation" do
    it "validates 20-character LEI" do
      expect(described_class.validate("lei", "529900T8BM49AURSDO55")).to be true
    end

    it "validates LEI ending in letters" do
      expect(described_class.validate("lei", "529900T8BM49AURSDOAB")).to be true
    end

    it "rejects too-short LEI" do
      expect(described_class.validate("lei", "529900T8BM49AURSDO5")).to be false
    end

    it "rejects LEI with symbol" do
      expect(described_class.validate("lei", "529900T8BM49AURSDO5$")).to be false
    end
  end

  describe "NPI validation" do
    it "validates 10-digit NPI" do
      expect(described_class.validate("npi", "1234567890")).to be true
    end

    it "rejects 9-digit NPI" do
      expect(described_class.validate("npi", "123456789")).to be false
    end

    it "rejects 11-digit NPI" do
      expect(described_class.validate("npi", "12345678901")).to be false
    end
  end

  describe "DEA validation" do
    it "validates DEA number" do
      expect(described_class.validate("dea", "AB1234567")).to be true
    end

    it "rejects single leading letter" do
      expect(described_class.validate("dea", "A1234567")).to be false
    end

    it "rejects too few digits" do
      expect(described_class.validate("dea", "AB123456")).to be false
    end
  end

  describe "IMEI validation" do
    it "validates 15-digit IMEI" do
      expect(described_class.validate("imei", "490154203237518")).to be true
    end

    it "rejects 14-digit IMEI" do
      expect(described_class.validate("imei", "49015420323751")).to be false
    end

    it "rejects 16-digit IMEI" do
      expect(described_class.validate("imei", "4901542032375189")).to be false
    end
  end

  describe "ICCID validation" do
    it "validates 19-digit ICCID" do
      expect(described_class.validate("iccid", "8901234567890123456")).to be true
    end

    it "validates 20-digit ICCID" do
      expect(described_class.validate("iccid", "89012345678901234567")).to be true
    end

    it "rejects 18-digit ICCID" do
      expect(described_class.validate("iccid", "890123456789012345")).to be false
    end

    it "rejects ICCID with a letter" do
      expect(described_class.validate("iccid", "8901234567890123456X")).to be false
    end
  end

  # ── Unknown format ──

  describe "unknown format" do
    it "returns true for unknown format name" do
      expect(described_class.validate("custom_format", "anything")).to be true
    end

    it "returns true for empty format name" do
      expect(described_class.validate("", "anything")).to be true
    end
  end

  # ── known? ──

  describe ".known?" do
    it "returns true for known format" do
      expect(described_class.known?("email")).to be true
    end

    it "returns false for unknown format" do
      expect(described_class.known?("custom")).to be false
    end
  end

  # ── Non-string input ──

  describe "non-string input" do
    it "returns false for non-string" do
      expect(described_class.validate("email", 42)).to be false
    end

    it "returns false for nil" do
      expect(described_class.validate("email", nil)).to be false
    end
  end
end
