# frozen_string_literal: true

module Odin
  module Serialization
    class Stringify
      # Lightweight node for path tree — much cheaper than Hash
      PathNode = Struct.new(:name, :full_path, :children, :array_indices, :value, :modifiers,
                            :has_array, :leaf_count) do
        def initialize(name, full_path)
          super(name, full_path, {}, nil, nil, nil, false, -1)
        end
      end

      def initialize(options = {})
        @use_headers = options.fetch(:use_headers, true)
        @use_tabular = options.fetch(:use_tabular, true)
        @sort_paths  = options.fetch(:sort_paths, false)
        @line_ending = options.fetch(:line_ending, "\n")
        @include_comments = options.fetch(:include_comments, true)
      end

      def stringify(doc)
        lines = []

        # Get direct access to internal hashes — avoids method dispatch per path
        assignments = doc.assignments
        metadata = doc.metadata
        modifiers = doc.all_modifiers
        comments = @include_comments ? doc.all_comments : nil

        # Separate metadata and data paths
        meta_paths = []
        data_paths = []

        assignments.each_key do |path|
          if path.getbyte(0) == 36 && path.getbyte(1) == 46 # "$."
            meta_paths << path
          else
            data_paths << path
          end
        end

        # Also add from metadata map
        unless metadata.empty?
          metadata.each_key do |key|
            p = "$.#{key}"
            meta_paths << p unless assignments.key?(p)
          end
        end

        meta_paths.sort! if @sort_paths

        # Output metadata
        unless meta_paths.empty?
          lines << "{$}" if @use_headers
          meta_paths.each do |path|
            value = assignments[path] || metadata[path[2..]]
            next unless value

            display_path = @use_headers ? path[2..] : path
            lines << format_assignment(display_path, value, modifiers[path], nil)
          end
          lines << "{}" if @use_headers && !data_paths.empty?
        end

        # Output data assignments
        if @use_headers && !@sort_paths && shallow_document?(data_paths)
          output_flat_sections(assignments, modifiers, comments, data_paths, lines)
        elsif @use_headers || @use_tabular
          output_hierarchical(assignments, modifiers, comments, data_paths, lines)
        else
          data_paths = data_paths.sort if @sort_paths
          data_paths.each do |path|
            value = assignments[path]
            next unless value

            comment = comments ? comments[path] : nil
            lines << format_assignment(path, value, modifiers[path], comment)
          end
        end

        result = lines.join(@line_ending)
        result << @line_ending unless lines.empty?
        result
      end

      private

      # ─────────────────────────────────────────────────────────────────────
      # Shallow Document Fast Path
      # ─────────────────────────────────────────────────────────────────────

      def shallow_document?(data_paths)
        data_paths.each do |path|
          return false if path.include?("[")
          first_dot = path.index(".")
          return false if first_dot && path.index(".", first_dot + 1)
        end
        true
      end

      def output_flat_sections(assignments, modifiers, comments, data_paths, lines)
        current_section = nil

        data_paths.each do |path|
          dot_pos = path.index(".")
          if dot_pos && dot_pos > 0
            section = path[0...dot_pos]
            field = path[(dot_pos + 1)..]
          else
            section = nil
            field = path
          end

          if section != current_section
            lines << "{#{section}}" if section
            current_section = section
          end

          comment = comments ? comments[path] : nil
          lines << format_assignment(field, assignments[path], modifiers[path], comment)
        end
      end

      # ─────────────────────────────────────────────────────────────────────
      # Hierarchical Output
      # ─────────────────────────────────────────────────────────────────────

      def output_hierarchical(assignments, modifiers, comments, data_paths, lines)
        tree = build_path_tree(assignments, modifiers, data_paths)

        child_names = tree.children.keys
        child_names.sort! if @sort_paths

        scalars = []
        groups = []

        child_names.each do |name|
          child = tree.children[name]
          if child.value
            scalars << name
          else
            groups << name
          end
        end

        scalars.each do |name|
          child = tree.children[name]
          comment = comments ? comments[child.full_path] : nil
          lines << format_assignment(child.full_path, child.value, child.modifiers, comment)
        end

        single_leaf_groups = []
        header_groups = []

        groups.each do |name|
          child = tree.children[name]
          has_arr = child.has_array
          if has_arr || (@use_headers && has_multiple_leaf_descendants?(child))
            header_groups << name
          else
            single_leaf_groups << name
          end
        end

        single_leaf_groups.each do |name|
          child = tree.children[name]
          output_node(comments, child, "", lines)
        end

        header_groups.each do |name|
          child = tree.children[name]

          if child.has_array && @use_tabular && child.array_indices
            next if try_output_as_tabular(comments, child, "", lines)
          end

          if child.has_array
            output_node(comments, child, "", lines)
          elsif @use_headers && has_multiple_leaf_descendants?(child)
            lines << "{#{child.full_path}}"
            output_node(comments, child, child.full_path, lines)
          else
            output_node(comments, child, "", lines)
          end
        end
      end

      def output_node(comments, node, header_path, lines, inside_relative_header: false)
        if node.value
          relative_path = if header_path.empty?
                            node.full_path
                          else
                            node.full_path[(header_path.length + 1)..]
                          end
          comment = comments ? comments[node.full_path] : nil
          lines << format_assignment(relative_path, node.value, node.modifiers, comment)
          return
        end

        return if node.children.empty?

        child_names = node.children.keys
        if @sort_paths
          child_names = child_names.sort do |a, b|
            a_arr = a.getbyte(0) == 91
            b_arr = b.getbyte(0) == 91
            if a_arr && b_arr
              parse_bracket_index(a) <=> parse_bracket_index(b)
            elsif a_arr
              1
            elsif b_arr
              -1
            else
              a <=> b
            end
          end
        end

        array_children = []
        regular_children = []
        subheader_children = []

        child_names.each do |name|
          child = node.children[name]
          if name.getbyte(0) == 91 # [
            array_children << name
            next
          end

          should_subheader = @use_headers &&
                             child.value.nil? &&
                             !child.has_array &&
                             has_multiple_leaf_descendants?(child)

          if should_subheader
            subheader_children << name
          else
            regular_children << name
          end
        end

        regular_children.each do |name|
          child = node.children[name]
          output_node(comments, child, header_path, lines)
        end

        unless array_children.empty?
          if @use_tabular && node.array_indices
            unless try_output_as_tabular(comments, node, header_path, lines)
              output_array_children(comments, array_children, node, header_path, lines)
            end
          else
            output_array_children(comments, array_children, node, header_path, lines)
          end
        end

        subheader_children.each do |name|
          child = node.children[name]
          is_direct = header_path &&
                      !header_path.empty? &&
                      child.full_path.start_with?("#{header_path}.") &&
                      !child.full_path[(header_path.length + 1)..].include?(".")
          can_use_relative = is_direct && !inside_relative_header

          if can_use_relative
            rel_name = child.full_path[(header_path.length + 1)..]
            lines << "{.#{rel_name}}"
            output_node(comments, child, child.full_path, lines, inside_relative_header: true)
          else
            lines << "{#{child.full_path}}"
            output_node(comments, child, child.full_path, lines, inside_relative_header: false)
          end
        end
      end

      def output_array_children(comments, array_children, node, header_path, lines)
        array_children.each do |name|
          child = node.children[name]
          if @use_headers && has_multiple_leaf_descendants?(child)
            lines << "{#{child.full_path}}"
            output_node(comments, child, child.full_path, lines)
          else
            output_node(comments, child, header_path, lines)
          end
        end
      end

      # ─────────────────────────────────────────────────────────────────────
      # Tabular Output
      # ─────────────────────────────────────────────────────────────────────

      def try_output_as_tabular(comments, node, current_header, lines)
        if primitive_array_node?(node)
          return try_output_as_primitive_tabular(node, current_header, lines)
        end

        items = {}
        all_columns = []
        col_set = {}

        node.children.each do |child_name, child|
          next unless child_name.getbyte(0) == 91

          index = parse_bracket_index(child_name)
          next if index < 0

          fields = {}
          return false unless collect_tabular_fields(child, "", fields)
          return false if fields.empty?

          fields.each_key do |col|
            unless col_set.key?(col)
              col_set[col] = true
              all_columns << col
            end
          end
          items[index] = fields
        end

        return false if items.empty?

        indices = items.keys.sort
        indices.each_with_index do |idx, i|
          return false if idx != i
        end

        # Reject tabular if any indexed sub-array column (`field[N]`) is sparse —
        # padding shorter rows with empty cells loses to the nested record-block form.
        all_columns.each do |col|
          next unless col.end_with?("]")

          open_idx = col.rindex("[")
          next if open_idx.nil? || open_idx <= 0

          inner = col[(open_idx + 1)...(col.length - 1)]
          next if inner.empty? || !inner.match?(/\A\d+\z/)

          items.each_value do |fields|
            return false unless fields.key?(col)
          end
        end

        columns = all_columns
        columns.sort! if @sort_paths

        header_path = if current_header && !current_header.empty?
                        ".#{node.full_path[(current_header.length + 1)..]}[]"
                      else
                        "#{node.full_path}[]"
                      end

        col_str = format_columns_with_relative(columns)
        lines << "{#{header_path} : #{col_str}}"

        indices.length.times do |i|
          fields = items[i]
          values = columns.map do |col|
            field = fields[col]
            field ? Utils::FormatUtils.format_value(field) : ""
          end
          lines << values.join(", ")
        end

        true
      end

      def try_output_as_primitive_tabular(node, current_header, lines)
        items = {}

        node.children.each do |child_name, child|
          next unless child_name.getbyte(0) == 91

          index = parse_bracket_index(child_name)
          next if index < 0
          return false unless child.value

          items[index] = child.value
        end

        return false if items.empty?

        indices = items.keys.sort
        indices.each_with_index do |idx, i|
          return false if idx != i
        end

        header_path = if current_header && !current_header.empty?
                        ".#{node.full_path[(current_header.length + 1)..]}[]"
                      else
                        "#{node.full_path}[]"
                      end

        lines << "{#{header_path} : ~}"
        indices.each do |i|
          lines << Utils::FormatUtils.format_value(items[i])
        end

        true
      end

      def primitive_array_node?(node)
        has_items = false
        node.children.each do |name, child|
          next unless name.getbyte(0) == 91
          has_items = true
          return false if child.value.nil? || !child.children.empty?
          return false unless primitive_value?(child.value)
          return false if child.modifiers
        end
        has_items
      end

      def collect_tabular_fields(node, prefix, fields)
        node.children.each do |field_name, field_node|
          col_name = prefix.empty? ? field_name : "#{prefix}.#{field_name}"

          if field_node.value
            return false unless primitive_value?(field_node.value)
            return false if field_node.modifiers
            fields[col_name] = field_node.value
          else
            return false unless prefix.empty?

            field_node.children.each do |child_key, child_node|
              return false unless child_node.value
              return false unless child_node.children.empty?
              return false unless primitive_value?(child_node.value)
              return false if child_node.modifiers

              if child_key.getbyte(0) == 91
                fields["#{field_name}#{child_key}"] = child_node.value
              else
                fields["#{field_name}.#{child_key}"] = child_node.value
              end
            end
          end
        end
        true
      end

      def format_columns_with_relative(columns)
        return "" if columns.empty?

        result = []
        current_parent = ""

        columns.each do |col|
          dot_idx = col.index(".")
          if dot_idx && dot_idx > 0
            parent = col[0...dot_idx]
            field = col[(dot_idx + 1)..]
            if parent == current_parent
              result << ".#{field}"
            else
              result << col
              current_parent = parent
            end
          else
            result << col
            current_parent = ""
          end
        end

        result.join(", ")
      end

      def primitive_value?(value)
        !value.is_a?(Types::OdinArray) && !value.is_a?(Types::OdinObject)
      end

      # ─────────────────────────────────────────────────────────────────────
      # Path Tree Building
      # ─────────────────────────────────────────────────────────────────────

      def build_path_tree(assignments, modifiers, paths)
        root = PathNode.new("", "")

        paths.each do |path|
          current = root
          pos = 0
          plen = path.length

          while pos < plen
            byte = path.getbyte(pos)

            if byte == 46 # .
              pos += 1
              next
            end

            # Determine segment
            if byte == 91 # [
              close = path.index("]", pos)
              seg_end = close ? close + 1 : plen
              seg = path[pos...seg_end]
              pos = seg_end
            else
              seg_start = pos
              pos += 1
              while pos < plen
                b = path.getbyte(pos)
                break if b == 46 || b == 91
                pos += 1
              end
              seg = path[seg_start...pos]
            end

            # Get or create child node
            child = current.children[seg]
            unless child
              if byte == 91
                full = current.full_path.empty? ? seg : "#{current.full_path}#{seg}"
              else
                full = current.full_path.empty? ? seg : "#{current.full_path}.#{seg}"
              end
              child = PathNode.new(seg, full)
              current.children[seg] = child
            end

            # Track array indices
            if byte == 91
              current.has_array = true
              ai = current.array_indices
              unless ai
                ai = []
                current.array_indices = ai
              end
              idx = parse_bracket_index(seg)
              ai << idx unless ai.include?(idx)
            end

            current = child
          end

          # Set value and modifiers on the leaf node
          val = assignments[path]
          current.value = val if val
          m = modifiers[path]
          current.modifiers = m if m
        end

        root
      end

      def parse_bracket_index(name)
        return -1 unless name.getbyte(0) == 91 # [
        len = name.length
        return -1 unless name.getbyte(len - 1) == 93 # ]
        return -1 if len <= 2

        n = 0
        i = 1
        while i < len - 1
          b = name.getbyte(i)
          return -1 if b < 48 || b > 57
          n = n * 10 + (b - 48)
          i += 1
        end
        n
      end

      def has_multiple_leaf_descendants?(node)
        # Use cached result if available
        lc = node.leaf_count
        return lc > 1 if lc >= 0

        count = 0
        stack = [node]
        while (n = stack.pop)
          if n.value
            count += 1
            if count > 1
              node.leaf_count = count
              return true
            end
          else
            n.children.each_value { |c| stack << c }
          end
        end
        node.leaf_count = count
        false
      end

      # ─────────────────────────────────────────────────────────────────────
      # Assignment Formatting
      # ─────────────────────────────────────────────────────────────────────

      def format_assignment(path, value, modifiers, comment)
        line = +"#{path} = "
        line << Utils::FormatUtils.format_modifier_prefix(modifiers)
        line << Utils::FormatUtils.format_value(value)
        line << " ; #{comment}" if comment && !comment.empty?
        line
      end
    end
  end
end
