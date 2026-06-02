# frozen_string_literal: true

require_relative "units"
require_relative "css"
require_relative "accessibility"

module Odin
  module Forms
    # Renders a parsed OdinForm into a complete, accessible HTML string.
    class Renderer
      def render(form, data = nil, options = nil)
        title = (form.metadata[:title] && !form.metadata[:title].empty? ? form.metadata[:title] : "ODIN Form")
        class_name = options && options[:className] ? " #{options[:className]}" : ""
        unit = (form.page_defaults && form.page_defaults[:unit]) || "inch"

        plan = build_render_plan(form, data)
        total_pages = plan.length
        page_w = Units.to_pixels((form.page_defaults && form.page_defaults[:width]) || 8.5, unit)
        page_h = Units.to_pixels((form.page_defaults && form.page_defaults[:height]) || 11, unit)

        parts = []
        parts << %(<form role="form" aria-label="#{escape_attr(title)}" class="odin-form#{class_name}">)
        parts << Accessibility.skip_link_html(title)
        parts << "<style>#{Css.generate_form_css}\n#{Css.generate_print_css}</style>"

        plan.each_with_index do |planned, i|
          ctx = {
            page_number: i + 1,
            total_pages: total_pages,
            unit: unit,
            data: data,
            page_width_px: page_w,
            page_height_px: page_h,
          }
          parts << render_planned_page(planned, ctx)
        end

        parts << "</form>"
        parts.join
      end

      private

      def build_render_plan(form, data)
        plan = []

        form.pages.each do |page|
          plan << { elements: page.elements, item_slices: nil }
          next unless data

          page.elements.each do |el|
            next unless el.type == ElementType::REGION

            bind = el[:bind]
            max = el[:max]
            overflow = el[:overflow]
            next if bind.nil? || max.nil? || overflow.nil?
            next unless max.is_a?(Numeric) && max >= 1

            count = bound_array_length(bind, data)
            next if count <= max

            consumed = max
            template_name = overflow.start_with?("@") ? overflow[1..] : nil
            guard = 0
            while consumed < count && (guard += 1) < 10_000
              tpl = template_name && form.templates ? form.templates[template_name] : nil
              tpl_region = tpl&.elements&.find { |e| e.type == ElementType::REGION && e.name == el.name }
              candidate_max = (tpl_region && tpl_region[:max]) || max
              page_max = candidate_max.is_a?(Numeric) && candidate_max >= 1 ? candidate_max : max

              slices = {}
              slices[el.name] = {
                start: consumed,
                count: [page_max, count - consumed].min,
                bind: bind,
              }
              elements = tpl ? tpl.elements : page.elements
              plan << { elements: elements, item_slices: slices }
              consumed += page_max

              if tpl_region && tpl_region[:overflow]&.start_with?("@")
                template_name = tpl_region[:overflow][1..]
              end
            end
          end
        end

        plan
      end

      def render_planned_page(page, ctx)
        page_index = ctx[:page_number] - 1

        parts = []
        parts << %(<div class="odin-form-page" id="odin-form-content" data-page="#{ctx[:page_number]}" ) +
                 %(style="width:#{ctx[:page_width_px]}px;height:#{ctx[:page_height_px]}px;">)

        page[:elements].each do |el|
          parts << render_element(el, page_index, ctx, page) if el.type == ElementType::IMG && el[:background]
        end
        page[:elements].each do |el|
          next if el.type == ElementType::IMG && el[:background]
          next if el.field?

          parts << render_element(el, page_index, ctx, page)
        end
        Accessibility.tab_order_sort(page[:elements].dup).each do |el|
          parts << render_element(el, page_index, ctx, page)
        end

        parts << "</div>"
        parts.join
      end

      def render_element(el, page_index, ctx, page)
        unit = ctx[:unit]
        case el.type
        when ElementType::LINE     then render_line(el, unit)
        when ElementType::RECT     then render_rect(el, unit)
        when ElementType::CIRCLE   then render_circle(el, unit)
        when ElementType::ELLIPSE  then render_ellipse(el, unit)
        when ElementType::POLYGON  then render_polygon(el, unit)
        when ElementType::POLYLINE then render_polyline(el, unit)
        when ElementType::PATH     then render_path(el, unit)
        when ElementType::TEXT     then render_text(el, ctx)
        when ElementType::IMG      then render_image(el, ctx)
        when ElementType::BARCODE  then render_barcode(el, ctx)
        when ElementType::FIELD_TEXT        then render_text_field(el, page_index, ctx)
        when ElementType::FIELD_CHECKBOX    then render_checkbox(el, page_index, ctx)
        when ElementType::FIELD_RADIO       then render_radio(el, page_index, ctx)
        when ElementType::FIELD_SELECT      then render_select(el, page_index, ctx)
        when ElementType::FIELD_MULTISELECT then render_multiselect(el, page_index, ctx)
        when ElementType::FIELD_DATE        then render_date(el, page_index, ctx)
        when ElementType::FIELD_SIGNATURE   then render_signature(el, page_index, ctx)
        when ElementType::REGION   then render_region(el, ctx, page)
        else ""
        end
      end

      # ── Interpolation ─────────────────────────────────────────────────────

      def interpolate(text, ctx)
        text.gsub(/\{@odin\.([a-z_]+)\}/) do
          case Regexp.last_match(1)
          when "page" then ctx[:page_number].to_s
          when "total_pages" then ctx[:total_pages].to_s
          else Regexp.last_match(0)
          end
        end
      end

      # ── Geometric ─────────────────────────────────────────────────────────

      def svg_wrap(inner)
        %(<svg class="odin-form-element" style="position:absolute;left:0;top:0;width:100%;height:100%;overflow:visible;">) +
          inner + "</svg>"
      end

      def stroke_color(el)
        el[:stroke] || "#000000"
      end

      def stroke_width_px(el, unit)
        el[:"stroke-width"] ? Units.to_pixels(el[:"stroke-width"], unit) : 1
      end

      def render_line(el, unit)
        x1 = Units.to_pixels(el[:x1], unit)
        y1 = Units.to_pixels(el[:y1], unit)
        x2 = Units.to_pixels(el[:x2], unit)
        y2 = Units.to_pixels(el[:y2], unit)
        svg_wrap(%(<line x1="#{x1}" y1="#{y1}" x2="#{x2}" y2="#{y2}" stroke="#{stroke_color(el)}" stroke-width="#{stroke_width_px(el, unit)}"/>))
      end

      def render_rect(el, unit)
        x = Units.to_pixels(el[:x], unit)
        y = Units.to_pixels(el[:y], unit)
        w = Units.to_pixels(el[:w], unit)
        h = Units.to_pixels(el[:h], unit)
        border = el[:stroke] ? "border:#{stroke_width_px(el, unit)}px solid #{el[:stroke]};" : ""
        bg = el[:fill] && el[:fill] != "none" ? "background:#{el[:fill]};" : ""
        rx = el[:rx] ? Units.to_pixels(el[:rx], unit) : 0
        ry = el[:ry] ? Units.to_pixels(el[:ry], unit) : 0
        radius = rx != 0 || ry != 0 ? "border-radius:#{rx}px #{ry}px;" : ""
        %(<div class="odin-form-element" style="position:absolute;left:#{x}px;top:#{y}px;width:#{w}px;height:#{h}px;#{border}#{bg}#{radius}"></div>)
      end

      def render_circle(el, unit)
        cx = Units.to_pixels(el[:cx], unit)
        cy = Units.to_pixels(el[:cy], unit)
        r = Units.to_pixels(el[:r], unit)
        fill = el[:fill] || "none"
        svg_wrap(%(<circle cx="#{cx}" cy="#{cy}" r="#{r}" stroke="#{stroke_color(el)}" stroke-width="#{stroke_width_px(el, unit)}" fill="#{fill}"/>))
      end

      def render_ellipse(el, unit)
        cx = Units.to_pixels(el[:cx], unit)
        cy = Units.to_pixels(el[:cy], unit)
        rx = Units.to_pixels(el[:rx], unit)
        ry = Units.to_pixels(el[:ry], unit)
        fill = el[:fill] || "none"
        svg_wrap(%(<ellipse cx="#{cx}" cy="#{cy}" rx="#{rx}" ry="#{ry}" stroke="#{stroke_color(el)}" stroke-width="#{stroke_width_px(el, unit)}" fill="#{fill}"/>))
      end

      def render_polygon(el, unit)
        points = convert_points(el[:points], unit)
        fill = el[:fill] || "none"
        svg_wrap(%(<polygon points="#{points}" stroke="#{stroke_color(el)}" stroke-width="#{stroke_width_px(el, unit)}" fill="#{fill}"/>))
      end

      def render_polyline(el, unit)
        points = convert_points(el[:points], unit)
        svg_wrap(%(<polyline points="#{points}" stroke="#{stroke_color(el)}" stroke-width="#{stroke_width_px(el, unit)}" fill="none"/>))
      end

      def render_path(el, unit)
        fill = el[:fill] || "none"
        svg_wrap(%(<path d="#{el[:d]}" stroke="#{stroke_color(el)}" stroke-width="#{stroke_width_px(el, unit)}" fill="#{fill}"/>))
      end

      # ── Content ───────────────────────────────────────────────────────────

      def render_text(el, ctx)
        unit = ctx[:unit]
        x = Units.to_pixels(el[:x], unit)
        y = Units.to_pixels(el[:y], unit)
        font_size = el[:"font-size"] ? Units.to_pixels(el[:"font-size"], "pt") : Units.to_pixels(12, "pt")
        font_weight = el[:"font-weight"] || "normal"
        color = el[:color] || "#000000"
        font_family = el[:"font-family"] ? "font-family:#{el[:"font-family"]};" : ""
        font_style = el[:"font-style"] == "italic" ? "font-style:italic;" : ""
        text_align = el[:"text-align"] ? "text-align:#{el[:"text-align"]};" : ""
        content = interpolate(el[:content], ctx)
        %(<span class="odin-form-element" style="position:absolute;left:#{x}px;top:#{y}px;font-size:#{font_size}px;font-weight:#{font_weight};color:#{color};#{font_family}#{font_style}#{text_align}">#{escape_html(content)}</span>)
      end

      def render_image(el, ctx)
        unit = ctx[:unit]
        x = Units.to_pixels(el[:x], unit)
        y = Units.to_pixels(el[:y], unit)
        w = Units.to_pixels(el[:w], unit)
        h = Units.to_pixels(el[:h], unit)
        src = image_src_to_data_uri(el[:src])
        alt = interpolate(el[:alt], ctx)
        z_index = el[:background] ? "z-index:0;" : ""
        %(<img class="odin-form-element" src="#{escape_attr(src)}" alt="#{escape_attr(alt)}" style="position:absolute;left:#{x}px;top:#{y}px;width:#{w}px;height:#{h}px;#{z_index}">)
      end

      def render_barcode(el, ctx)
        unit = ctx[:unit]
        x = Units.to_pixels(el[:x], unit)
        y = Units.to_pixels(el[:y], unit)
        w = Units.to_pixels(el[:w], unit)
        h = Units.to_pixels(el[:h], unit)
        alt = interpolate(el[:alt], ctx)
        content = interpolate(el[:content], ctx)
        %(<div class="odin-form-element odin-form-barcode" role="img" aria-label="#{escape_attr(alt)}" ) +
          %(data-barcode-type="#{escape_attr(el[:barcodeType])}" data-content="#{escape_attr(content)}" ) +
          %(style="position:absolute;left:#{x}px;top:#{y}px;width:#{w}px;height:#{h}px;"></div>)
      end

      def image_src_to_data_uri(src)
        return src unless src.start_with?("^")

        rest = src[1..]
        colon = rest.index(":")
        return "data:image/png;base64,#{rest}" if colon.nil?

        format = rest[0...colon]
        b64 = rest[(colon + 1)..]
        "data:image/#{format};base64,#{b64}"
      end

      # ── Fields ────────────────────────────────────────────────────────────

      def field_box(el, ctx)
        unit = ctx[:unit]
        {
          x: Units.to_pixels(el[:x], unit),
          y: Units.to_pixels(el[:y], unit),
          w: Units.to_pixels(el[:w], unit),
          h: Units.to_pixels(el[:h], unit),
        }
      end

      def aria_required_attr(attrs)
        attrs["aria-required"] ? ' aria-required="true"' : ""
      end

      def render_text_field(el, page_index, ctx)
        box = field_box(el, ctx)
        attrs = Accessibility.field_aria_attrs(el, page_index)
        input_id = Accessibility.generate_field_id(el.name, page_index)
        value = el[:value] || lookup_bound_value(el, ctx[:data])
        value_attr = value.nil? ? "" : %( value="#{escape_attr(value)}")
        required_attr = el[:required] ? " required" : ""
        readonly_attr = el[:readonly] ? " readonly" : ""
        placeholder_attr = el[:placeholder] ? %( placeholder="#{escape_attr(el[:placeholder])}") : ""
        input_type = el[:inputType] || "text"

        %(<div class="odin-form-element" style="position:absolute;left:#{box[:x]}px;top:#{box[:y]}px;width:#{box[:w]}px;height:#{box[:h]}px;">) +
          Accessibility.field_label_html(interpolate(el[:label], ctx), input_id) +
          %(<input type="#{escape_attr(input_type)}" class="odin-form-input" id="#{attrs['id']}" aria-label="#{escape_attr(interpolate(attrs['aria-label'], ctx))}"#{aria_required_attr(attrs)}#{value_attr}#{required_attr}#{readonly_attr}#{placeholder_attr}>) +
          "</div>"
      end

      def render_checkbox(el, page_index, ctx)
        box = field_box(el, ctx)
        attrs = Accessibility.field_aria_attrs(el, page_index)
        input_id = Accessibility.generate_field_id(el.name, page_index)
        bound = lookup_bound_value(el, ctx[:data])
        is_checked = el.key?(:checked) ? el[:checked] : (bound == "true")
        checked = is_checked ? " checked" : ""

        %(<div class="odin-form-element" style="position:absolute;left:#{box[:x]}px;top:#{box[:y]}px;width:#{box[:w]}px;height:#{box[:h]}px;">) +
          Accessibility.field_label_html(interpolate(el[:label], ctx), input_id) +
          %(<input type="checkbox" class="odin-form-checkbox" id="#{attrs['id']}" aria-label="#{escape_attr(interpolate(attrs['aria-label'], ctx))}"#{aria_required_attr(attrs)}#{checked}>) +
          "</div>"
      end

      def render_radio(el, page_index, ctx)
        box = field_box(el, ctx)
        attrs = Accessibility.field_aria_attrs(el, page_index)
        value = lookup_bound_value(el, ctx[:data])
        checked = value == el[:value] ? " checked" : ""

        radio_html =
          %(<input type="radio" class="odin-form-radio" id="#{attrs['id']}" name="#{escape_attr(el[:group])}" value="#{escape_attr(el[:value])}" aria-label="#{escape_attr(interpolate(attrs['aria-label'], ctx))}"#{aria_required_attr(attrs)}#{checked}>) +
          %(<label for="#{attrs['id']}">#{escape_html(interpolate(el[:label], ctx))}</label>)

        %(<div class="odin-form-element" style="position:absolute;left:#{box[:x]}px;top:#{box[:y]}px;width:#{box[:w]}px;height:#{box[:h]}px;">) +
          Accessibility.field_group_html(el[:group], interpolate(el[:label], ctx), radio_html) +
          "</div>"
      end

      def render_select(el, page_index, ctx)
        box = field_box(el, ctx)
        attrs = Accessibility.field_aria_attrs(el, page_index)
        input_id = Accessibility.generate_field_id(el.name, page_index)
        value = el[:selected] || lookup_bound_value(el, ctx[:data])

        options_html = +""
        options_html << %(<option value="">#{escape_html(el[:placeholder])}</option>) if el[:placeholder]
        (el[:options] || []).each do |opt|
          selected = value == opt ? " selected" : ""
          options_html << %(<option value="#{escape_attr(opt)}"#{selected}>#{escape_html(opt)}</option>)
        end

        %(<div class="odin-form-element" style="position:absolute;left:#{box[:x]}px;top:#{box[:y]}px;width:#{box[:w]}px;height:#{box[:h]}px;">) +
          Accessibility.field_label_html(interpolate(el[:label], ctx), input_id) +
          %(<select class="odin-form-select" id="#{attrs['id']}" aria-label="#{escape_attr(interpolate(attrs['aria-label'], ctx))}"#{aria_required_attr(attrs)}>) +
          options_html +
          "</select>" +
          "</div>"
      end

      def render_multiselect(el, page_index, ctx)
        box = field_box(el, ctx)
        attrs = Accessibility.field_aria_attrs(el, page_index)
        input_id = Accessibility.generate_field_id(el.name, page_index)
        selected_values =
          if el.key?(:selected)
            Array(el[:selected])
          else
            value = lookup_bound_value(el, ctx[:data])
            value ? value.split(",").map(&:strip) : []
          end

        options_html = +""
        (el[:options] || []).each do |opt|
          selected = selected_values.include?(opt) ? " selected" : ""
          options_html << %(<option value="#{escape_attr(opt)}"#{selected}>#{escape_html(opt)}</option>)
        end

        %(<div class="odin-form-element" style="position:absolute;left:#{box[:x]}px;top:#{box[:y]}px;width:#{box[:w]}px;height:#{box[:h]}px;">) +
          Accessibility.field_label_html(interpolate(el[:label], ctx), input_id) +
          %(<select multiple class="odin-form-select" id="#{attrs['id']}" aria-label="#{escape_attr(interpolate(attrs['aria-label'], ctx))}"#{aria_required_attr(attrs)}>) +
          options_html +
          "</select>" +
          "</div>"
      end

      def render_date(el, page_index, ctx)
        box = field_box(el, ctx)
        attrs = Accessibility.field_aria_attrs(el, page_index)
        input_id = Accessibility.generate_field_id(el.name, page_index)
        value = el[:value] || lookup_bound_value(el, ctx[:data])
        value_attr = value.nil? ? "" : %( value="#{escape_attr(value)}")
        required_attr = el[:required] ? " required" : ""

        %(<div class="odin-form-element" style="position:absolute;left:#{box[:x]}px;top:#{box[:y]}px;width:#{box[:w]}px;height:#{box[:h]}px;">) +
          Accessibility.field_label_html(interpolate(el[:label], ctx), input_id) +
          %(<input type="date" class="odin-form-input" id="#{attrs['id']}" aria-label="#{escape_attr(interpolate(attrs['aria-label'], ctx))}"#{aria_required_attr(attrs)}#{value_attr}#{required_attr}>) +
          "</div>"
      end

      def render_signature(el, page_index, ctx)
        box = field_box(el, ctx)
        attrs = Accessibility.field_aria_attrs(el, page_index)
        input_id = Accessibility.generate_field_id(el.name, page_index)

        %(<div class="odin-form-element" style="position:absolute;left:#{box[:x]}px;top:#{box[:y]}px;width:#{box[:w]}px;height:#{box[:h]}px;">) +
          Accessibility.field_label_html(interpolate(el[:label], ctx), input_id) +
          %(<div class="odin-form-signature" id="#{attrs['id']}" aria-label="#{escape_attr(interpolate(attrs['aria-label'], ctx))}"#{aria_required_attr(attrs)} role="img" tabindex="0" style="width:100%;height:100%;"></div>) +
          "</div>"
      end

      # ── Region ────────────────────────────────────────────────────────────

      def render_region(el, ctx, page)
        unit = ctx[:unit]
        region_x = Units.to_pixels(el[:x], unit)
        region_y = Units.to_pixels(el[:y], unit)
        region_w = Units.to_pixels(el[:w], unit)
        region_h = Units.to_pixels(el[:h], unit)

        slice = page[:item_slices] && page[:item_slices][el.name]
        bind = el[:bind] || (slice && slice[:bind])
        total = bind ? bound_array_length(bind, ctx[:data]) : 0
        start = 0
        if slice
          start = slice[:start]
          count = slice[:count]
        elsif total.positive?
          count = el[:max] ? [el[:max], total].min : total
        else
          count = 1
        end

        parts = []
        parts << %(<div class="odin-form-element odin-form-region" data-region="#{escape_attr(el.name)}" ) +
                 %(style="position:absolute;left:#{region_x}px;top:#{region_y}px;width:#{region_w}px;height:#{region_h}px;">)

        count.times do |i|
          item_index = start + i
          item_bind = bind ? "#{bind}[#{item_index}]" : nil
          (el[:children] || []).each do |child|
            parts << render_region_child(child, i, item_bind, ctx)
          end
        end

        parts << "</div>"
        parts.join
      end

      def render_region_child(child, i, item_bind, ctx)
        y_offset = child[:"y-offset"] || 0
        x_offset = child[:"x-offset"] || 0
        dx = child[:x] + (x_offset * i)
        dy = child[:y] + (y_offset * i)

        if child.type == ElementType::TEXT
          return render_text(FormElement.new(child.props.merge(x: dx, y: dy)), ctx)
        end

        resolved_bind = resolve_relative_bind(child[:bind], item_bind) || child[:bind]
        rebased = FormElement.new(child.props.merge(
          x: dx, y: dy,
          name: "#{child.name}_#{i}",
          bind: resolved_bind
        ))
        child_page_index = -1 - i
        render_element(rebased, child_page_index, ctx, { elements: [] })
      end

      def resolve_relative_bind(bind, item_bind)
        return nil if bind.nil? || bind.empty?

        if bind.start_with?("@.")
          return nil if item_bind.nil?

          return "#{item_bind}.#{bind[2..]}"
        end
        bind
      end

      def bound_array_length(bind, data)
        return 0 if data.nil?

        path = bind.start_with?("@") ? bind[1..] : bind
        re = /\A#{Regexp.escape(path)}\[(\d+)\](?:\.|\z)/
        max = -1
        data.paths.each do |p|
          m = re.match(p)
          if m
            idx = m[1].to_i
            max = idx if idx > max
          end
        end
        max + 1
      end

      # ── Data binding ──────────────────────────────────────────────────────

      def lookup_bound_value(el, data)
        bind = el[:bind]
        return nil if data.nil? || bind.nil? || bind.empty?

        path = bind.start_with?("@") ? bind[1..] : bind
        return nil if path.empty?

        val = data.get(path)
        return nil if val.nil?

        case val.type
        when :string then val.value
        when :number, :integer, :boolean then val.value.to_s
        end
      end

      # ── Utilities ─────────────────────────────────────────────────────────

      def escape_html(str)
        str.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
      end

      def escape_attr(str)
        str.to_s.gsub("&", "&amp;").gsub('"', "&quot;").gsub("'", "&#39;").gsub("<", "&lt;").gsub(">", "&gt;")
      end

      def convert_points(points, unit)
        points.to_s.strip.split(/\s+/).map do |pair|
          x, y = pair.split(",")
          if x.nil? || y.nil?
            pair
          else
            "#{Units.to_pixels(x.to_f, unit)},#{Units.to_pixels(y.to_f, unit)}"
          end
        end.join(" ")
      end
    end
  end
end
