# odin-foundation

[![Gem](https://img.shields.io/gem/v/odin-foundation)](https://rubygems.org/gems/odin-foundation) [![License](https://img.shields.io/badge/license-Apache--2.0-blue)](https://github.com/odin-foundation/odin-core-ruby/blob/main/LICENSE)

Official Ruby SDK for [ODIN](https://odin.foundation) (Open Data Interchange Notation) — a canonical data model for transporting meaning between systems, standards, and AI.

## Install

```bash
gem install odin-foundation
```

Or add to your `Gemfile`:

```ruby
gem 'odin-foundation', '~> 1.0'
```

**Requires Ruby 3.1+**

## Quick Start

```ruby
require 'odin'

doc = Odin.parse(<<~ODIN)
  {policy}
  number = "PAP-2024-001"
  effective = 2024-06-01
  premium = #$747.50
  active = ?true
ODIN

puts doc["policy.number"]   # "PAP-2024-001"
puts doc["policy.premium"]  # 747.50

text = Odin.stringify(doc)
```

## Core API

| Method | Description | Example |
|--------|-------------|---------|
| `Odin.parse(text)` | Parse ODIN text into a document | `doc = Odin.parse(src)` |
| `Odin.stringify(doc)` | Serialize document to ODIN text | `text = Odin.stringify(doc)` |
| `Odin.canonicalize(doc)` | Deterministic bytes for hashing/signatures | `bytes = Odin.canonicalize(doc)` |
| `Odin.validate(doc, schema)` | Validate against an ODIN schema | `result = Odin.validate(doc, schema)` |
| `Odin.parse_schema(text)` | Parse a schema definition | `schema = Odin.parse_schema(src)` |
| `Odin.diff(a, b)` | Structured diff between two documents | `changes = Odin.diff(doc_a, doc_b)` |
| `Odin.patch(doc, diff)` | Apply a diff to a document | `updated = Odin.patch(doc, changes)` |
| `Odin.parse_transform(text)` | Parse a transform specification | `tx = Odin.parse_transform(src)` |
| `Odin.execute_transform(tx, source)` | Run a transform on data | `out = Odin.execute_transform(tx, doc)` |
| `Odin.transform(text, source)` | Parse and execute in one step | `out = Odin.transform(tx_text, doc)` |
| `doc.to_json` | Export to JSON | `json = doc.to_json` |
| `doc.to_xml` | Export to XML | `xml = doc.to_xml` |
| `doc.to_csv` | Export to CSV | `csv = doc.to_csv` |
| `Odin.stringify(doc)` | Export to ODIN | `odin_str = Odin.stringify(doc)` |
| `Odin.builder` | Fluent document builder | `Odin.builder.section("policy")...` |

## Schema Validation

```ruby
require 'odin'

schema = Odin.parse_schema(<<~ODIN)
  {policy}
  !number : string
  !effective : date
  !premium : currency
  active : boolean
ODIN

doc = Odin.parse(source)
result = Odin.validate(doc, schema)

unless result.valid?
  result.errors.each { |e| puts e }
end
```

## Transforms

```ruby
require 'odin'

transform = Odin.parse_transform(<<~ODIN)
  map policy -> record
    policy.number -> record.id
    policy.premium -> record.amount
ODIN

result = Odin.execute_transform(transform, doc)

# Or use the shorthand:
result = Odin.transform(transform_text, doc)
```

## Export

```ruby
odin = Odin.stringify(doc) # ODIN string
json = doc.to_json         # JSON string
xml  = doc.to_xml          # XML string
csv  = doc.to_csv          # CSV string
```

## Builder

```ruby
doc = Odin.builder
  .section("policy")
  .set("number", "PAP-2024-001")
  .set("effective", Date.new(2024, 6, 1))
  .set("premium", Odin.currency(747.50))
  .set("active", true)
  .build
```

## Testing

Tests use [RSpec](https://rspec.info/) and the shared golden test suite:

```bash
bundle exec rspec
```

## Links

- [.Odin Foundation Website](https://odin.foundation)
- [GitHub](https://github.com/odin-foundation/odin)
- [Golden Test Suite](https://github.com/odin-foundation/odin/tree/main/sdk/golden)
- [License (Apache 2.0)](https://github.com/odin-foundation/odin/blob/main/LICENSE)
