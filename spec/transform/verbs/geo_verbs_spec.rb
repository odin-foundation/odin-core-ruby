# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe "Geo Verbs" do
  let(:engine) { Odin::Transform::TransformEngine.new }
  let(:ctx) { Odin::Transform::VerbContext.new }
  let(:dv) { Odin::Types::DynValue }

  def invoke(name, *args)
    engine.invoke_verb(name, args, ctx)
  end

  # ── distance ──

  describe "distance" do
    it "computes distance from NYC to London in km" do
      # NYC: 40.7128, -74.0060  London: 51.5074, -0.1278
      result = invoke("distance",
        dv.of_float(40.7128), dv.of_float(-74.0060),
        dv.of_float(51.5074), dv.of_float(-0.1278))
      expect(result.value).to be_within(50.0).of(5570.0)
    end

    it "returns 0 for same point" do
      result = invoke("distance",
        dv.of_float(40.7128), dv.of_float(-74.0060),
        dv.of_float(40.7128), dv.of_float(-74.0060))
      expect(result.value).to be_within(0.001).of(0.0)
    end

    it "computes distance in miles" do
      result = invoke("distance",
        dv.of_float(40.7128), dv.of_float(-74.0060),
        dv.of_float(51.5074), dv.of_float(-0.1278),
        dv.of_string("mi"))
      expect(result.value).to be_within(50.0).of(3461.0)
    end

    it "computes distance in nautical miles" do
      result = invoke("distance",
        dv.of_float(40.7128), dv.of_float(-74.0060),
        dv.of_float(51.5074), dv.of_float(-0.1278),
        dv.of_string("nm"))
      expect(result.value).to be_within(50.0).of(3007.0)
    end

    it "returns null when lat1 is null" do
      result = invoke("distance",
        dv.of_null, dv.of_float(-74.0060),
        dv.of_float(51.5074), dv.of_float(-0.1278))
      expect(result.null?).to be true
    end

    it "returns null when lon1 is null" do
      result = invoke("distance",
        dv.of_float(40.7128), dv.of_null,
        dv.of_float(51.5074), dv.of_float(-0.1278))
      expect(result.null?).to be true
    end

    it "returns null when lat2 is null" do
      result = invoke("distance",
        dv.of_float(40.7128), dv.of_float(-74.0060),
        dv.of_null, dv.of_float(-0.1278))
      expect(result.null?).to be true
    end

    it "returns null when lon2 is null" do
      result = invoke("distance",
        dv.of_float(40.7128), dv.of_float(-74.0060),
        dv.of_float(51.5074), dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── inBoundingBox ──

  describe "inBoundingBox" do
    it "returns true when point is inside bounding box" do
      # Point: (45, -73), Box: (40, -80) to (50, -70)
      result = invoke("inBoundingBox",
        dv.of_float(45.0), dv.of_float(-73.0),
        dv.of_float(40.0), dv.of_float(-80.0),
        dv.of_float(50.0), dv.of_float(-70.0))
      expect(result.value).to be true
    end

    it "returns false when point is outside bounding box" do
      result = invoke("inBoundingBox",
        dv.of_float(55.0), dv.of_float(-73.0),
        dv.of_float(40.0), dv.of_float(-80.0),
        dv.of_float(50.0), dv.of_float(-70.0))
      expect(result.value).to be false
    end

    it "returns true when point is on boundary" do
      result = invoke("inBoundingBox",
        dv.of_float(40.0), dv.of_float(-80.0),
        dv.of_float(40.0), dv.of_float(-80.0),
        dv.of_float(50.0), dv.of_float(-70.0))
      expect(result.value).to be true
    end

    it "returns null when any coordinate is null" do
      result = invoke("inBoundingBox",
        dv.of_null, dv.of_float(-73.0),
        dv.of_float(40.0), dv.of_float(-80.0),
        dv.of_float(50.0), dv.of_float(-70.0))
      expect(result.null?).to be true
    end

    it "returns true on max boundary" do
      result = invoke("inBoundingBox",
        dv.of_float(50.0), dv.of_float(-70.0),
        dv.of_float(40.0), dv.of_float(-80.0),
        dv.of_float(50.0), dv.of_float(-70.0))
      expect(result.value).to be true
    end
  end

  # ── toRadians ──

  describe "toRadians" do
    it "converts 180 degrees to PI" do
      result = invoke("toRadians", dv.of_float(180.0))
      expect(result.value).to be_within(0.0001).of(Math::PI)
    end

    it "converts 0 degrees to 0" do
      result = invoke("toRadians", dv.of_float(0.0))
      expect(result.value).to be_within(0.0001).of(0.0)
    end

    it "converts 90 degrees to PI/2" do
      result = invoke("toRadians", dv.of_float(90.0))
      expect(result.value).to be_within(0.0001).of(Math::PI / 2.0)
    end

    it "returns null for null input" do
      result = invoke("toRadians", dv.of_null)
      expect(result.null?).to be true
    end

    it "converts 360 degrees to 2*PI" do
      result = invoke("toRadians", dv.of_float(360.0))
      expect(result.value).to be_within(0.0001).of(2.0 * Math::PI)
    end
  end

  # ── toDegrees ──

  describe "toDegrees" do
    it "converts PI radians to 180 degrees" do
      result = invoke("toDegrees", dv.of_float(Math::PI))
      expect(result.value).to be_within(0.0001).of(180.0)
    end

    it "converts 0 radians to 0 degrees" do
      result = invoke("toDegrees", dv.of_float(0.0))
      expect(result.value).to be_within(0.0001).of(0.0)
    end

    it "converts PI/2 radians to 90 degrees" do
      result = invoke("toDegrees", dv.of_float(Math::PI / 2.0))
      expect(result.value).to be_within(0.0001).of(90.0)
    end

    it "returns null for null input" do
      result = invoke("toDegrees", dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── toRadians/toDegrees roundtrip ──

  describe "toRadians/toDegrees roundtrip" do
    it "roundtrips 180 degrees" do
      radians = invoke("toRadians", dv.of_float(180.0))
      degrees = invoke("toDegrees", radians)
      expect(degrees.value).to be_within(0.0001).of(180.0)
    end

    it "roundtrips 45 degrees" do
      radians = invoke("toRadians", dv.of_float(45.0))
      degrees = invoke("toDegrees", radians)
      expect(degrees.value).to be_within(0.0001).of(45.0)
    end

    it "roundtrips 270 degrees" do
      radians = invoke("toRadians", dv.of_float(270.0))
      degrees = invoke("toDegrees", radians)
      expect(degrees.value).to be_within(0.0001).of(270.0)
    end
  end

  # ── bearing ──

  describe "bearing" do
    it "computes bearing due north (approximately 0)" do
      # Same longitude, point 2 is north
      result = invoke("bearing",
        dv.of_float(40.0), dv.of_float(-74.0),
        dv.of_float(41.0), dv.of_float(-74.0))
      expect(result.value).to be_within(1.0).of(0.0)
    end

    it "computes bearing due east (approximately 90)" do
      # Same latitude, point 2 is east
      result = invoke("bearing",
        dv.of_float(0.0), dv.of_float(0.0),
        dv.of_float(0.0), dv.of_float(1.0))
      expect(result.value).to be_within(1.0).of(90.0)
    end

    it "computes bearing due south (approximately 180)" do
      result = invoke("bearing",
        dv.of_float(41.0), dv.of_float(-74.0),
        dv.of_float(40.0), dv.of_float(-74.0))
      expect(result.value).to be_within(1.0).of(180.0)
    end

    it "returns null when lat1 is null" do
      result = invoke("bearing",
        dv.of_null, dv.of_float(-74.0),
        dv.of_float(41.0), dv.of_float(-74.0))
      expect(result.null?).to be true
    end

    it "returns null when lon2 is null" do
      result = invoke("bearing",
        dv.of_float(40.0), dv.of_float(-74.0),
        dv.of_float(41.0), dv.of_null)
      expect(result.null?).to be true
    end
  end

  # ── midpoint ──

  describe "midpoint" do
    it "computes midpoint returning object with lat and lon" do
      result = invoke("midpoint",
        dv.of_float(40.0), dv.of_float(-74.0),
        dv.of_float(42.0), dv.of_float(-72.0))
      expect(result.object?).to be true
      expect(result.get("lat").value).to be_within(0.5).of(41.0)
      expect(result.get("lon").value).to be_within(0.5).of(-73.0)
    end

    it "returns same point when both inputs are identical" do
      result = invoke("midpoint",
        dv.of_float(40.7128), dv.of_float(-74.0060),
        dv.of_float(40.7128), dv.of_float(-74.0060))
      expect(result.object?).to be true
      expect(result.get("lat").value).to be_within(0.001).of(40.7128)
      expect(result.get("lon").value).to be_within(0.001).of(-74.0060)
    end

    it "returns null when lat1 is null" do
      result = invoke("midpoint",
        dv.of_null, dv.of_float(-74.0),
        dv.of_float(42.0), dv.of_float(-72.0))
      expect(result.null?).to be true
    end

    it "returns null when lon1 is null" do
      result = invoke("midpoint",
        dv.of_float(40.0), dv.of_null,
        dv.of_float(42.0), dv.of_float(-72.0))
      expect(result.null?).to be true
    end

    it "returns null when lat2 is null" do
      result = invoke("midpoint",
        dv.of_float(40.0), dv.of_float(-74.0),
        dv.of_null, dv.of_float(-72.0))
      expect(result.null?).to be true
    end

    it "returns null when lon2 is null" do
      result = invoke("midpoint",
        dv.of_float(40.0), dv.of_float(-74.0),
        dv.of_float(42.0), dv.of_null)
      expect(result.null?).to be true
    end

    it "computes midpoint of equator points" do
      result = invoke("midpoint",
        dv.of_float(0.0), dv.of_float(0.0),
        dv.of_float(0.0), dv.of_float(10.0))
      expect(result.get("lat").value).to be_within(0.1).of(0.0)
      expect(result.get("lon").value).to be_within(0.1).of(5.0)
    end
  end
end
