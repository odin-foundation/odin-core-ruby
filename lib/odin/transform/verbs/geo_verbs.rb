# frozen_string_literal: true

module Odin
  module Transform
    module Verbs
      module GeoVerbs
        EARTH_RADIUS_KM = 6371.0
        DEG_TO_RAD = Math::PI / 180.0
        RAD_TO_DEG = 180.0 / Math::PI
        KM_TO_MI = 0.621371
        KM_TO_NM = 0.539957

        module_function

        def register(registry)
          dv = Types::DynValue

          registry["distance"] = ->(args, ctx) {
            lat1 = NumericVerbs.to_double(args[0])
            lon1 = NumericVerbs.to_double(args[1])
            lat2 = NumericVerbs.to_double(args[2])
            lon2 = NumericVerbs.to_double(args[3])
            unit = args[4]&.to_string || "km"
            return dv.of_null if lat1.nil? || lon1.nil? || lat2.nil? || lon2.nil?

            valid_units = %w[km mi miles nm]
            unless valid_units.include?(unit)
              ctx.errors << TransformEngine.incompatible_conversion_error(
                "distance", "unknown unit '#{unit}' (expected 'km', 'mi', or 'miles')"
              )
              return dv.of_null
            end

            dlat = (lat2 - lat1) * DEG_TO_RAD
            dlon = (lon2 - lon1) * DEG_TO_RAD
            a = Math.sin(dlat / 2)**2 +
                Math.cos(lat1 * DEG_TO_RAD) * Math.cos(lat2 * DEG_TO_RAD) *
                Math.sin(dlon / 2)**2
            c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
            dist_km = EARTH_RADIUS_KM * c

            result = case unit
                     when "mi", "miles" then dist_km * KM_TO_MI
                     when "nm" then dist_km * KM_TO_NM
                     else dist_km
                     end
            return dv.of_null if result.nan? || result.infinite?
            dv.of_float(result)
          }

          registry["inBoundingBox"] = ->(args, _ctx) {
            lat = NumericVerbs.to_double(args[0])
            lon = NumericVerbs.to_double(args[1])
            min_lat = NumericVerbs.to_double(args[2])
            min_lon = NumericVerbs.to_double(args[3])
            max_lat = NumericVerbs.to_double(args[4])
            max_lon = NumericVerbs.to_double(args[5])
            return dv.of_null if [lat, lon, min_lat, min_lon, max_lat, max_lon].any?(&:nil?)
            dv.of_bool(lat >= min_lat && lat <= max_lat && lon >= min_lon && lon <= max_lon)
          }

          registry["toRadians"] = ->(args, _ctx) {
            v = NumericVerbs.to_double(args[0])
            return dv.of_null if v.nil?
            dv.of_float(v * DEG_TO_RAD)
          }

          registry["toDegrees"] = ->(args, _ctx) {
            v = NumericVerbs.to_double(args[0])
            return dv.of_null if v.nil?
            dv.of_float(v * RAD_TO_DEG)
          }

          registry["bearing"] = ->(args, _ctx) {
            lat1 = NumericVerbs.to_double(args[0])
            lon1 = NumericVerbs.to_double(args[1])
            lat2 = NumericVerbs.to_double(args[2])
            lon2 = NumericVerbs.to_double(args[3])
            return dv.of_null if lat1.nil? || lon1.nil? || lat2.nil? || lon2.nil?

            lat1r = lat1 * DEG_TO_RAD
            lat2r = lat2 * DEG_TO_RAD
            dlon = (lon2 - lon1) * DEG_TO_RAD

            y = Math.sin(dlon) * Math.cos(lat2r)
            x = Math.cos(lat1r) * Math.sin(lat2r) - Math.sin(lat1r) * Math.cos(lat2r) * Math.cos(dlon)
            bearing = Math.atan2(y, x) * RAD_TO_DEG
            bearing = (bearing + 360) % 360
            return dv.of_null if bearing.nan? || bearing.infinite?
            dv.of_float(bearing)
          }

          registry["midpoint"] = ->(args, _ctx) {
            lat1 = NumericVerbs.to_double(args[0])
            lon1 = NumericVerbs.to_double(args[1])
            lat2 = NumericVerbs.to_double(args[2])
            lon2 = NumericVerbs.to_double(args[3])
            return dv.of_null if lat1.nil? || lon1.nil? || lat2.nil? || lon2.nil?

            lat1r = lat1 * DEG_TO_RAD
            lat2r = lat2 * DEG_TO_RAD
            lon1r = lon1 * DEG_TO_RAD
            dlon = (lon2 - lon1) * DEG_TO_RAD

            bx = Math.cos(lat2r) * Math.cos(dlon)
            by = Math.cos(lat2r) * Math.sin(dlon)
            mid_lat = Math.atan2(
              Math.sin(lat1r) + Math.sin(lat2r),
              Math.sqrt((Math.cos(lat1r) + bx)**2 + by**2)
            )
            mid_lon = lon1r + Math.atan2(by, Math.cos(lat1r) + bx)

            mid_lat_deg = mid_lat * RAD_TO_DEG
            mid_lon_deg = mid_lon * RAD_TO_DEG

            dv.of_object({
              "lat" => dv.of_float(mid_lat_deg),
              "lon" => dv.of_float(mid_lon_deg)
            })
          }
        end
      end
    end
  end
end
