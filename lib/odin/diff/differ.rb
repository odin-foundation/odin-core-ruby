# frozen_string_literal: true

require "set"

module Odin
  module Diff
    class Differ
      def compute_diff(doc_a, doc_b)
        paths_a = Set.new(doc_a.paths)
        paths_b = Set.new(doc_b.paths)

        removed = []
        changed = []
        added = []

        # 1. Find removed: in A but not in B
        (paths_a - paths_b).sort.each do |path|
          removed << Types::DiffEntry.new(
            path: path,
            value: doc_a.get(path),
            modifiers: doc_a.modifiers_for(path)
          )
        end

        # 2. Find added: in B but not in A
        (paths_b - paths_a).sort.each do |path|
          added << Types::DiffEntry.new(
            path: path,
            value: doc_b.get(path),
            modifiers: doc_b.modifiers_for(path)
          )
        end

        # 3. Find changed: in both but different value or modifiers
        (paths_a & paths_b).sort.each do |path|
          val_a = doc_a.get(path)
          val_b = doc_b.get(path)
          mod_a = doc_a.modifiers_for(path)
          mod_b = doc_b.modifiers_for(path)

          unless values_equal?(val_a, val_b) && modifiers_equal?(mod_a, mod_b)
            changed << Types::DiffChange.new(
              path: path,
              old_value: val_a,
              new_value: val_b,
              old_modifiers: mod_a,
              new_modifiers: mod_b
            )
          end
        end

        # 4. Detect moves: removed value that appears as added value
        moved = detect_moves(removed, added)

        Types::OdinDiff.new(
          added: added,
          removed: removed,
          changed: changed,
          moved: moved
        )
      end

      private

      def values_equal?(a, b)
        return a.nil? && b.nil? if a.nil? || b.nil?

        a == b
      end

      def modifiers_equal?(a, b)
        # Treat nil and NONE (all false) as equivalent
        a_req = a&.required || false
        b_req = b&.required || false
        a_conf = a&.confidential || false
        b_conf = b&.confidential || false
        a_dep = a&.deprecated || false
        b_dep = b&.deprecated || false
        a_req == b_req && a_conf == b_conf && a_dep == b_dep
      end

      def detect_moves(removed, added)
        moves = []
        removed_matched = Set.new
        added_matched = Set.new

        removed.each_with_index do |rem_entry, ri|
          next if removed_matched.include?(ri)

          added.each_with_index do |add_entry, ai|
            next if added_matched.include?(ai)

            if values_equal?(rem_entry.value, add_entry.value)
              moves << Types::DiffMove.new(
                from_path: rem_entry.path,
                to_path: add_entry.path,
                value: rem_entry.value,
                modifiers: rem_entry.modifiers
              )
              removed_matched << ri
              added_matched << ai
              break
            end
          end
        end

        # Remove matched entries from removed/added lists (mutate in-place)
        removed_matched.sort.reverse_each { |i| removed.delete_at(i) }
        added_matched.sort.reverse_each { |i| added.delete_at(i) }

        moves
      end
    end
  end
end
