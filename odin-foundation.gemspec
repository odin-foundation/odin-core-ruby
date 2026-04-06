# frozen_string_literal: true

require_relative "lib/odin/version"

Gem::Specification.new do |s|
  s.name        = "odin-foundation"
  s.version     = Odin::VERSION
  s.summary     = "ODIN (Open Data Interchange Notation) SDK for Ruby"
  s.description = "Ruby SDK for parsing, serializing, validating, and transforming ODIN documents"
  s.authors     = ["ODIN Foundation"]
  s.homepage    = "https://odin.foundation"
  s.license     = "MIT"
  s.required_ruby_version = ">= 3.1"
  s.files       = Dir["lib/**/*.rb"]

  s.add_dependency "bigdecimal"
  s.add_dependency "base64"
  s.add_dependency "csv"
  s.add_dependency "rexml"

  s.add_development_dependency "rspec", "~> 3.12"
end
