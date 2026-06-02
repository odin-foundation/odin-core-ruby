# frozen_string_literal: true

require_relative "types"

module Odin
  module Forms
    # Parses ODIN forms text into a typed OdinForm structure. Low-level ODIN
    # parsing is delegated to Odin.parse; the flat path space is then mapped onto
    # the Forms model.
    class Parser
      VALID_UNITS = %w[inch cm mm pt].freeze
      VALID_INPUT_TYPES = %w[text email tel password number url].freeze
      VALID_BARCODE_TYPES = %w[code39 code128 qr datamatrix pdf417].freeze
      REGION_OWN_PROPS = %w[x y w h bind max overflow].freeze
      REGION_CHILD_TYPES = %w[text field img barcode].freeze

      TPL_HEADER = /\A\s*\{\s*@(tpl_[A-Za-z0-9_]+)\s*\}\s*\z/.freeze
      TOP_LEVEL_HEADER = /\A\s*\{\s*(\$|page\[\d+\]|@tpl_)/.freeze
      ANCHOR_HEADER = /\A\s*\{\s*(page\[\d+\]|tpl\.[A-Za-z0-9_]+)\s*\}\s*\z/.freeze
      RELATIVE_HEADER = /\A\s*\{\s*\./.freeze
      RELATIVE_TABULAR = /\A\s*\{\s*\.[^}]*\[\]\s*:/.freeze
      PAGE_PATH = /\Apage\[(\d+)\]\./.freeze

      def parse(text)
        body, template_blocks = split_templates(text)
        doc = Odin.parse(body)

        i18n = extract_i18n(doc)

        OdinForm.new(
          metadata: extract_metadata(doc),
          page_defaults: extract_page_defaults(doc),
          screen: extract_screen(doc),
          i18n: i18n,
          pages: extract_pages(doc, i18n),
          templates: extract_templates(template_blocks, i18n)
        )
      end

      private

      # Split a forms document into its core-parseable body and the raw text of
      # each {@tpl_*} template block.
      def split_templates(text)
        lines = text.split(/\r?\n/)
        body_lines = []
        blocks = []
        current = nil

        lines.each do |line|
          if (m = TPL_HEADER.match(line))
            current = { name: m[1], text: +"" }
            blocks << current
            next
          end
          if current
            if TOP_LEVEL_HEADER.match?(line) && !TPL_HEADER.match?(line)
              current = nil
              body_lines << line
            else
              current[:text] << line << "\n"
            end
            next
          end
          body_lines << line
        end

        [reanchor(body_lines.join("\n")), blocks]
      end

      # Re-emit the active top-level anchor after a relative tabular block so
      # following relative siblings resolve against the page, not the field.
      def reanchor(text, root_anchor = nil)
        out = []
        anchor = root_anchor
        needs_reanchor = false

        text.split(/\r?\n/).each do |line|
          if (m = ANCHOR_HEADER.match(line))
            anchor = "{#{m[1]}}"
            needs_reanchor = false
            out << line
            next
          end

          if RELATIVE_HEADER.match?(line)
            if needs_reanchor && anchor
              out << anchor
              needs_reanchor = false
            end
            needs_reanchor = true if RELATIVE_TABULAR.match?(line)
            out << line
            next
          end

          out << line
        end

        out.join("\n")
      end

      def extract_templates(blocks, i18n)
        return nil if blocks.empty?

        templates = {}
        blocks.each do |block|
          root = "tpl.#{block[:name]}"
          synthetic = reanchor("{#{root}}\n#{block[:text]}", "{#{root}}")
          doc = Odin.parse(synthetic)
          prefix = "#{root}."

          page_template = bool_value(doc, "#{prefix}page-template")
          page_template = true if page_template.nil?

          templates[block[:name]] = PageTemplate.new(
            name: block[:name],
            page_template: page_template,
            continues: string_value(doc, "#{prefix}continues"),
            form_id: string_value(doc, "#{prefix}form-id"),
            elements: extract_elements(doc, prefix, i18n)
          )
        end
        templates
      end

      # ── Metadata and settings ────────────────────────────────────────────────

      def extract_metadata(doc)
        meta = {
          title: meta_string(doc, "title") || "",
          id: meta_string(doc, "id") || "",
          lang: meta_string(doc, "lang") || "en",
        }
        version = meta_string(doc, "forms")
        meta[:version] = version if version
        meta
      end

      def extract_page_defaults(doc)
        width = meta_number(doc, "page.width")
        height = meta_number(doc, "page.height")
        unit = meta_string(doc, "page.unit")
        margin = extract_margins(doc)

        return nil if width.nil? && height.nil? && unit.nil?

        resolved_unit = VALID_UNITS.include?(unit) ? unit : "inch"
        result = { width: width || 8.5, height: height || 11, unit: resolved_unit }
        result[:margin] = margin if margin
        result
      end

      def extract_margins(doc)
        sides = {}
        %w[top right bottom left].each do |side|
          v = meta_number(doc, "page.margin.#{side}")
          sides[side.to_sym] = v unless v.nil?
        end
        sides.empty? ? nil : sides
      end

      def extract_screen(doc)
        scale = meta_number(doc, "screen.scale")
        scale.nil? ? nil : { scale: scale }
      end

      def extract_i18n(doc)
        prefix = "i18n."
        result = {}
        doc.metadata.each do |key, val|
          next unless key.start_with?(prefix)

          sub = key[prefix.length..]
          value = val.type == :string ? val.value : nil
          result[sub] = value if sub && !sub.empty? && value
        end
        result.empty? ? nil : result
      end

      # ── Pages and elements ───────────────────────────────────────────────────

      def extract_pages(doc, i18n)
        indices = []
        doc.paths.each do |path|
          m = PAGE_PATH.match(path)
          indices << m[1].to_i if m
        end
        indices = indices.uniq.sort
        return [] if indices.empty?

        indices.map { |i| FormPage.new(extract_elements(doc, "page[#{i}].", i18n)) }
      end

      def extract_elements(doc, prefix, i18n)
        keys_seen = {}
        keys_ordered = []

        doc.paths.each do |path|
          next unless path.start_with?(prefix)

          rest = path[prefix.length..]
          parts = rest.split(".")
          next if parts.length < 2

          key = "#{parts[0]}.#{parts[1]}"
          unless keys_seen[key]
            keys_seen[key] = true
            keys_ordered << key
          end
        end

        id_counter = 0
        elements = []
        keys_ordered.each do |key|
          element_type, element_name = key.split(".", 2)
          element_prefix = "#{prefix}#{key}."
          element = build_element(doc, element_type, element_name, element_prefix, id_counter, i18n)
          id_counter += 1
          elements << element if element
        end
        elements
      end

      # ── Element dispatch ─────────────────────────────────────────────────────

      def build_element(doc, element_type, element_name, prefix, id_counter, i18n)
        id = "#{element_type}_#{element_name}_#{id_counter}"

        case element_type
        when "line"     then build_line(doc, element_name, id, prefix)
        when "rect"     then build_rect(doc, element_name, id, prefix)
        when "circle"   then build_circle(doc, element_name, id, prefix)
        when "ellipse"  then build_ellipse(doc, element_name, id, prefix)
        when "polygon"  then build_polygon(doc, element_name, id, prefix)
        when "polyline" then build_polyline(doc, element_name, id, prefix)
        when "path"     then build_path(doc, element_name, id, prefix)
        when "text"     then build_text(doc, element_name, id, prefix, i18n)
        when "img"      then build_image(doc, element_name, id, prefix, i18n)
        when "barcode"  then build_barcode(doc, element_name, id, prefix, i18n)
        when "field"    then build_field(doc, element_name, id, prefix, i18n)
        when "region"   then build_region(doc, element_name, id, prefix, i18n)
        end
      end

      # ── Geometric builders ───────────────────────────────────────────────────

      def build_line(doc, name, id, prefix)
        props = {
          type: ElementType::LINE, name: name, id: id,
          x1: number_value(doc, "#{prefix}x1") || 0,
          y1: number_value(doc, "#{prefix}y1") || 0,
          x2: number_value(doc, "#{prefix}x2") || 0,
          y2: number_value(doc, "#{prefix}y2") || 0,
        }
        merge_stroked(props, doc, prefix)
        FormElement.new(props)
      end

      def build_rect(doc, name, id, prefix)
        props = {
          type: ElementType::RECT, name: name, id: id,
          x: number_value(doc, "#{prefix}x") || 0,
          y: number_value(doc, "#{prefix}y") || 0,
          w: number_value(doc, "#{prefix}w") || 0,
          h: number_value(doc, "#{prefix}h") || 0,
        }
        rx = number_value(doc, "#{prefix}rx")
        ry = number_value(doc, "#{prefix}ry")
        props[:rx] = rx unless rx.nil?
        props[:ry] = ry unless ry.nil?
        merge_stroked(props, doc, prefix)
        merge_filled(props, doc, prefix)
        FormElement.new(props)
      end

      def build_circle(doc, name, id, prefix)
        props = {
          type: ElementType::CIRCLE, name: name, id: id,
          cx: number_value(doc, "#{prefix}cx") || 0,
          cy: number_value(doc, "#{prefix}cy") || 0,
          r: number_value(doc, "#{prefix}r") || 0,
        }
        merge_stroked(props, doc, prefix)
        merge_filled(props, doc, prefix)
        FormElement.new(props)
      end

      def build_ellipse(doc, name, id, prefix)
        props = {
          type: ElementType::ELLIPSE, name: name, id: id,
          cx: number_value(doc, "#{prefix}cx") || 0,
          cy: number_value(doc, "#{prefix}cy") || 0,
          rx: number_value(doc, "#{prefix}rx") || 0,
          ry: number_value(doc, "#{prefix}ry") || 0,
        }
        merge_stroked(props, doc, prefix)
        merge_filled(props, doc, prefix)
        FormElement.new(props)
      end

      def build_polygon(doc, name, id, prefix)
        props = {
          type: ElementType::POLYGON, name: name, id: id,
          points: string_value(doc, "#{prefix}points") || "",
        }
        merge_stroked(props, doc, prefix)
        merge_filled(props, doc, prefix)
        FormElement.new(props)
      end

      def build_polyline(doc, name, id, prefix)
        props = {
          type: ElementType::POLYLINE, name: name, id: id,
          points: string_value(doc, "#{prefix}points") || "",
        }
        merge_stroked(props, doc, prefix)
        FormElement.new(props)
      end

      def build_path(doc, name, id, prefix)
        props = {
          type: ElementType::PATH, name: name, id: id,
          d: string_value(doc, "#{prefix}d") || "",
        }
        merge_stroked(props, doc, prefix)
        merge_filled(props, doc, prefix)
        FormElement.new(props)
      end

      # ── Content builders ─────────────────────────────────────────────────────

      def build_text(doc, name, id, prefix, i18n)
        props = {
          type: ElementType::TEXT, name: name, id: id,
          content: label_value(doc, "#{prefix}content", i18n) || "",
          x: number_value(doc, "#{prefix}x") || 0,
          y: number_value(doc, "#{prefix}y") || 0,
        }
        rotate = number_value(doc, "#{prefix}rotate")
        props[:rotate] = rotate unless rotate.nil?
        merge_fonted(props, doc, prefix)
        FormElement.new(props)
      end

      def build_image(doc, name, id, prefix, i18n)
        background = bool_value(doc, "#{prefix}background")
        props = {
          type: ElementType::IMG, name: name, id: id,
          src: binary_literal(doc, "#{prefix}src") || "",
          alt: label_value(doc, "#{prefix}alt", i18n) || "",
          x: number_value(doc, "#{prefix}x") || 0,
          y: number_value(doc, "#{prefix}y") || 0,
          w: number_value(doc, "#{prefix}w") || 0,
          h: number_value(doc, "#{prefix}h") || 0,
        }
        props[:background] = background unless background.nil?
        FormElement.new(props)
      end

      def build_barcode(doc, name, id, prefix, i18n)
        raw = string_value(doc, "#{prefix}type") || string_value(doc, "#{prefix}barcode-type") || "code128"
        resolved = VALID_BARCODE_TYPES.include?(raw) ? raw : "code128"
        FormElement.new(
          type: ElementType::BARCODE, name: name, id: id,
          barcodeType: resolved,
          content: label_value(doc, "#{prefix}content", i18n) || "",
          alt: label_value(doc, "#{prefix}alt", i18n) || "",
          x: number_value(doc, "#{prefix}x") || 0,
          y: number_value(doc, "#{prefix}y") || 0,
          w: number_value(doc, "#{prefix}w") || 0,
          h: number_value(doc, "#{prefix}h") || 0
        )
      end

      # ── Field builder ────────────────────────────────────────────────────────

      def build_field(doc, name, id, prefix, i18n)
        field_type = string_value(doc, "#{prefix}type") || "text"
        base = extract_base_field(doc, name, id, prefix, i18n)

        case field_type
        when "text"        then build_text_field(doc, prefix, base)
        when "checkbox"    then build_checkbox_field(doc, prefix, base)
        when "radio"       then build_radio_field(doc, prefix, base)
        when "select"      then build_select_field(doc, prefix, base)
        when "multiselect" then build_multiselect_field(doc, prefix, base)
        when "date"        then build_date_field(doc, prefix, base)
        when "signature"   then build_signature_field(doc, prefix, base)
        else build_text_field(doc, prefix, base)
        end
      end

      def extract_base_field(doc, name, id, prefix, i18n)
        required = bool_value(doc, "#{prefix}required")
        tabindex = number_value(doc, "#{prefix}tabindex")
        min_length = number_value(doc, "#{prefix}minLength")
        max_length = number_value(doc, "#{prefix}maxLength")
        min = number_value(doc, "#{prefix}min") || scalar_string(doc, "#{prefix}min")
        max = number_value(doc, "#{prefix}max") || scalar_string(doc, "#{prefix}max")
        aria_label = label_value(doc, "#{prefix}aria-label", i18n)
        readonly = bool_value(doc, "#{prefix}readonly")
        bind_ref = reference_value(doc, "#{prefix}bind")

        base = {
          name: name, id: id,
          label: label_value(doc, "#{prefix}label", i18n) || "",
          x: number_value(doc, "#{prefix}x") || 0,
          y: number_value(doc, "#{prefix}y") || 0,
          w: number_value(doc, "#{prefix}w") || 0,
          h: number_value(doc, "#{prefix}h") || 0,
          bind: bind_ref ? "@#{bind_ref}" : "",
        }
        base[:required] = required unless required.nil?
        base[:tabindex] = tabindex unless tabindex.nil?
        base[:minLength] = min_length unless min_length.nil?
        base[:maxLength] = max_length unless max_length.nil?
        base[:min] = min unless min.nil?
        base[:max] = max unless max.nil?
        base[:"aria-label"] = aria_label unless aria_label.nil?
        base[:readonly] = readonly unless readonly.nil?
        base
      end

      def build_text_field(doc, prefix, base)
        props = base.merge(type: ElementType::FIELD_TEXT)
        value = scalar_string(doc, "#{prefix}value")
        input_type = string_value(doc, "#{prefix}inputType")
        mask = string_value(doc, "#{prefix}mask")
        placeholder = string_value(doc, "#{prefix}placeholder")
        multiline = bool_value(doc, "#{prefix}multiline")
        max_lines = number_value(doc, "#{prefix}maxLines")

        props[:value] = value unless value.nil?
        props[:inputType] = input_type if VALID_INPUT_TYPES.include?(input_type)
        props[:mask] = mask unless mask.nil?
        props[:placeholder] = placeholder unless placeholder.nil?
        props[:multiline] = multiline unless multiline.nil?
        props[:maxLines] = max_lines unless max_lines.nil?
        FormElement.new(props)
      end

      def build_checkbox_field(doc, prefix, base)
        props = base.merge(type: ElementType::FIELD_CHECKBOX)
        checked = bool_value(doc, "#{prefix}checked")
        props[:checked] = checked unless checked.nil?
        FormElement.new(props)
      end

      def build_radio_field(doc, prefix, base)
        FormElement.new(base.merge(
          type: ElementType::FIELD_RADIO,
          group: string_value(doc, "#{prefix}group") || "",
          value: string_value(doc, "#{prefix}value") || ""
        ))
      end

      def build_select_field(doc, prefix, base)
        props = base.merge(
          type: ElementType::FIELD_SELECT,
          options: extract_options(doc, prefix)
        )
        selected = string_value(doc, "#{prefix}selected")
        placeholder = string_value(doc, "#{prefix}placeholder")
        props[:selected] = selected unless selected.nil?
        props[:placeholder] = placeholder unless placeholder.nil?
        FormElement.new(props)
      end

      def build_multiselect_field(doc, prefix, base)
        props = base.merge(
          type: ElementType::FIELD_MULTISELECT,
          options: extract_options(doc, prefix)
        )
        selected = extract_field_array(doc, prefix, "selected")
        min_select = number_value(doc, "#{prefix}minSelect")
        max_select = number_value(doc, "#{prefix}maxSelect")
        props[:selected] = selected unless selected.nil?
        props[:minSelect] = min_select unless min_select.nil?
        props[:maxSelect] = max_select unless max_select.nil?
        FormElement.new(props)
      end

      def build_date_field(doc, prefix, base)
        props = base.merge(type: ElementType::FIELD_DATE)
        value = scalar_string(doc, "#{prefix}value")
        props[:value] = value unless value.nil?
        FormElement.new(props)
      end

      def build_signature_field(doc, prefix, base)
        props = base.merge(type: ElementType::FIELD_SIGNATURE)
        value = binary_literal(doc, "#{prefix}value")
        date_field = string_value(doc, "#{prefix}date_field")
        props[:value] = value unless value.nil?
        props[:date_field] = date_field unless date_field.nil?
        FormElement.new(props)
      end

      def extract_options(doc, prefix)
        extract_field_array(doc, prefix, "options") || []
      end

      # Extract a field's tabular string array, tolerating the extra path segment
      # a relative tabular header leaves in place.
      def extract_field_array(doc, prefix, name)
        direct = collect_indexed(doc, "#{prefix}#{name}")
        return direct unless direct.empty?

        re = /\A#{Regexp.escape(prefix)}(?:[^.]+\.)*#{Regexp.escape(name)}\[(\d+)\]\z/
        found = []
        doc.paths.each do |p|
          m = re.match(p)
          found << [m[1].to_i, p] if m
        end
        return nil if found.empty?

        found.sort_by!(&:first)
        found.filter_map { |(_, path)| string_value(doc, path) }
      end

      def collect_indexed(doc, base)
        out = []
        i = 0
        while doc.include?("#{base}[#{i}]")
          v = string_value(doc, "#{base}[#{i}]")
          out << v unless v.nil?
          i += 1
        end
        out
      end

      # ── Region builder ───────────────────────────────────────────────────────

      def build_region(doc, name, id, prefix, i18n)
        bind = reference_value(doc, "#{prefix}bind")
        max = number_value(doc, "#{prefix}max")
        overflow_ref = reference_value(doc, "#{prefix}overflow")
        overflow = overflow_ref || string_value(doc, "#{prefix}overflow")

        props = {
          type: ElementType::REGION, name: name, id: id,
          x: number_value(doc, "#{prefix}x") || 0,
          y: number_value(doc, "#{prefix}y") || 0,
          w: number_value(doc, "#{prefix}w") || 0,
          h: number_value(doc, "#{prefix}h") || 0,
          children: extract_region_children(doc, prefix, i18n),
        }
        props[:bind] = "@#{bind}" unless bind.nil?
        unless overflow.nil?
          props[:overflow] = overflow_ref ? "@#{overflow}" : overflow
        end
        props[:max] = max unless max.nil?
        FormElement.new(props)
      end

      def extract_region_children(doc, prefix, i18n)
        keys_seen = {}
        keys_ordered = []

        doc.paths.each do |path|
          next unless path.start_with?(prefix)

          rest = path[prefix.length..]
          parts = rest.split(".")
          next if parts.length < 2
          next if REGION_OWN_PROPS.include?(parts[0])
          next unless REGION_CHILD_TYPES.include?(parts[0])

          key = "#{parts[0]}.#{parts[1]}"
          unless keys_seen[key]
            keys_seen[key] = true
            keys_ordered << key
          end
        end

        id_counter = 0
        children = []
        keys_ordered.each do |key|
          child_type, child_name = key.split(".", 2)
          child_prefix = "#{prefix}#{key}."
          built = build_element(doc, child_type, child_name, child_prefix, id_counter, i18n)
          id_counter += 1
          next unless built

          y_offset = number_value(doc, "#{child_prefix}y-offset")
          x_offset = number_value(doc, "#{child_prefix}x-offset")
          props = built.props.dup
          props[:"y-offset"] = y_offset unless y_offset.nil?
          props[:"x-offset"] = x_offset unless x_offset.nil?
          children << FormElement.new(props)
        end
        children
      end

      # ── Style mixin extractors ───────────────────────────────────────────────

      def merge_stroked(props, doc, prefix)
        v = string_value(doc, "#{prefix}stroke")
        props[:stroke] = v unless v.nil?
        v = number_value(doc, "#{prefix}stroke-width")
        props[:"stroke-width"] = v unless v.nil?
        v = number_value(doc, "#{prefix}stroke-opacity")
        props[:"stroke-opacity"] = v unless v.nil?
        v = string_value(doc, "#{prefix}stroke-dasharray")
        props[:"stroke-dasharray"] = v unless v.nil?
        v = string_value(doc, "#{prefix}stroke-linecap")
        props[:"stroke-linecap"] = v unless v.nil?
        v = string_value(doc, "#{prefix}stroke-linejoin")
        props[:"stroke-linejoin"] = v unless v.nil?
      end

      def merge_filled(props, doc, prefix)
        v = string_value(doc, "#{prefix}fill")
        props[:fill] = v unless v.nil?
        v = number_value(doc, "#{prefix}fill-opacity")
        props[:"fill-opacity"] = v unless v.nil?
      end

      def merge_fonted(props, doc, prefix)
        v = string_value(doc, "#{prefix}font-family")
        props[:"font-family"] = v unless v.nil?
        v = number_value(doc, "#{prefix}font-size")
        props[:"font-size"] = v unless v.nil?
        v = string_value(doc, "#{prefix}font-weight")
        props[:"font-weight"] = v unless v.nil?
        v = string_value(doc, "#{prefix}font-style")
        props[:"font-style"] = v unless v.nil?
        v = string_value(doc, "#{prefix}text-align")
        props[:"text-align"] = v unless v.nil?
        v = string_value(doc, "#{prefix}color")
        props[:color] = v unless v.nil?
      end

      # ── Value accessors ──────────────────────────────────────────────────────

      def string_value(doc, path)
        val = doc.get(path)
        return nil if val.nil?

        val.type == :string ? val.value : nil
      end

      # Resolve a string property that may instead be an @$.i18n.* reference.
      def label_value(doc, path, i18n)
        val = doc.get(path)
        return nil if val.nil?
        return val.value if val.type == :string

        if val.type == :reference
          ref = val.path
          if ref.start_with?("$.i18n.")
            key = ref["$.i18n.".length..]
            return (i18n && i18n[key]) || ref
          end
          return ref
        end
        nil
      end

      # Read a scalar as a string, preserving the raw source form for dates.
      def scalar_string(doc, path)
        val = doc.get(path)
        return nil if val.nil?

        case val.type
        when :string then val.value
        when :date, :timestamp then val.respond_to?(:raw) && val.raw ? val.raw : val.value.to_s
        end
      end

      # Reconstruct an ODIN binary literal (^algorithm:base64).
      def binary_literal(doc, path)
        val = doc.get(path)
        return nil if val.nil?

        if val.type == :binary
          return val.algorithm ? "^#{val.algorithm}:#{val.data}" : "^#{val.data}"
        end
        val.type == :string ? val.value : nil
      end

      def number_value(doc, path)
        val = doc.get(path)
        return nil if val.nil?
        return nil unless val.type == :number || val.type == :integer

        v = val.value
        v == v.to_i ? v.to_i : v
      end

      def bool_value(doc, path)
        val = doc.get(path)
        return nil if val.nil?

        val.type == :boolean ? val.value : nil
      end

      def reference_value(doc, path)
        val = doc.get(path)
        return nil if val.nil?

        val.type == :reference ? val.path : nil
      end

      def meta_string(doc, key)
        mv = doc.metadata[key]
        mv && mv.type == :string ? mv.value : nil
      end

      def meta_number(doc, key)
        mv = doc.metadata[key]
        return nil unless mv && (mv.type == :number || mv.type == :integer)

        v = mv.value
        v == v.to_i ? v.to_i : v
      end
    end
  end
end
