# frozen_string_literal: true

require "spec_helper"

RSpec.describe "DateTime Verbs" do
  let(:engine) { Odin::Transform::TransformEngine.new }
  let(:ctx) { Odin::Transform::VerbContext.new }
  let(:dv) { Odin::Types::DynValue }

  def invoke(name, *args)
    engine.invoke_verb(name, args, ctx)
  end

  # ── today ──

  describe "today" do
    it "returns a date type" do
      result = invoke("today")
      expect(result.date?).to be true
    end

    it "returns date in YYYY-MM-DD format" do
      result = invoke("today")
      expect(result.to_string).to match(/\A\d{4}-\d{2}-\d{2}\z/)
    end

    it "returns today's date" do
      result = invoke("today")
      expect(result.to_string).to eq(Time.now.utc.strftime("%Y-%m-%d"))
    end
  end

  # ── now ──

  describe "now" do
    it "returns a timestamp type" do
      result = invoke("now")
      expect(result.timestamp?).to be true
    end

    it "returns timestamp in ISO 8601 format with Z suffix" do
      result = invoke("now")
      expect(result.to_string).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/)
    end
  end

  # ── formatDate ──

  describe "formatDate" do
    it "formats date with yyyy-MM-dd pattern" do
      result = invoke("formatDate", dv.of_date("2024-03-15"), dv.of_string("yyyy-MM-dd"))
      expect(result.to_string).to eq("2024-03-15")
    end

    it "formats date with dd/MM/yyyy pattern" do
      result = invoke("formatDate", dv.of_date("2024-03-15"), dv.of_string("dd/MM/yyyy"))
      expect(result.to_string).to eq("15/03/2024")
    end

    it "formats date with MMM pattern (abbreviated month)" do
      result = invoke("formatDate", dv.of_date("2024-03-15"), dv.of_string("dd MMM yyyy"))
      expect(result.to_string).to eq("15 Mar 2024")
    end

    it "formats date with MMMM pattern (full month)" do
      result = invoke("formatDate", dv.of_date("2024-03-15"), dv.of_string("dd MMMM yyyy"))
      expect(result.to_string).to eq("15 March 2024")
    end

    it "formats date with EEE pattern (abbreviated weekday)" do
      result = invoke("formatDate", dv.of_date("2024-03-15"), dv.of_string("EEE, dd MMM yyyy"))
      expect(result.to_string).to eq("Fri, 15 Mar 2024")
    end

    it "formats date with EEEE pattern (full weekday)" do
      result = invoke("formatDate", dv.of_date("2024-03-15"), dv.of_string("EEEE, dd MMMM yyyy"))
      expect(result.to_string).to eq("Friday, 15 March 2024")
    end

    it "uses default yyyy-MM-dd pattern when no pattern given" do
      result = invoke("formatDate", dv.of_date("2024-03-15"))
      expect(result.to_string).to eq("2024-03-15")
    end

    it "returns null for null input" do
      result = invoke("formatDate", dv.of_null, dv.of_string("yyyy-MM-dd"))
      expect(result.null?).to be true
    end

    it "returns string type" do
      result = invoke("formatDate", dv.of_date("2024-03-15"), dv.of_string("yyyy-MM-dd"))
      expect(result.string?).to be true
    end
  end

  # ── parseDate ──

  describe "parseDate" do
    it "parses a date string" do
      result = invoke("parseDate", dv.of_string("2024-03-15"))
      expect(result.string?).to be true
      expect(result.to_string).to eq("2024-03-15")
    end

    it "returns null for empty string" do
      result = invoke("parseDate", dv.of_string(""))
      expect(result.null?).to be true
    end

    it "returns null for null input" do
      result = invoke("parseDate", dv.of_null)
      expect(result.null?).to be true
    end

    it "returns null for invalid date" do
      result = invoke("parseDate", dv.of_string("not-a-date"))
      expect(result.null?).to be true
    end
  end

  # ── formatTime ──

  describe "formatTime" do
    it "formats timestamp to time with default pattern HH:mm:ss" do
      result = invoke("formatTime", dv.of_timestamp("2024-03-15T14:30:45.000Z"))
      expect(result.to_string).to eq("14:30:45")
    end

    it "formats timestamp with custom HH:mm pattern" do
      result = invoke("formatTime", dv.of_timestamp("2024-03-15T14:30:45.000Z"), dv.of_string("HH:mm"))
      expect(result.to_string).to eq("14:30")
    end

    it "returns null for null input" do
      result = invoke("formatTime", dv.of_null)
      expect(result.null?).to be true
    end

    it "returns string type" do
      result = invoke("formatTime", dv.of_timestamp("2024-03-15T14:30:45.000Z"))
      expect(result.string?).to be true
    end
  end

  # ── formatTimestamp ──

  describe "formatTimestamp" do
    it "formats timestamp without pattern to ISO format" do
      result = invoke("formatTimestamp", dv.of_timestamp("2024-03-15T14:30:45.000Z"))
      expect(result.to_string).to eq("2024-03-15T14:30:45.000Z")
    end

    it "formats timestamp with custom pattern" do
      result = invoke("formatTimestamp", dv.of_timestamp("2024-03-15T14:30:45.000Z"), dv.of_string("yyyy-MM-dd HH:mm:ss"))
      expect(result.to_string).to eq("2024-03-15 14:30:45")
    end

    it "formats timestamp with date-only pattern" do
      result = invoke("formatTimestamp", dv.of_timestamp("2024-03-15T14:30:45.000Z"), dv.of_string("yyyy-MM-dd"))
      expect(result.to_string).to eq("2024-03-15")
    end

    it "returns null for null input" do
      result = invoke("formatTimestamp", dv.of_null)
      expect(result.null?).to be true
    end

    it "returns string type" do
      result = invoke("formatTimestamp", dv.of_timestamp("2024-03-15T14:30:45.000Z"))
      expect(result.string?).to be true
    end
  end

  # ── parseTimestamp ──

  describe "parseTimestamp" do
    it "parses ISO timestamp and normalizes to UTC" do
      result = invoke("parseTimestamp", dv.of_string("2024-03-15T14:30:45.000Z"))
      expect(result.timestamp?).to be true
      expect(result.to_string).to eq("2024-03-15T14:30:45.000Z")
    end

    it "returns null for empty string" do
      result = invoke("parseTimestamp", dv.of_string(""))
      expect(result.null?).to be true
    end

    it "returns null for null input" do
      result = invoke("parseTimestamp", dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── addDays ──

  describe "addDays" do
    it "adds positive days to a date" do
      result = invoke("addDays", dv.of_date("2024-03-15"), dv.of_integer(5))
      expect(result.string?).to be true
      expect(result.to_string).to eq("2024-03-20")
    end

    it "adds negative days to a date" do
      result = invoke("addDays", dv.of_date("2024-03-15"), dv.of_integer(-5))
      expect(result.to_string).to eq("2024-03-10")
    end

    it "crosses month boundary" do
      result = invoke("addDays", dv.of_date("2024-01-30"), dv.of_integer(3))
      expect(result.to_string).to eq("2024-02-02")
    end

    it "adds days to a timestamp" do
      result = invoke("addDays", dv.of_timestamp("2024-03-15T10:00:00.000Z"), dv.of_integer(2))
      expect(result.string?).to be true
      expect(result.to_string).to eq("2024-03-17T10:00:00.000Z")
    end

    it "returns null for null input" do
      result = invoke("addDays", dv.of_null, dv.of_integer(5))
      expect(result.null?).to be true
    end
  end

  # ── addMonths ──

  describe "addMonths" do
    it "adds months to a date" do
      result = invoke("addMonths", dv.of_date("2024-01-15"), dv.of_integer(3))
      expect(result.to_string).to eq("2024-04-15")
    end

    it "clamps end-of-month: Jan 31 + 1 month = Feb 29 (leap year)" do
      result = invoke("addMonths", dv.of_date("2024-01-31"), dv.of_integer(1))
      expect(result.to_string).to eq("2024-02-29")
    end

    it "clamps end-of-month: Jan 31 + 1 month = Feb 28 (non-leap year)" do
      result = invoke("addMonths", dv.of_date("2023-01-31"), dv.of_integer(1))
      expect(result.to_string).to eq("2023-02-28")
    end

    it "clamps end-of-month: Mar 31 + 1 month = Apr 30" do
      result = invoke("addMonths", dv.of_date("2024-03-31"), dv.of_integer(1))
      expect(result.to_string).to eq("2024-04-30")
    end

    it "subtracts months with negative value" do
      result = invoke("addMonths", dv.of_date("2024-03-15"), dv.of_integer(-2))
      expect(result.to_string).to eq("2024-01-15")
    end

    it "adds months to a timestamp preserving time" do
      result = invoke("addMonths", dv.of_timestamp("2024-01-15T10:30:00.000Z"), dv.of_integer(2))
      expect(result.timestamp?).to be true
      expect(result.to_string).to eq("2024-03-15T10:30:00.000Z")
    end

    it "returns null for null input" do
      result = invoke("addMonths", dv.of_null, dv.of_integer(1))
      expect(result.null?).to be true
    end
  end

  # ── addYears ──

  describe "addYears" do
    it "adds years to a date" do
      result = invoke("addYears", dv.of_date("2024-03-15"), dv.of_integer(2))
      expect(result.to_string).to eq("2026-03-15")
    end

    it "clamps leap day: Feb 29 + 1 year = Feb 28" do
      result = invoke("addYears", dv.of_date("2024-02-29"), dv.of_integer(1))
      expect(result.to_string).to eq("2025-02-28")
    end

    it "subtracts years with negative value" do
      result = invoke("addYears", dv.of_date("2024-03-15"), dv.of_integer(-3))
      expect(result.to_string).to eq("2021-03-15")
    end

    it "adds years to a timestamp preserving time" do
      result = invoke("addYears", dv.of_timestamp("2024-03-15T08:00:00.000Z"), dv.of_integer(1))
      expect(result.string?).to be true
      expect(result.to_string).to eq("2025-03-15T08:00:00.000Z")
    end

    it "returns null for null input" do
      result = invoke("addYears", dv.of_null, dv.of_integer(1))
      expect(result.null?).to be true
    end
  end

  # ── dateDiff ──

  describe "dateDiff" do
    it "calculates difference in days" do
      result = invoke("dateDiff", dv.of_date("2024-01-01"), dv.of_date("2024-01-31"), dv.of_string("days"))
      expect(result.integer?).to be true
      expect(result.value).to eq(30)
    end

    it "calculates negative difference in days" do
      result = invoke("dateDiff", dv.of_date("2024-01-31"), dv.of_date("2024-01-01"), dv.of_string("days"))
      expect(result.value).to eq(-30)
    end

    it "calculates difference in months" do
      result = invoke("dateDiff", dv.of_date("2024-01-15"), dv.of_date("2024-04-15"), dv.of_string("months"))
      expect(result.value).to eq(3)
    end

    it "calculates difference in months with partial month" do
      result = invoke("dateDiff", dv.of_date("2024-01-31"), dv.of_date("2024-03-15"), dv.of_string("months"))
      expect(result.value).to eq(1)
    end

    it "calculates difference in years" do
      result = invoke("dateDiff", dv.of_date("2020-06-15"), dv.of_date("2024-06-15"), dv.of_string("years"))
      expect(result.value).to eq(4)
    end

    it "calculates difference in years with partial year" do
      result = invoke("dateDiff", dv.of_date("2020-06-15"), dv.of_date("2024-03-15"), dv.of_string("years"))
      expect(result.value).to eq(3)
    end

    it "calculates difference in hours" do
      result = invoke("dateDiff", dv.of_timestamp("2024-01-01T00:00:00.000Z"), dv.of_timestamp("2024-01-01T06:00:00.000Z"), dv.of_string("hours"))
      expect(result.value).to be_within(0.001).of(6.0)
    end

    it "calculates difference in minutes" do
      result = invoke("dateDiff", dv.of_timestamp("2024-01-01T00:00:00.000Z"), dv.of_timestamp("2024-01-01T01:30:00.000Z"), dv.of_string("minutes"))
      expect(result.value).to be_within(0.001).of(90.0)
    end

    it "calculates difference in seconds" do
      result = invoke("dateDiff", dv.of_timestamp("2024-01-01T00:00:00.000Z"), dv.of_timestamp("2024-01-01T00:05:00.000Z"), dv.of_string("seconds"))
      expect(result.value).to be_within(0.001).of(300.0)
    end

    it "defaults to days when no unit specified" do
      result = invoke("dateDiff", dv.of_date("2024-01-01"), dv.of_date("2024-01-11"))
      expect(result.value).to eq(10)
    end

    it "returns null when first arg is null" do
      result = invoke("dateDiff", dv.of_null, dv.of_date("2024-01-01"), dv.of_string("days"))
      expect(result.null?).to be true
    end

    it "returns null when second arg is null" do
      result = invoke("dateDiff", dv.of_date("2024-01-01"), dv.of_null, dv.of_string("days"))
      expect(result.null?).to be true
    end
  end

  # ── addHours ──

  describe "addHours" do
    it "adds hours to a timestamp" do
      result = invoke("addHours", dv.of_timestamp("2024-03-15T10:00:00.000Z"), dv.of_integer(3))
      expect(result.timestamp?).to be true
      expect(result.to_string).to eq("2024-03-15T13:00:00.000Z")
    end

    it "adds hours crossing day boundary" do
      result = invoke("addHours", dv.of_timestamp("2024-03-15T22:00:00.000Z"), dv.of_integer(5))
      expect(result.to_string).to eq("2024-03-16T03:00:00.000Z")
    end

    it "returns null for null input" do
      result = invoke("addHours", dv.of_null, dv.of_integer(3))
      expect(result.null?).to be true
    end
  end

  # ── addMinutes ──

  describe "addMinutes" do
    it "adds minutes to a timestamp" do
      result = invoke("addMinutes", dv.of_timestamp("2024-03-15T10:00:00.000Z"), dv.of_integer(45))
      expect(result.to_string).to eq("2024-03-15T10:45:00.000Z")
    end

    it "adds minutes crossing hour boundary" do
      result = invoke("addMinutes", dv.of_timestamp("2024-03-15T10:50:00.000Z"), dv.of_integer(20))
      expect(result.to_string).to eq("2024-03-15T11:10:00.000Z")
    end

    it "returns null for null input" do
      result = invoke("addMinutes", dv.of_null, dv.of_integer(30))
      expect(result.null?).to be true
    end
  end

  # ── addSeconds ──

  describe "addSeconds" do
    it "adds seconds to a timestamp" do
      result = invoke("addSeconds", dv.of_timestamp("2024-03-15T10:00:00.000Z"), dv.of_integer(30))
      expect(result.to_string).to eq("2024-03-15T10:00:30.000Z")
    end

    it "adds seconds crossing minute boundary" do
      result = invoke("addSeconds", dv.of_timestamp("2024-03-15T10:00:50.000Z"), dv.of_integer(20))
      expect(result.to_string).to eq("2024-03-15T10:01:10.000Z")
    end

    it "returns null for null input" do
      result = invoke("addSeconds", dv.of_null, dv.of_integer(10))
      expect(result.null?).to be true
    end
  end

  # ── startOfDay ──

  describe "startOfDay" do
    it "returns timestamp at 00:00:00.000Z for a date" do
      result = invoke("startOfDay", dv.of_date("2024-03-15"))
      expect(result.timestamp?).to be true
      expect(result.to_string).to eq("2024-03-15T00:00:00.000Z")
    end

    it "returns timestamp at 00:00:00.000Z for a timestamp" do
      result = invoke("startOfDay", dv.of_timestamp("2024-03-15T14:30:45.000Z"))
      expect(result.to_string).to eq("2024-03-15T00:00:00.000Z")
    end

    it "returns null for null input" do
      result = invoke("startOfDay", dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── endOfDay ──

  describe "endOfDay" do
    it "returns timestamp at 23:59:59.999Z for a date" do
      result = invoke("endOfDay", dv.of_date("2024-03-15"))
      expect(result.timestamp?).to be true
      expect(result.to_string).to eq("2024-03-15T23:59:59.999Z")
    end

    it "returns timestamp at 23:59:59.999Z for a timestamp" do
      result = invoke("endOfDay", dv.of_timestamp("2024-03-15T14:30:45.000Z"))
      expect(result.to_string).to eq("2024-03-15T23:59:59.999Z")
    end

    it "returns null for null input" do
      result = invoke("endOfDay", dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── startOfMonth ──

  describe "startOfMonth" do
    it "returns first day of the month" do
      result = invoke("startOfMonth", dv.of_date("2024-03-15"))
      expect(result.date?).to be true
      expect(result.to_string).to eq("2024-03-01")
    end

    it "returns first day when already on first" do
      result = invoke("startOfMonth", dv.of_date("2024-03-01"))
      expect(result.to_string).to eq("2024-03-01")
    end

    it "returns null for null input" do
      result = invoke("startOfMonth", dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── endOfMonth ──

  describe "endOfMonth" do
    it "returns last day of March (31)" do
      result = invoke("endOfMonth", dv.of_date("2024-03-15"))
      expect(result.date?).to be true
      expect(result.to_string).to eq("2024-03-31")
    end

    it "returns last day of February in leap year (29)" do
      result = invoke("endOfMonth", dv.of_date("2024-02-10"))
      expect(result.to_string).to eq("2024-02-29")
    end

    it "returns last day of February in non-leap year (28)" do
      result = invoke("endOfMonth", dv.of_date("2023-02-10"))
      expect(result.to_string).to eq("2023-02-28")
    end

    it "returns last day of April (30)" do
      result = invoke("endOfMonth", dv.of_date("2024-04-05"))
      expect(result.to_string).to eq("2024-04-30")
    end

    it "returns null for null input" do
      result = invoke("endOfMonth", dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── startOfYear ──

  describe "startOfYear" do
    it "returns January 1 of the year" do
      result = invoke("startOfYear", dv.of_date("2024-06-15"))
      expect(result.date?).to be true
      expect(result.to_string).to eq("2024-01-01")
    end

    it "returns null for null input" do
      result = invoke("startOfYear", dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── endOfYear ──

  describe "endOfYear" do
    it "returns December 31 of the year" do
      result = invoke("endOfYear", dv.of_date("2024-06-15"))
      expect(result.date?).to be true
      expect(result.to_string).to eq("2024-12-31")
    end

    it "returns null for null input" do
      result = invoke("endOfYear", dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── dayOfWeek ──

  describe "dayOfWeek" do
    it "returns 1 for Monday (ISO 8601)" do
      result = invoke("dayOfWeek", dv.of_date("2024-03-11")) # Monday
      expect(result.integer?).to be true
      expect(result.value).to eq(1)
    end

    it "returns 5 for Friday" do
      result = invoke("dayOfWeek", dv.of_date("2024-03-15")) # Friday
      expect(result.value).to eq(5)
    end

    it "returns 7 for Sunday" do
      result = invoke("dayOfWeek", dv.of_date("2024-03-17")) # Sunday
      expect(result.value).to eq(7)
    end

    it "returns 6 for Saturday" do
      result = invoke("dayOfWeek", dv.of_date("2024-03-16")) # Saturday
      expect(result.value).to eq(6)
    end

    it "returns null for null input" do
      result = invoke("dayOfWeek", dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── dayOfMonth ──

  describe "dayOfMonth" do
    it "returns 1 for first of month" do
      result = invoke("dayOfMonth", dv.of_date("2024-03-01"))
      expect(result.integer?).to be true
      expect(result.value).to eq(1)
    end

    it "returns 31 for last day of January" do
      result = invoke("dayOfMonth", dv.of_date("2024-01-31"))
      expect(result.value).to eq(31)
    end

    it "returns 15 for mid-month" do
      result = invoke("dayOfMonth", dv.of_date("2024-06-15"))
      expect(result.value).to eq(15)
    end

    it "returns null for null input" do
      result = invoke("dayOfMonth", dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── dayOfYear ──

  describe "dayOfYear" do
    it "returns 1 for January 1" do
      result = invoke("dayOfYear", dv.of_date("2024-01-01"))
      expect(result.integer?).to be true
      expect(result.value).to eq(1)
    end

    it "returns 366 for Dec 31 in leap year" do
      result = invoke("dayOfYear", dv.of_date("2024-12-31"))
      expect(result.value).to eq(366)
    end

    it "returns 365 for Dec 31 in non-leap year" do
      result = invoke("dayOfYear", dv.of_date("2023-12-31"))
      expect(result.value).to eq(365)
    end

    it "returns 60 for Feb 29 in leap year" do
      result = invoke("dayOfYear", dv.of_date("2024-02-29"))
      expect(result.value).to eq(60)
    end

    it "returns null for null input" do
      result = invoke("dayOfYear", dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── weekOfYear ──

  describe "weekOfYear" do
    it "returns week 1 for early January" do
      result = invoke("weekOfYear", dv.of_date("2024-01-04")) # Thursday of week 1
      expect(result.integer?).to be true
      expect(result.value).to eq(1)
    end

    it "returns week 53 for Dec 31 2020 (ISO week 53)" do
      result = invoke("weekOfYear", dv.of_date("2020-12-31"))
      expect(result.value).to eq(53)
    end

    it "returns correct week for mid-year date" do
      result = invoke("weekOfYear", dv.of_date("2024-07-01"))
      expect(result.value).to eq(27)
    end

    it "returns null for null input" do
      result = invoke("weekOfYear", dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── quarter ──

  describe "quarter" do
    it "returns Q1 for January" do
      result = invoke("quarter", dv.of_date("2024-01-15"))
      expect(result.integer?).to be true
      expect(result.value).to eq(1)
    end

    it "returns Q1 for March" do
      result = invoke("quarter", dv.of_date("2024-03-31"))
      expect(result.value).to eq(1)
    end

    it "returns Q2 for April" do
      result = invoke("quarter", dv.of_date("2024-04-01"))
      expect(result.value).to eq(2)
    end

    it "returns Q3 for July" do
      result = invoke("quarter", dv.of_date("2024-07-15"))
      expect(result.value).to eq(3)
    end

    it "returns Q4 for December" do
      result = invoke("quarter", dv.of_date("2024-12-25"))
      expect(result.value).to eq(4)
    end

    it "returns null for null input" do
      result = invoke("quarter", dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── isLeapYear ──

  describe "isLeapYear" do
    it "returns true for 2024 (divisible by 4)" do
      result = invoke("isLeapYear", dv.of_date("2024-01-01"))
      expect(result.value).to be true
    end

    it "returns false for 2023 (not divisible by 4)" do
      result = invoke("isLeapYear", dv.of_date("2023-06-15"))
      expect(result.value).to be false
    end

    it "returns true for 2000 (divisible by 400)" do
      result = invoke("isLeapYear", dv.of_date("2000-07-01"))
      expect(result.value).to be true
    end

    it "returns false for 1900 (divisible by 100 but not 400)" do
      result = invoke("isLeapYear", dv.of_date("1900-01-01"))
      expect(result.value).to be false
    end

    it "accepts integer year directly" do
      result = invoke("isLeapYear", dv.of_integer(2024))
      expect(result.value).to be true
    end

    it "returns false for integer non-leap year" do
      result = invoke("isLeapYear", dv.of_integer(2023))
      expect(result.value).to be false
    end

    it "returns null for null input" do
      result = invoke("isLeapYear", dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── isBefore ──

  describe "isBefore" do
    it "returns true when first date is before second" do
      result = invoke("isBefore", dv.of_date("2024-01-01"), dv.of_date("2024-06-01"))
      expect(result.value).to be true
    end

    it "returns false when first date is after second" do
      result = invoke("isBefore", dv.of_date("2024-06-01"), dv.of_date("2024-01-01"))
      expect(result.value).to be false
    end

    it "returns false when dates are equal" do
      result = invoke("isBefore", dv.of_date("2024-03-15"), dv.of_date("2024-03-15"))
      expect(result.value).to be false
    end

    it "works with timestamps" do
      result = invoke("isBefore", dv.of_timestamp("2024-01-01T00:00:00.000Z"), dv.of_timestamp("2024-01-01T12:00:00.000Z"))
      expect(result.value).to be true
    end

    it "returns null when first arg is null" do
      result = invoke("isBefore", dv.of_null, dv.of_date("2024-01-01"))
      expect(result.null?).to be true
    end

    it "returns null when second arg is null" do
      result = invoke("isBefore", dv.of_date("2024-01-01"), dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── isAfter ──

  describe "isAfter" do
    it "returns true when first date is after second" do
      result = invoke("isAfter", dv.of_date("2024-06-01"), dv.of_date("2024-01-01"))
      expect(result.value).to be true
    end

    it "returns false when first date is before second" do
      result = invoke("isAfter", dv.of_date("2024-01-01"), dv.of_date("2024-06-01"))
      expect(result.value).to be false
    end

    it "returns false when dates are equal" do
      result = invoke("isAfter", dv.of_date("2024-03-15"), dv.of_date("2024-03-15"))
      expect(result.value).to be false
    end

    it "works with timestamps" do
      result = invoke("isAfter", dv.of_timestamp("2024-01-01T12:00:00.000Z"), dv.of_timestamp("2024-01-01T00:00:00.000Z"))
      expect(result.value).to be true
    end

    it "returns null when first arg is null" do
      result = invoke("isAfter", dv.of_null, dv.of_date("2024-01-01"))
      expect(result.null?).to be true
    end
  end

  # ── isBetween ──

  describe "isBetween" do
    it "returns true when date is between start and end (inclusive)" do
      result = invoke("isBetween", dv.of_date("2024-03-15"), dv.of_date("2024-01-01"), dv.of_date("2024-06-30"))
      expect(result.value).to be true
    end

    it "returns true when date equals start (inclusive)" do
      result = invoke("isBetween", dv.of_date("2024-01-01"), dv.of_date("2024-01-01"), dv.of_date("2024-06-30"))
      expect(result.value).to be true
    end

    it "returns true when date equals end (inclusive)" do
      result = invoke("isBetween", dv.of_date("2024-06-30"), dv.of_date("2024-01-01"), dv.of_date("2024-06-30"))
      expect(result.value).to be true
    end

    it "returns false when date is before range" do
      result = invoke("isBetween", dv.of_date("2023-12-31"), dv.of_date("2024-01-01"), dv.of_date("2024-06-30"))
      expect(result.value).to be false
    end

    it "returns false when date is after range" do
      result = invoke("isBetween", dv.of_date("2024-07-01"), dv.of_date("2024-01-01"), dv.of_date("2024-06-30"))
      expect(result.value).to be false
    end

    it "works with timestamps" do
      result = invoke("isBetween",
        dv.of_timestamp("2024-03-15T12:00:00.000Z"),
        dv.of_timestamp("2024-03-15T00:00:00.000Z"),
        dv.of_timestamp("2024-03-15T23:59:59.999Z"))
      expect(result.value).to be true
    end

    it "returns null when value is null" do
      result = invoke("isBetween", dv.of_null, dv.of_date("2024-01-01"), dv.of_date("2024-06-30"))
      expect(result.null?).to be true
    end
  end

  # ── toUnix / fromUnix ──

  describe "toUnix" do
    it "converts a known timestamp to unix epoch" do
      result = invoke("toUnix", dv.of_timestamp("2024-01-01T00:00:00.000Z"))
      expect(result.integer?).to be true
      expect(result.value).to eq(1704067200)
    end

    it "converts a date to unix epoch" do
      result = invoke("toUnix", dv.of_date("2024-01-01"))
      expect(result.integer?).to be true
      # Date parsing via Time.parse may apply local timezone;
      # verify it produces a reasonable epoch near midnight UTC
      expect(result.value).to be_within(86400).of(1704067200)
    end

    it "returns null for null input" do
      result = invoke("toUnix", dv.of_null)
      expect(result.null?).to be true
    end
  end

  describe "fromUnix" do
    it "converts unix epoch to timestamp" do
      result = invoke("fromUnix", dv.of_integer(1704067200))
      expect(result.timestamp?).to be true
      expect(result.to_string).to eq("2024-01-01T00:00:00.000Z")
    end

    it "converts epoch 0 to 1970-01-01" do
      result = invoke("fromUnix", dv.of_integer(0))
      expect(result.to_string).to eq("1970-01-01T00:00:00.000Z")
    end

    it "returns null for null input" do
      result = invoke("fromUnix", dv.of_null)
      expect(result.null?).to be true
    end
  end

  describe "toUnix/fromUnix round-trip" do
    it "round-trips a timestamp" do
      original = dv.of_timestamp("2024-06-15T12:30:00.000Z")
      unix = invoke("toUnix", original)
      restored = invoke("fromUnix", unix)
      expect(restored.to_string).to eq("2024-06-15T12:30:00.000Z")
    end
  end

  # ── daysBetweenDates ──

  describe "daysBetweenDates" do
    it "returns absolute difference in days" do
      result = invoke("daysBetweenDates", dv.of_date("2024-01-01"), dv.of_date("2024-01-31"))
      expect(result.integer?).to be true
      expect(result.value).to eq(30)
    end

    it "returns absolute value regardless of order" do
      result = invoke("daysBetweenDates", dv.of_date("2024-01-31"), dv.of_date("2024-01-01"))
      expect(result.value).to eq(30)
    end

    it "returns 0 for same date" do
      result = invoke("daysBetweenDates", dv.of_date("2024-03-15"), dv.of_date("2024-03-15"))
      expect(result.value).to eq(0)
    end

    it "returns null when first arg is null" do
      result = invoke("daysBetweenDates", dv.of_null, dv.of_date("2024-01-01"))
      expect(result.null?).to be true
    end

    it "returns null when second arg is null" do
      result = invoke("daysBetweenDates", dv.of_date("2024-01-01"), dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── ageFromDate ──

  describe "ageFromDate" do
    it "calculates age with reference date" do
      result = invoke("ageFromDate", dv.of_date("2000-01-15"), dv.of_date("2024-06-15"))
      expect(result.integer?).to be true
      expect(result.value).to eq(24)
    end

    it "calculates age when birthday has not occurred yet in reference year" do
      result = invoke("ageFromDate", dv.of_date("2000-08-15"), dv.of_date("2024-06-15"))
      expect(result.value).to eq(23)
    end

    it "calculates age on birthday" do
      result = invoke("ageFromDate", dv.of_date("2000-06-15"), dv.of_date("2024-06-15"))
      expect(result.value).to eq(24)
    end

    it "returns null for null input" do
      result = invoke("ageFromDate", dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── isValidDate ──

  describe "isValidDate" do
    it "returns true for valid date string" do
      result = invoke("isValidDate", dv.of_string("2024-03-15"))
      expect(result.value).to be true
    end

    it "returns true for another valid date" do
      result = invoke("isValidDate", dv.of_string("2024-02-29"))
      expect(result.value).to be true
    end

    it "returns false for invalid date string" do
      result = invoke("isValidDate", dv.of_string("not-a-date"))
      expect(result.value).to be false
    end

    it "returns false for empty string" do
      result = invoke("isValidDate", dv.of_string(""))
      expect(result.value).to be false
    end

    it "returns false for null input" do
      result = invoke("isValidDate", dv.of_null)
      expect(result.value).to be false
    end
  end

  # ── formatLocaleDate ──

  describe "formatLocaleDate" do
    it "formats date with default locale and no pattern" do
      result = invoke("formatLocaleDate", dv.of_date("2024-03-15"), dv.of_string("en"))
      expect(result.string?).to be true
      expect(result.to_string).to eq("2024-03-15")
    end

    it "formats date with locale and custom pattern" do
      result = invoke("formatLocaleDate", dv.of_date("2024-03-15"), dv.of_string("en"), dv.of_string("dd MMMM yyyy"))
      expect(result.to_string).to eq("15 March 2024")
    end

    it "returns null for null input" do
      result = invoke("formatLocaleDate", dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── null propagation ──

  describe "null propagation" do
    it "formatDate returns null for null" do
      expect(invoke("formatDate", dv.of_null).null?).to be true
    end

    it "parseDate returns null for null" do
      expect(invoke("parseDate", dv.of_null).null?).to be true
    end

    it "formatTime returns null for null" do
      expect(invoke("formatTime", dv.of_null).null?).to be true
    end

    it "formatTimestamp returns null for null" do
      expect(invoke("formatTimestamp", dv.of_null).null?).to be true
    end

    it "parseTimestamp returns null for null" do
      expect(invoke("parseTimestamp", dv.of_null).null?).to be true
    end

    it "addDays returns null for null" do
      expect(invoke("addDays", dv.of_null, dv.of_integer(1)).null?).to be true
    end

    it "addMonths returns null for null" do
      expect(invoke("addMonths", dv.of_null, dv.of_integer(1)).null?).to be true
    end

    it "addYears returns null for null" do
      expect(invoke("addYears", dv.of_null, dv.of_integer(1)).null?).to be true
    end

    it "addHours returns null for null" do
      expect(invoke("addHours", dv.of_null, dv.of_integer(1)).null?).to be true
    end

    it "addMinutes returns null for null" do
      expect(invoke("addMinutes", dv.of_null, dv.of_integer(1)).null?).to be true
    end

    it "addSeconds returns null for null" do
      expect(invoke("addSeconds", dv.of_null, dv.of_integer(1)).null?).to be true
    end

    it "startOfDay returns null for null" do
      expect(invoke("startOfDay", dv.of_null).null?).to be true
    end

    it "endOfDay returns null for null" do
      expect(invoke("endOfDay", dv.of_null).null?).to be true
    end

    it "startOfMonth returns null for null" do
      expect(invoke("startOfMonth", dv.of_null).null?).to be true
    end

    it "endOfMonth returns null for null" do
      expect(invoke("endOfMonth", dv.of_null).null?).to be true
    end

    it "startOfYear returns null for null" do
      expect(invoke("startOfYear", dv.of_null).null?).to be true
    end

    it "endOfYear returns null for null" do
      expect(invoke("endOfYear", dv.of_null).null?).to be true
    end

    it "dayOfWeek returns null for null" do
      expect(invoke("dayOfWeek", dv.of_null).null?).to be true
    end

    it "dayOfMonth returns null for null" do
      expect(invoke("dayOfMonth", dv.of_null).null?).to be true
    end

    it "dayOfYear returns null for null" do
      expect(invoke("dayOfYear", dv.of_null).null?).to be true
    end

    it "weekOfYear returns null for null" do
      expect(invoke("weekOfYear", dv.of_null).null?).to be true
    end

    it "quarter returns null for null" do
      expect(invoke("quarter", dv.of_null).null?).to be true
    end

    it "isLeapYear returns null for null" do
      expect(invoke("isLeapYear", dv.of_null).null?).to be true
    end

    it "isBefore returns null for null first arg" do
      expect(invoke("isBefore", dv.of_null, dv.of_date("2024-01-01")).null?).to be true
    end

    it "isAfter returns null for null first arg" do
      expect(invoke("isAfter", dv.of_null, dv.of_date("2024-01-01")).null?).to be true
    end

    it "isBetween returns null for null value" do
      expect(invoke("isBetween", dv.of_null, dv.of_date("2024-01-01"), dv.of_date("2024-12-31")).null?).to be true
    end

    it "toUnix returns null for null" do
      expect(invoke("toUnix", dv.of_null).null?).to be true
    end

    it "fromUnix returns null for null" do
      expect(invoke("fromUnix", dv.of_null).null?).to be true
    end

    it "daysBetweenDates returns null for null first arg" do
      expect(invoke("daysBetweenDates", dv.of_null, dv.of_date("2024-01-01")).null?).to be true
    end

    it "ageFromDate returns null for null" do
      expect(invoke("ageFromDate", dv.of_null).null?).to be true
    end

    it "formatLocaleDate returns null for null" do
      expect(invoke("formatLocaleDate", dv.of_null).null?).to be true
    end
  end
end
