# frozen_string_literal: true

module Odin
  module Transform
    module Verbs
      module ObjectVerbs
        module_function

        def extract_obj(v)
          return nil if v.nil? || v.null?
          return v.value if v.object?
          if v.string?
            begin
              parsed = Types::DynValue.extract_object(v.value)
              return parsed.value
            rescue
              return nil
            end
          end
          nil
        end

        def register(registry)
          dv = Types::DynValue

          registry["keys"] = ->(args, _ctx) {
            obj = ObjectVerbs.extract_obj(args[0])
            return dv.of_null if obj.nil?
            dv.of_array(obj.keys.map { |k| dv.of_string(k) })
          }

          registry["values"] = ->(args, _ctx) {
            obj = ObjectVerbs.extract_obj(args[0])
            return dv.of_null if obj.nil?
            dv.of_array(obj.values)
          }

          registry["entries"] = ->(args, _ctx) {
            obj = ObjectVerbs.extract_obj(args[0])
            return dv.of_null if obj.nil?
            result = obj.map { |k, v| dv.of_array([dv.of_string(k), v]) }
            dv.of_array(result)
          }

          registry["has"] = ->(args, _ctx) {
            obj = ObjectVerbs.extract_obj(args[0])
            key = args[1]&.to_string || ""
            dv.of_bool(obj&.key?(key) || false)
          }

          registry["get"] = ->(args, _ctx) {
            obj = ObjectVerbs.extract_obj(args[0])
            key = args[1]&.to_string || ""
            default_val = args[2] || dv.of_null
            if obj && obj.key?(key)
              obj[key]
            else
              default_val
            end
          }

          registry["merge"] = ->(args, _ctx) {
            result = {}
            args.each do |a|
              obj = ObjectVerbs.extract_obj(a)
              result.merge!(obj) if obj
            end
            result.empty? ? dv.of_null : dv.of_object(result)
          }

          registry["jsonPath"] = ->(args, _ctx) {
            root = args[0]
            path = args[1]&.to_string || ""
            return dv.of_null if root.nil? || root.null? || path.empty?

            # Simple JSONPath: split on '.' and navigate
            parts = path.sub(/^\$\.?/, "").split(".")
            current = root
            parts.each do |part|
              break if current.nil? || current.null?
              # Handle array index like items[0]
              if part =~ /^(.+)\[(\d+)\]$/
                field = $1
                idx = $2.to_i
                current = current.object? ? current.get(field) : nil
                current = current&.array? ? (current.value[idx] || dv.of_null) : dv.of_null
              elsif current.object?
                current = current.get(part)
              elsif current.array?
                idx = part.to_i
                current = current.value[idx] || dv.of_null
              else
                current = nil
              end
            end
            current || dv.of_null
          }

          registry["extract"] = ->(args, _ctx) {
            obj = args[0]
            keys_arg = args[1]
            return dv.of_null if obj.nil? || obj.null? || !obj.object?

            key_list = if keys_arg&.array?
                         keys_arg.value.map(&:to_string)
                       elsif keys_arg&.string?
                         keys_arg.value.split(",").map(&:strip)
                       else
                         []
                       end

            result = {}
            key_list.each do |k|
              val = obj.get(k)
              result[k] = val if val
            end
            dv.of_object(result)
          }
        end
      end
    end
  end
end
