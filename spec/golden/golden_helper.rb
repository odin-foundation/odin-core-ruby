# frozen_string_literal: true

def find_golden_dir
  candidates = [
    File.expand_path("../../../golden", __dir__),
    File.expand_path("../../../../golden", __dir__),
  ]
  candidates.each do |p|
    return p if File.directory?(p)
  end
  raise "Cannot find sdk/golden/ directory. Tried: #{candidates.join(', ')}"
end
