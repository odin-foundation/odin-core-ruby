# frozen_string_literal: true

require "set"

module Odin
  module Diff
    class Patcher
      def apply_patch(doc, diff)
        return clone_document(doc) if diff.empty?

        builder = Types::OdinDocumentBuilder.new

        # Build set of paths to skip (removed + move sources)
        removed_paths = Set.new(diff.removed.map(&:path))
        moved_from_paths = Set.new(diff.moved.map(&:from_path))
        changed_paths = Set.new(diff.changed.map(&:path))
        skip_paths = removed_paths | moved_from_paths

        # 1. Copy existing assignments (except removed, moved-from, and changed)
        doc.each_assignment do |path, value|
          next if skip_paths.include?(path) || changed_paths.include?(path)

          builder.set(path, value, modifiers: doc.modifiers_for(path))
        end

        # 2. Apply changes (update values and/or modifiers)
        diff.changed.each do |change|
          builder.set(change.path, change.new_value, modifiers: change.new_modifiers)
        end

        # 3. Apply moves (add at new path)
        diff.moved.each do |move|
          mods = doc.modifiers_for(move.from_path)
          builder.set(move.to_path, move.value, modifiers: mods)
        end

        # 4. Apply additions
        diff.added.each do |entry|
          builder.set(entry.path, entry.value, modifiers: entry.modifiers)
        end

        # 5. Copy metadata
        doc.each_metadata do |key, value|
          builder.set_metadata(key, value)
        end

        builder.build
      end

      private

      def clone_document(doc)
        builder = Types::OdinDocumentBuilder.new
        doc.each_assignment do |path, value|
          builder.set(path, value, modifiers: doc.modifiers_for(path))
        end
        doc.each_metadata do |key, value|
          builder.set_metadata(key, value)
        end
        builder.build
      end
    end
  end
end
