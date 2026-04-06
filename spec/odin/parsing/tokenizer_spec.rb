# frozen_string_literal: true

require "spec_helper"

RSpec.describe Odin::Parsing::Tokenizer do
  TokenType = Odin::Parsing::TokenType

  def tokenize(text)
    Odin::Parsing::Tokenizer.new(text).tokenize
  end

  def find_tokens(tokens, type)
    tokens.select { |t| t.type == type }
  end

  def find_token(tokens, type)
    tokens.find { |t| t.type == type }
  end

  # ─── Structure Tokens ─────────────────────────────────────────────

  describe "structure tokens" do
    it "tokenizes header {path}" do
      tokens = tokenize("{Customer}")
      expect(find_token(tokens, TokenType::HEADER_OPEN)).not_to be_nil
      path = find_token(tokens, TokenType::PATH)
      expect(path.value).to eq("Customer")
      expect(find_token(tokens, TokenType::HEADER_CLOSE)).not_to be_nil
    end

    it "tokenizes metadata header {$}" do
      tokens = tokenize("{$}")
      expect(find_token(tokens, TokenType::HEADER_OPEN)).not_to be_nil
      path = find_token(tokens, TokenType::PATH)
      expect(path.value).to eq("$")
      expect(find_token(tokens, TokenType::HEADER_CLOSE)).not_to be_nil
    end

    it "tokenizes empty header {}" do
      tokens = tokenize("{}")
      open = find_token(tokens, TokenType::HEADER_OPEN)
      close = find_token(tokens, TokenType::HEADER_CLOSE)
      expect(open).not_to be_nil
      expect(close).not_to be_nil
      expect(find_token(tokens, TokenType::PATH)).to be_nil
    end

    it "tokenizes relative header {.relative}" do
      tokens = tokenize("{.relative}")
      path = find_token(tokens, TokenType::PATH)
      expect(path.value).to eq(".relative")
    end

    it "tokenizes nested header {Customer.Address}" do
      tokens = tokenize("{Customer.Address}")
      path = find_token(tokens, TokenType::PATH)
      expect(path.value).to eq("Customer.Address")
    end

    it "tokenizes equals sign" do
      tokens = tokenize("name = \"test\"")
      expect(find_token(tokens, TokenType::EQUALS)).not_to be_nil
    end

    it "tokenizes pipe for tabular" do
      tokens = tokenize("| col1 | col2 |")
      pipes = find_tokens(tokens, TokenType::PIPE)
      expect(pipes.length).to be >= 2
    end

    it "tokenizes newline" do
      tokens = tokenize("a\nb")
      newlines = find_tokens(tokens, TokenType::NEWLINE)
      expect(newlines.length).to eq(1)
    end

    it "treats CRLF as single newline" do
      tokens = tokenize("a\r\nb")
      newlines = find_tokens(tokens, TokenType::NEWLINE)
      expect(newlines.length).to eq(1)
    end

    it "skips UTF-8 BOM" do
      tokens = tokenize("\xEF\xBB\xBFname = \"test\"")
      expect(find_token(tokens, TokenType::ERROR)).to be_nil
      path = find_token(tokens, TokenType::PATH)
      expect(path.value).to eq("name")
    end

    it "always ends with EOF" do
      tokens = tokenize("")
      expect(tokens.last.type).to eq(TokenType::EOF)
    end

    it "tokenizes header with array index {items[0]}" do
      tokens = tokenize("{items[0]}")
      path = find_token(tokens, TokenType::PATH)
      expect(path.value).to eq("items[0]")
    end

    it "tokenizes multiple newlines" do
      tokens = tokenize("a\n\n\nb")
      newlines = find_tokens(tokens, TokenType::NEWLINE)
      expect(newlines.length).to eq(3)
    end

    it "tokenizes empty input to just EOF" do
      tokens = tokenize("")
      expect(tokens.length).to eq(1)
      expect(tokens[0].type).to eq(TokenType::EOF)
    end
  end

  # ─── String Tokens ────────────────────────────────────────────────

  describe "string tokens" do
    it "tokenizes quoted string" do
      tokens = tokenize('name = "hello"')
      str = find_token(tokens, TokenType::STRING)
      expect(str.value).to eq("hello")
    end

    it "tokenizes empty string" do
      tokens = tokenize('name = ""')
      str = find_token(tokens, TokenType::STRING)
      expect(str.value).to eq("")
    end

    it 'handles escaped quote \\"' do
      tokens = tokenize('name = "say \\"hello\\""')
      str = find_token(tokens, TokenType::STRING)
      expect(str.value).to eq('say "hello"')
    end

    it "handles escaped backslash \\\\" do
      tokens = tokenize('name = "path\\\\dir"')
      str = find_token(tokens, TokenType::STRING)
      expect(str.value).to eq("path\\dir")
    end

    it "handles escaped newline \\n" do
      tokens = tokenize('name = "line1\\nline2"')
      str = find_token(tokens, TokenType::STRING)
      expect(str.value).to eq("line1\nline2")
    end

    it "handles escaped tab \\t" do
      tokens = tokenize('name = "col1\\tcol2"')
      str = find_token(tokens, TokenType::STRING)
      expect(str.value).to eq("col1\tcol2")
    end

    it "handles escaped carriage return \\r" do
      tokens = tokenize('name = "line\\rend"')
      str = find_token(tokens, TokenType::STRING)
      expect(str.value).to eq("line\rend")
    end

    it "handles escaped null \\0" do
      tokens = tokenize('name = "null\\0char"')
      str = find_token(tokens, TokenType::STRING)
      expect(str.value).to eq("null\0char")
    end

    it "handles unicode escape \\u0041 (A)" do
      tokens = tokenize('name = "\\u0041"')
      str = find_token(tokens, TokenType::STRING)
      expect(str.value).to eq("A")
    end

    it "handles unicode escape \\u00E9 (e-acute)" do
      tokens = tokenize('name = "\\u00E9"')
      str = find_token(tokens, TokenType::STRING)
      expect(str.value).to eq("\u00E9")
    end

    it "handles surrogate pairs \\uD83D\\uDE00 (emoji)" do
      tokens = tokenize('name = "\\uD83D\\uDE00"')
      str = find_token(tokens, TokenType::STRING)
      expect(str.value).to eq("\u{1F600}")
    end

    it "tokenizes multi-line string" do
      text = "name = \"\"\"\nline1\nline2\n\"\"\""
      tokens = tokenize(text)
      str = find_token(tokens, TokenType::STRING)
      expect(str.value).to include("line1")
      expect(str.value).to include("line2")
    end

    it "multi-line preserves internal newlines" do
      text = "name = \"\"\"\nfirst\nsecond\nthird\n\"\"\""
      tokens = tokenize(text)
      str = find_token(tokens, TokenType::STRING)
      expect(str.value).to eq("first\nsecond\nthird\n")
    end

    it "unterminated string produces ERROR" do
      tokens = tokenize('name = "unclosed')
      err = find_token(tokens, TokenType::ERROR)
      expect(err).not_to be_nil
    end

    it "invalid escape produces ERROR" do
      tokens = tokenize('name = "bad\\x"')
      err = find_token(tokens, TokenType::ERROR)
      expect(err).not_to be_nil
    end

    it "handles string with multiple escapes" do
      tokens = tokenize('name = "a\\nb\\tc"')
      str = find_token(tokens, TokenType::STRING)
      expect(str.value).to eq("a\nb\tc")
    end

    it "handles string with embedded quotes around content" do
      tokens = tokenize('name = "he said \\"hi\\""')
      str = find_token(tokens, TokenType::STRING)
      expect(str.value).to eq('he said "hi"')
    end

    it "handles slash escape \\/" do
      tokens = tokenize('name = "a\\/b"')
      str = find_token(tokens, TokenType::STRING)
      expect(str.value).to eq("a/b")
    end

    it "handles empty multi-line string" do
      text = "name = \"\"\"\n\"\"\""
      tokens = tokenize(text)
      str = find_token(tokens, TokenType::STRING)
      expect(str.value).to eq("")
    end

    it "multi-line string does not process escapes" do
      text = "name = \"\"\"\n\\n literal\n\"\"\""
      tokens = tokenize(text)
      str = find_token(tokens, TokenType::STRING)
      expect(str.value).to include("\\n")
    end

    it "handles unicode capital U escape \\U00010000" do
      tokens = tokenize('name = "\\U00010000"')
      str = find_token(tokens, TokenType::STRING)
      expect(str.value).to eq("\u{10000}")
    end

    it "unterminated multi-line string produces ERROR" do
      text = "name = \"\"\"\nnever closed"
      tokens = tokenize(text)
      err = find_token(tokens, TokenType::ERROR)
      expect(err).not_to be_nil
    end

    it "string at end of line without closing quote is ERROR" do
      tokens = tokenize("name = \"no end\n")
      err = find_token(tokens, TokenType::ERROR)
      expect(err).not_to be_nil
    end

    it "handles adjacent strings in verb args" do
      tokens = tokenize('name = %concat "a" "b"')
      strs = find_tokens(tokens, TokenType::STRING)
      expect(strs.length).to eq(2)
      expect(strs[0].value).to eq("a")
      expect(strs[1].value).to eq("b")
    end
  end

  # ─── Number Tokens ───────────────────────────────────────────────

  describe "number tokens" do
    it "tokenizes #3.14 as NUMBER" do
      tokens = tokenize("val = #3.14")
      num = find_token(tokens, TokenType::NUMBER)
      expect(num.value).to eq("3.14")
    end

    it "tokenizes ##42 as INTEGER" do
      tokens = tokenize("val = ##42")
      num = find_token(tokens, TokenType::INTEGER)
      expect(num.value).to eq("42")
    end

    it "tokenizes #$99.99 as CURRENCY" do
      tokens = tokenize('val = #$99.99')
      num = find_token(tokens, TokenType::CURRENCY)
      expect(num.value).to eq("99.99")
    end

    it "tokenizes #$99.99:USD as CURRENCY with code" do
      tokens = tokenize('val = #$99.99:USD')
      num = find_token(tokens, TokenType::CURRENCY)
      expect(num.value).to eq("99.99:USD")
    end

    it "tokenizes #%50.5 as PERCENT" do
      tokens = tokenize("val = #%50.5")
      num = find_token(tokens, TokenType::PERCENT)
      expect(num.value).to eq("50.5")
    end

    it "tokenizes negative number #-3.14" do
      tokens = tokenize("val = #-3.14")
      num = find_token(tokens, TokenType::NUMBER)
      expect(num.value).to eq("-3.14")
    end

    it "tokenizes negative integer ##-42" do
      tokens = tokenize("val = ##-42")
      num = find_token(tokens, TokenType::INTEGER)
      expect(num.value).to eq("-42")
    end

    it "tokenizes scientific notation #1.5e10" do
      tokens = tokenize("val = #1.5e10")
      num = find_token(tokens, TokenType::NUMBER)
      expect(num.value).to eq("1.5e10")
    end

    it "tokenizes zero #0" do
      tokens = tokenize("val = #0")
      num = find_token(tokens, TokenType::NUMBER)
      expect(num.value).to eq("0")
    end

    it "tokenizes integer zero ##0" do
      tokens = tokenize("val = ##0")
      num = find_token(tokens, TokenType::INTEGER)
      expect(num.value).to eq("0")
    end

    it "tokenizes currency zero #$0.00" do
      tokens = tokenize('val = #$0.00')
      num = find_token(tokens, TokenType::CURRENCY)
      expect(num.value).to eq("0.00")
    end

    it "tokenizes large number #1000000" do
      tokens = tokenize("val = #1000000")
      num = find_token(tokens, TokenType::NUMBER)
      expect(num.value).to eq("1000000")
    end

    it "tokenizes scientific notation with negative exponent #1.5e-3" do
      tokens = tokenize("val = #1.5e-3")
      num = find_token(tokens, TokenType::NUMBER)
      expect(num.value).to eq("1.5e-3")
    end

    it "tokenizes scientific notation with positive exponent #1.5e+3" do
      tokens = tokenize("val = #1.5e+3")
      num = find_token(tokens, TokenType::NUMBER)
      expect(num.value).to eq("1.5e+3")
    end

    it "tokenizes negative currency #$-10.50" do
      tokens = tokenize('val = #$-10.50')
      num = find_token(tokens, TokenType::CURRENCY)
      expect(num.value).to eq("-10.50")
    end

    it "tokenizes negative currency with code #$-10.50:EUR" do
      tokens = tokenize('val = #$-10.50:EUR')
      num = find_token(tokens, TokenType::CURRENCY)
      expect(num.value).to eq("-10.50:EUR")
    end

    it "tokenizes percent zero #%0" do
      tokens = tokenize("val = #%0")
      num = find_token(tokens, TokenType::PERCENT)
      expect(num.value).to eq("0")
    end

    it "tokenizes negative percent #%-5.5" do
      tokens = tokenize("val = #%-5.5")
      num = find_token(tokens, TokenType::PERCENT)
      expect(num.value).to eq("-5.5")
    end

    it "tokenizes number with just decimal #.5" do
      tokens = tokenize("val = #.5")
      num = find_token(tokens, TokenType::NUMBER)
      expect(num.value).to eq(".5")
    end
  end

  # ─── Boolean Tokens ──────────────────────────────────────────────

  describe "boolean tokens" do
    it "tokenizes true as BOOLEAN" do
      tokens = tokenize("val = true")
      bool = find_token(tokens, TokenType::BOOLEAN)
      expect(bool.value).to eq("true")
    end

    it "tokenizes false as BOOLEAN" do
      tokens = tokenize("val = false")
      bool = find_token(tokens, TokenType::BOOLEAN)
      expect(bool.value).to eq("false")
    end

    it "tokenizes ?true as BOOLEAN" do
      tokens = tokenize("val = ?true")
      bool = find_token(tokens, TokenType::BOOLEAN)
      expect(bool.value).to eq("true")
    end

    it "tokenizes ?false as BOOLEAN" do
      tokens = tokenize("val = ?false")
      bool = find_token(tokens, TokenType::BOOLEAN)
      expect(bool.value).to eq("false")
    end

    it "strips ? prefix from boolean value" do
      tokens = tokenize("val = ?true")
      bool = find_token(tokens, TokenType::BOOLEAN)
      expect(bool.value).to eq("true")
    end

    it "?invalid produces ERROR" do
      tokens = tokenize("val = ?maybe")
      err = find_token(tokens, TokenType::ERROR)
      expect(err).not_to be_nil
    end
  end

  # ─── Null Tokens ──────────────────────────────────────────────────

  describe "null tokens" do
    it "tokenizes ~ as NULL" do
      tokens = tokenize("val = ~")
      null = find_token(tokens, TokenType::NULL)
      expect(null).not_to be_nil
      expect(null.value).to eq("~")
    end

    it "tokenizes ~ with comment" do
      tokens = tokenize("val = ~ ; null value")
      null = find_token(tokens, TokenType::NULL)
      expect(null).not_to be_nil
      comment = find_token(tokens, TokenType::COMMENT)
      expect(comment).not_to be_nil
    end
  end

  # ─── Reference Tokens ────────────────────────────────────────────

  describe "reference tokens" do
    it "tokenizes @path.to.field as REFERENCE" do
      tokens = tokenize("val = @path.to.field")
      ref = find_token(tokens, TokenType::REFERENCE)
      expect(ref.value).to eq("path.to.field")
    end

    it "tokenizes @items[0].name as REFERENCE" do
      tokens = tokenize("val = @items[0].name")
      ref = find_token(tokens, TokenType::REFERENCE)
      expect(ref.value).to eq("items[0].name")
    end

    it "tokenizes bare @ as REFERENCE with empty path" do
      tokens = tokenize("_ = @")
      ref = find_token(tokens, TokenType::REFERENCE)
      expect(ref).not_to be_nil
      expect(ref.value).to eq("")
    end

    it "tokenizes @# as ERROR" do
      tokens = tokenize("val = @#")
      err = find_token(tokens, TokenType::ERROR)
      expect(err).not_to be_nil
      expect(err.value).to include("@#")
    end

    it "tokenizes @parties[0] as REFERENCE with array index" do
      tokens = tokenize("val = @parties[0]")
      ref = find_token(tokens, TokenType::REFERENCE)
      expect(ref.value).to eq("parties[0]")
    end

    it "tokenizes deeply nested reference" do
      tokens = tokenize("val = @a.b.c.d.e")
      ref = find_token(tokens, TokenType::REFERENCE)
      expect(ref.value).to eq("a.b.c.d.e")
    end

    it "tokenizes reference with multiple array indices" do
      tokens = tokenize("val = @items[0].sub[1]")
      ref = find_token(tokens, TokenType::REFERENCE)
      expect(ref.value).to eq("items[0].sub[1]")
    end

    it "tokenizes bare @ in verb arguments" do
      tokens = tokenize("val = %upper @")
      ref = find_token(tokens, TokenType::REFERENCE)
      expect(ref).not_to be_nil
      expect(ref.value).to eq("")
    end

    it "tokenizes @ followed by space as bare reference" do
      tokens = tokenize("val = @ ; comment")
      ref = find_token(tokens, TokenType::REFERENCE)
      expect(ref.value).to eq("")
    end

    it "tokenizes @.field as relative reference" do
      tokens = tokenize("val = @.field")
      ref = find_token(tokens, TokenType::REFERENCE)
      expect(ref.value).to eq(".field")
    end
  end

  # ─── Binary Tokens ───────────────────────────────────────────────

  describe "binary tokens" do
    it "tokenizes ^SGVsbG8= as BINARY" do
      tokens = tokenize("val = ^SGVsbG8=")
      bin = find_token(tokens, TokenType::BINARY)
      expect(bin.value).to eq("SGVsbG8=")
    end

    it "tokenizes ^sha256:data as BINARY with algorithm" do
      tokens = tokenize("val = ^sha256:abc123")
      bin = find_token(tokens, TokenType::BINARY)
      expect(bin.value).to eq("sha256:abc123")
    end

    it "tokenizes ^ alone as empty BINARY" do
      tokens = tokenize("val = ^")
      bin = find_token(tokens, TokenType::BINARY)
      expect(bin).not_to be_nil
      expect(bin.value).to eq("")
    end

    it "tokenizes binary with long base64 data" do
      tokens = tokenize("val = ^SGVsbG8gV29ybGQ=")
      bin = find_token(tokens, TokenType::BINARY)
      expect(bin.value).to eq("SGVsbG8gV29ybGQ=")
    end

    it "tokenizes binary with md5 algorithm" do
      tokens = tokenize("val = ^md5:d41d8cd98f00b204e9800998ecf8427e")
      bin = find_token(tokens, TokenType::BINARY)
      expect(bin.value).to eq("md5:d41d8cd98f00b204e9800998ecf8427e")
    end
  end

  # ─── Verb Tokens ──────────────────────────────────────────────────

  describe "verb tokens" do
    it "tokenizes %upper as VERB" do
      tokens = tokenize("val = %upper @name")
      verb = find_token(tokens, TokenType::VERB)
      expect(verb.value).to eq("upper")
    end

    it "tokenizes %concat as VERB" do
      tokens = tokenize("val = %concat @first @last")
      verb = find_token(tokens, TokenType::VERB)
      expect(verb.value).to eq("concat")
    end

    it "tokenizes %&customVerb as custom VERB" do
      tokens = tokenize("val = %&customVerb @x")
      verb = find_token(tokens, TokenType::VERB)
      expect(verb.value).to eq("&customVerb")
    end

    it "tokenizes % alone as ERROR" do
      tokens = tokenize("val = % ")
      err = find_token(tokens, TokenType::ERROR)
      expect(err).not_to be_nil
    end

    it "verb arguments are flat token list" do
      tokens = tokenize('val = %concat "a" "b"')
      verb = find_token(tokens, TokenType::VERB)
      strs = find_tokens(tokens, TokenType::STRING)
      expect(verb.value).to eq("concat")
      expect(strs.length).to eq(2)
    end

    it "nested verbs produce flat list" do
      tokens = tokenize("val = %concat %upper @name \" suffix\"")
      verbs = find_tokens(tokens, TokenType::VERB)
      expect(verbs.length).to eq(2)
      expect(verbs[0].value).to eq("concat")
      expect(verbs[1].value).to eq("upper")
    end

    it "verb with reference arg" do
      tokens = tokenize("val = %trim @field")
      verb = find_token(tokens, TokenType::VERB)
      ref = find_token(tokens, TokenType::REFERENCE)
      expect(verb.value).to eq("trim")
      expect(ref.value).to eq("field")
    end

    it "verb with number arg" do
      tokens = tokenize("val = %add #5")
      verb = find_token(tokens, TokenType::VERB)
      num = find_token(tokens, TokenType::NUMBER)
      expect(verb.value).to eq("add")
      expect(num.value).to eq("5")
    end
  end

  # ─── Date/Time/Duration Tokens ────────────────────────────────────

  describe "date/time/duration tokens" do
    it "tokenizes 2024-01-15 as DATE" do
      tokens = tokenize("val = 2024-01-15")
      date = find_token(tokens, TokenType::DATE)
      expect(date.value).to eq("2024-01-15")
    end

    it "tokenizes 2024-01-15T10:30:00Z as TIMESTAMP" do
      tokens = tokenize("val = 2024-01-15T10:30:00Z")
      ts = find_token(tokens, TokenType::TIMESTAMP)
      expect(ts.value).to eq("2024-01-15T10:30:00Z")
    end

    it "tokenizes timestamp with timezone offset" do
      tokens = tokenize("val = 2024-01-15T10:30:00+05:00")
      ts = find_token(tokens, TokenType::TIMESTAMP)
      expect(ts.value).to eq("2024-01-15T10:30:00+05:00")
    end

    it "tokenizes T10:30:00 as TIME" do
      tokens = tokenize("val = T10:30:00")
      time = find_token(tokens, TokenType::TIME)
      expect(time.value).to eq("T10:30:00")
    end

    it "tokenizes P1Y2M3D as DURATION" do
      tokens = tokenize("val = P1Y2M3D")
      dur = find_token(tokens, TokenType::DURATION)
      expect(dur.value).to eq("P1Y2M3D")
    end

    it "tokenizes PT1H30M as DURATION" do
      tokens = tokenize("val = PT1H30M")
      dur = find_token(tokens, TokenType::DURATION)
      expect(dur.value).to eq("PT1H30M")
    end

    it "tokenizes P1DT12H as DURATION" do
      tokens = tokenize("val = P1DT12H")
      dur = find_token(tokens, TokenType::DURATION)
      expect(dur.value).to eq("P1DT12H")
    end

    it "tokenizes timestamp with milliseconds" do
      tokens = tokenize("val = 2024-01-15T10:30:00.123Z")
      ts = find_token(tokens, TokenType::TIMESTAMP)
      expect(ts.value).to eq("2024-01-15T10:30:00.123Z")
    end

    it "tokenizes time with seconds fraction" do
      tokens = tokenize("val = T10:30:00.500")
      time = find_token(tokens, TokenType::TIME)
      expect(time.value).to eq("T10:30:00.500")
    end

    it "tokenizes duration with weeks P2W" do
      tokens = tokenize("val = P2W")
      dur = find_token(tokens, TokenType::DURATION)
      expect(dur.value).to eq("P2W")
    end

    it "tokenizes duration with fractional seconds PT1.5S" do
      tokens = tokenize("val = PT1.5S")
      dur = find_token(tokens, TokenType::DURATION)
      expect(dur.value).to eq("PT1.5S")
    end

    it "tokenizes time with just hours and minutes T14:30" do
      tokens = tokenize("val = T14:30")
      time = find_token(tokens, TokenType::TIME)
      expect(time.value).to eq("T14:30")
    end

    it "tokenizes timestamp with negative timezone offset" do
      tokens = tokenize("val = 2024-06-15T08:00:00-04:00")
      ts = find_token(tokens, TokenType::TIMESTAMP)
      expect(ts.value).to eq("2024-06-15T08:00:00-04:00")
    end

    it "distinguishes date from number" do
      tokens = tokenize("val = 2024-01-15")
      expect(find_token(tokens, TokenType::DATE)).not_to be_nil
      expect(find_token(tokens, TokenType::NUMBER)).to be_nil
    end

    it "tokenizes date at end of line" do
      tokens = tokenize("val = 2024-12-31\n")
      date = find_token(tokens, TokenType::DATE)
      expect(date.value).to eq("2024-12-31")
    end
  end

  # ─── Modifier Tokens ─────────────────────────────────────────────

  describe "modifier tokens" do
    it "tokenizes ! before value as MODIFIER" do
      tokens = tokenize('name = !"required"')
      mod = find_token(tokens, TokenType::MODIFIER)
      expect(mod.value).to eq("!")
    end

    it "tokenizes * before value as MODIFIER" do
      tokens = tokenize('ssn = *"hidden"')
      mod = find_token(tokens, TokenType::MODIFIER)
      expect(mod.value).to eq("*")
    end

    it "tokenizes - before value as MODIFIER" do
      tokens = tokenize('old = -"deprecated"')
      mod = find_token(tokens, TokenType::MODIFIER)
      expect(mod.value).to eq("-")
    end

    it "tokenizes combined !-* as three MODIFIERs" do
      tokens = tokenize('val = !-*"secret"')
      mods = find_tokens(tokens, TokenType::MODIFIER)
      expect(mods.length).to eq(3)
      expect(mods.map(&:value)).to eq(["!", "-", "*"])
    end

    it "modifier followed by number" do
      tokens = tokenize("val = !##42")
      mod = find_token(tokens, TokenType::MODIFIER)
      int = find_token(tokens, TokenType::INTEGER)
      expect(mod.value).to eq("!")
      expect(int.value).to eq("42")
    end

    it "modifier followed by boolean" do
      tokens = tokenize("val = !true")
      mod = find_token(tokens, TokenType::MODIFIER)
      bool = find_token(tokens, TokenType::BOOLEAN)
      expect(mod.value).to eq("!")
      expect(bool.value).to eq("true")
    end
  end

  # ─── Directive Tokens ─────────────────────────────────────────────

  describe "directive tokens" do
    it "tokenizes :required as DIRECTIVE" do
      tokens = tokenize('name = "John" :required')
      dir = find_token(tokens, TokenType::DIRECTIVE)
      expect(dir.value).to eq("required")
    end

    it "tokenizes :confidential as DIRECTIVE" do
      tokens = tokenize('ssn = "123" :confidential')
      dir = find_token(tokens, TokenType::DIRECTIVE)
      expect(dir.value).to eq("confidential")
    end

    it "tokenizes :deprecated as DIRECTIVE" do
      tokens = tokenize('old = "x" :deprecated')
      dir = find_token(tokens, TokenType::DIRECTIVE)
      expect(dir.value).to eq("deprecated")
    end

    it 'tokenizes :type with value' do
      tokens = tokenize('name = "John" :type "string"')
      dir = find_token(tokens, TokenType::DIRECTIVE)
      expect(dir.value).to eq("type")
      strs = find_tokens(tokens, TokenType::STRING)
      expect(strs.length).to eq(2)
    end

    it "directive after null value" do
      tokens = tokenize("val = ~ :deprecated")
      null = find_token(tokens, TokenType::NULL)
      dir = find_token(tokens, TokenType::DIRECTIVE)
      expect(null).not_to be_nil
      expect(dir.value).to eq("deprecated")
    end
  end

  # ─── Comment Tokens ──────────────────────────────────────────────

  describe "comment tokens" do
    it "tokenizes ; comment as COMMENT" do
      tokens = tokenize("; this is a comment")
      comment = find_token(tokens, TokenType::COMMENT)
      expect(comment.value).to eq("this is a comment")
    end

    it "tokenizes comment after value" do
      tokens = tokenize('name = "John" ; the name')
      comment = find_token(tokens, TokenType::COMMENT)
      expect(comment.value).to eq("the name")
    end

    it "tokenizes comment-only line" do
      tokens = tokenize("; just a comment\nname = \"x\"")
      comment = find_token(tokens, TokenType::COMMENT)
      expect(comment.value).to eq("just a comment")
    end

    it "preserves comment text" do
      tokens = tokenize("; spaces  and   tabs\t here")
      comment = find_token(tokens, TokenType::COMMENT)
      expect(comment.value).to include("spaces")
    end

    it "empty comment" do
      tokens = tokenize(";")
      comment = find_token(tokens, TokenType::COMMENT)
      expect(comment.value).to eq("")
    end
  end

  # ─── Path Tokens ─────────────────────────────────────────────────

  describe "path tokens" do
    it "tokenizes simple name as PATH" do
      tokens = tokenize("name = \"x\"")
      path = find_token(tokens, TokenType::PATH)
      expect(path.value).to eq("name")
    end

    it "tokenizes dotted path person.name" do
      tokens = tokenize("person.name = \"x\"")
      path = find_token(tokens, TokenType::PATH)
      expect(path.value).to eq("person.name")
    end

    it "tokenizes array index path items[0]" do
      tokens = tokenize("items[0] = \"x\"")
      path = find_token(tokens, TokenType::PATH)
      expect(path.value).to eq("items[0]")
    end

    it "tokenizes combined path items[0].name" do
      tokens = tokenize("items[0].name = \"x\"")
      path = find_token(tokens, TokenType::PATH)
      expect(path.value).to eq("items[0].name")
    end

    it "tokenizes path with underscore" do
      tokens = tokenize("first_name = \"x\"")
      path = find_token(tokens, TokenType::PATH)
      expect(path.value).to eq("first_name")
    end

    it "tokenizes path with hyphen" do
      tokens = tokenize("my-field = \"x\"")
      path = find_token(tokens, TokenType::PATH)
      expect(path.value).to eq("my-field")
    end

    it "tokenizes path starting with underscore" do
      tokens = tokenize("_private = \"x\"")
      path = find_token(tokens, TokenType::PATH)
      expect(path.value).to eq("_private")
    end

    it "tokenizes deeply nested path" do
      tokens = tokenize("a.b.c.d = \"x\"")
      path = find_token(tokens, TokenType::PATH)
      expect(path.value).to eq("a.b.c.d")
    end

    it "tokenizes path with multiple array indices" do
      tokens = tokenize("items[0].sub[1] = \"x\"")
      path = find_token(tokens, TokenType::PATH)
      expect(path.value).to eq("items[0].sub[1]")
    end

    it "tokenizes relative path .field" do
      tokens = tokenize(".field = \"x\"")
      path = find_token(tokens, TokenType::PATH)
      expect(path.value).to eq(".field")
    end
  end

  # ─── Full Line Scanning ──────────────────────────────────────────

  describe "full line scanning" do
    it 'scans name = "John"' do
      tokens = tokenize('name = "John"')
      types = tokens.map(&:type).reject { |t| t == TokenType::EOF }
      expect(types).to eq([TokenType::PATH, TokenType::EQUALS, TokenType::STRING])
      expect(find_token(tokens, TokenType::STRING).value).to eq("John")
    end

    it "scans age = ##42" do
      tokens = tokenize("age = ##42")
      types = tokens.map(&:type).reject { |t| t == TokenType::EOF }
      expect(types).to eq([TokenType::PATH, TokenType::EQUALS, TokenType::INTEGER])
      expect(find_token(tokens, TokenType::INTEGER).value).to eq("42")
    end

    it "scans price = #\$99.99:USD" do
      tokens = tokenize('price = #$99.99:USD')
      types = tokens.map(&:type).reject { |t| t == TokenType::EOF }
      expect(types).to eq([TokenType::PATH, TokenType::EQUALS, TokenType::CURRENCY])
    end

    it "scans active = ?true" do
      tokens = tokenize("active = ?true")
      types = tokens.map(&:type).reject { |t| t == TokenType::EOF }
      expect(types).to eq([TokenType::PATH, TokenType::EQUALS, TokenType::BOOLEAN])
    end

    it "scans data = ~" do
      tokens = tokenize("data = ~")
      types = tokens.map(&:type).reject { |t| t == TokenType::EOF }
      expect(types).to eq([TokenType::PATH, TokenType::EQUALS, TokenType::NULL])
    end

    it "scans ref = @other.path" do
      tokens = tokenize("ref = @other.path")
      types = tokens.map(&:type).reject { |t| t == TokenType::EOF }
      expect(types).to eq([TokenType::PATH, TokenType::EQUALS, TokenType::REFERENCE])
    end

    it "scans _ = @ (bare ref valid)" do
      tokens = tokenize("_ = @")
      ref = find_token(tokens, TokenType::REFERENCE)
      expect(ref).not_to be_nil
      expect(ref.value).to eq("")
    end

    it 'scans line with comment: name = "John" ; the name' do
      tokens = tokenize('name = "John" ; the name')
      types = tokens.map(&:type).reject { |t| t == TokenType::EOF }
      expect(types).to eq([TokenType::PATH, TokenType::EQUALS, TokenType::STRING, TokenType::COMMENT])
    end

    it 'scans line with modifier: name = !"required"' do
      tokens = tokenize('name = !"required"')
      types = tokens.map(&:type).reject { |t| t == TokenType::EOF }
      expect(types).to eq([TokenType::PATH, TokenType::EQUALS, TokenType::MODIFIER, TokenType::STRING])
    end

    it 'scans line with directive: name = "John" :required' do
      tokens = tokenize('name = "John" :required')
      types = tokens.map(&:type).reject { |t| t == TokenType::EOF }
      expect(types).to eq([TokenType::PATH, TokenType::EQUALS, TokenType::STRING, TokenType::DIRECTIVE])
    end

    it "scans multi-line document" do
      text = "name = \"John\"\nage = ##30"
      tokens = tokenize(text)
      paths = find_tokens(tokens, TokenType::PATH)
      expect(paths.length).to eq(2)
      expect(paths[0].value).to eq("name")
      expect(paths[1].value).to eq("age")
    end

    it "scans document with header and assignments" do
      text = "{Customer}\nname = \"John\"\nage = ##30"
      tokens = tokenize(text)
      expect(find_token(tokens, TokenType::HEADER_OPEN)).not_to be_nil
      paths = find_tokens(tokens, TokenType::PATH)
      expect(paths.length).to be >= 2
    end

    it "scans line with modifier and directive" do
      tokens = tokenize('name = !"John" :required')
      mod = find_token(tokens, TokenType::MODIFIER)
      str = find_token(tokens, TokenType::STRING)
      dir = find_token(tokens, TokenType::DIRECTIVE)
      expect(mod.value).to eq("!")
      expect(str.value).to eq("John")
      expect(dir.value).to eq("required")
    end

    it "scans bare boolean on value side" do
      tokens = tokenize("active = true")
      bool = find_token(tokens, TokenType::BOOLEAN)
      expect(bool.value).to eq("true")
    end

    it "scans line with all parts: modifier + value + directive + comment" do
      tokens = tokenize('name = !"John" :required ; important')
      types = tokens.map(&:type).reject { |t| t == TokenType::EOF }
      expect(types).to eq([
        TokenType::PATH, TokenType::EQUALS,
        TokenType::MODIFIER, TokenType::STRING,
        TokenType::DIRECTIVE, TokenType::COMMENT
      ])
    end
  end

  # ─── Error Cases ─────────────────────────────────────────────────

  describe "error cases" do
    it "unterminated string produces ERROR" do
      tokens = tokenize('name = "unclosed')
      expect(find_token(tokens, TokenType::ERROR)).not_to be_nil
    end

    it "invalid escape produces ERROR" do
      tokens = tokenize('name = "\\q"')
      expect(find_token(tokens, TokenType::ERROR)).not_to be_nil
    end

    it "@# produces ERROR" do
      tokens = tokenize("val = @#")
      expect(find_token(tokens, TokenType::ERROR)).not_to be_nil
    end

    it "document exceeding MAX_DOCUMENT_SIZE raises ParseError" do
      huge = "x" * (Odin::Utils::SecurityLimits::MAX_DOCUMENT_SIZE + 1)
      expect { tokenize(huge) }.to raise_error(Odin::Errors::ParseError) do |e|
        expect(e.code).to eq(Odin::Errors::ParseErrorCode::MAXIMUM_DOCUMENT_SIZE_EXCEEDED)
      end
    end

    it "% alone produces ERROR" do
      tokens = tokenize("val = % ")
      expect(find_token(tokens, TokenType::ERROR)).not_to be_nil
    end

    it "?invalid produces ERROR" do
      tokens = tokenize("val = ?maybe")
      expect(find_token(tokens, TokenType::ERROR)).not_to be_nil
    end

    it "unterminated header produces ERROR" do
      tokens = tokenize("{unclosed\n")
      expect(find_token(tokens, TokenType::ERROR)).not_to be_nil
    end

    it "unterminated multi-line string produces ERROR" do
      tokens = tokenize("val = \"\"\"\nnever closed")
      expect(find_token(tokens, TokenType::ERROR)).not_to be_nil
    end

    it "invalid unicode escape produces ERROR" do
      tokens = tokenize('val = "\\uGGGG"')
      expect(find_token(tokens, TokenType::ERROR)).not_to be_nil
    end

    it "error token has error? == true" do
      tokens = tokenize('val = "unclosed')
      err = find_token(tokens, TokenType::ERROR)
      expect(err.error?).to be true
    end
  end

  # ─── Line/Column Tracking ────────────────────────────────────────

  describe "line/column tracking" do
    it "first token at line 1, col 1" do
      tokens = tokenize("name = \"x\"")
      first = tokens.first
      expect(first.line).to eq(1)
      expect(first.column).to eq(1)
    end

    it "second line tokens at line 2" do
      tokens = tokenize("a = \"x\"\nb = \"y\"")
      paths = find_tokens(tokens, TokenType::PATH)
      expect(paths[1].line).to eq(2)
    end

    it "column advances through line" do
      tokens = tokenize("name = \"x\"")
      eq = find_token(tokens, TokenType::EQUALS)
      expect(eq.column).to eq(6)
    end

    it "tracks line after multiple newlines" do
      tokens = tokenize("a = \"x\"\n\n\nb = \"y\"")
      paths = find_tokens(tokens, TokenType::PATH)
      expect(paths[1].line).to eq(4)
    end

    it "EOF has correct line" do
      tokens = tokenize("line1\nline2\n")
      eof = tokens.last
      expect(eof.type).to eq(TokenType::EOF)
      expect(eof.line).to be >= 2
    end

    it "header tokens have correct positions" do
      tokens = tokenize("{Customer}")
      open = find_token(tokens, TokenType::HEADER_OPEN)
      expect(open.line).to eq(1)
      expect(open.column).to eq(1)
    end

    it "CRLF advances line correctly" do
      tokens = tokenize("a = \"x\"\r\nb = \"y\"")
      paths = find_tokens(tokens, TokenType::PATH)
      expect(paths[1].line).to eq(2)
    end

    it "token after BOM has correct column" do
      tokens = tokenize("\xEF\xBB\xBFname = \"x\"")
      path = find_token(tokens, TokenType::PATH)
      expect(path.column).to eq(1)
    end
  end

  # ─── Token Object ────────────────────────────────────────────────

  describe "Token class" do
    it "is frozen after creation" do
      token = Odin::Parsing::Token.new(TokenType::STRING, "hello", 1, 1)
      expect(token).to be_frozen
    end

    it "has to_s representation" do
      token = Odin::Parsing::Token.new(TokenType::STRING, "hello", 1, 5)
      expect(token.to_s).to include("string")
      expect(token.to_s).to include("hello")
    end

    it "non-error token has error? == false" do
      token = Odin::Parsing::Token.new(TokenType::STRING, "hello", 1, 1)
      expect(token.error?).to be false
    end

    it "supports raw attribute" do
      token = Odin::Parsing::Token.new(TokenType::STRING, "hello", 1, 1, raw: '"hello"')
      expect(token.raw).to eq('"hello"')
    end
  end

  # ─── Complex Documents ───────────────────────────────────────────

  describe "complex documents" do
    it "tokenizes a complete ODIN document" do
      text = <<~'ODIN'
        {$}
        odin = "1.0.0"

        {Customer}
        name = "John Doe"
        age = ##30
        email = !"john@example.com" :required
        balance = #$1000.00:USD
        active = ?true
        notes = ~
      ODIN
      tokens = tokenize(text)
      expect(find_token(tokens, TokenType::ERROR)).to be_nil
      expect(find_tokens(tokens, TokenType::HEADER_OPEN).length).to eq(2)
      expect(find_tokens(tokens, TokenType::PATH).length).to be >= 7
    end

    it "tokenizes transform-like document" do
      text = <<~'ODIN'
        {$}
        odin = "1.0.0"
        transform = "1.0.0"
        direction = "json->odin"

        {Customer}
        Name = %upper @.name
        Total = %add @.price @.tax
      ODIN
      tokens = tokenize(text)
      expect(find_token(tokens, TokenType::ERROR)).to be_nil
      verbs = find_tokens(tokens, TokenType::VERB)
      expect(verbs.length).to eq(2)
    end

    it "tokenizes tabular data" do
      text = "| name | age |\n| \"John\" | ##30 |"
      tokens = tokenize(text)
      pipes = find_tokens(tokens, TokenType::PIPE)
      expect(pipes.length).to be >= 4
    end

    it "tokenizes document with all value types" do
      text = <<~'ODIN'
        str = "hello"
        num = #3.14
        int = ##42
        cur = #$99.99:USD
        pct = #%50
        bool = ?true
        null = ~
        ref = @other
        bin = ^SGVsbG8=
        date = 2024-01-15
        time = T10:30:00
        dur = P1Y2M3D
      ODIN
      tokens = tokenize(text)
      expect(find_token(tokens, TokenType::ERROR)).to be_nil
      expect(find_token(tokens, TokenType::STRING)).not_to be_nil
      expect(find_token(tokens, TokenType::NUMBER)).not_to be_nil
      expect(find_token(tokens, TokenType::INTEGER)).not_to be_nil
      expect(find_token(tokens, TokenType::CURRENCY)).not_to be_nil
      expect(find_token(tokens, TokenType::PERCENT)).not_to be_nil
      expect(find_token(tokens, TokenType::BOOLEAN)).not_to be_nil
      expect(find_token(tokens, TokenType::NULL)).not_to be_nil
      expect(find_token(tokens, TokenType::REFERENCE)).not_to be_nil
      expect(find_token(tokens, TokenType::BINARY)).not_to be_nil
      expect(find_token(tokens, TokenType::DATE)).not_to be_nil
      expect(find_token(tokens, TokenType::TIME)).not_to be_nil
      expect(find_token(tokens, TokenType::DURATION)).not_to be_nil
    end

    it "handles multiple headers with assignments" do
      text = <<~'ODIN'
        {Customer}
        name = "Alice"

        {Order}
        total = #$50.00

        {}
        global = "yes"
      ODIN
      tokens = tokenize(text)
      headers = find_tokens(tokens, TokenType::HEADER_OPEN)
      expect(headers.length).to eq(3)
    end
  end

  # ─── Edge Cases ──────────────────────────────────────────────────

  describe "edge cases" do
    it "handles whitespace-only lines" do
      tokens = tokenize("  \t  \n  \t  ")
      # Should just have newline and EOF, no errors
      expect(find_token(tokens, TokenType::ERROR)).to be_nil
    end

    it "handles value immediately after equals with no space" do
      tokens = tokenize('name="John"')
      # With no space, 'name' is path, then we need = to be detected
      # The scanner should handle this
      eq = find_token(tokens, TokenType::EQUALS)
      expect(eq).not_to be_nil
    end

    it "handles multiple assignments on separate lines" do
      text = "a = \"1\"\nb = \"2\"\nc = \"3\""
      tokens = tokenize(text)
      paths = find_tokens(tokens, TokenType::PATH)
      expect(paths.length).to eq(3)
    end

    it "handles empty lines between assignments" do
      text = "a = \"1\"\n\nb = \"2\""
      tokens = tokenize(text)
      paths = find_tokens(tokens, TokenType::PATH)
      expect(paths.length).to eq(2)
    end

    it "handles comment-only document" do
      tokens = tokenize("; just comments\n; more comments")
      comments = find_tokens(tokens, TokenType::COMMENT)
      expect(comments.length).to eq(2)
      expect(find_token(tokens, TokenType::ERROR)).to be_nil
    end

    it "handles header with spaces" do
      tokens = tokenize("{ Customer }")
      path = find_token(tokens, TokenType::PATH)
      expect(path.value).to eq("Customer")
    end

    it "handles consecutive headers" do
      text = "{A}\n{B}\n{C}"
      tokens = tokenize(text)
      headers = find_tokens(tokens, TokenType::HEADER_OPEN)
      expect(headers.length).to eq(3)
    end

    it "verb with null argument" do
      tokens = tokenize("val = %coalesce @field ~")
      verb = find_token(tokens, TokenType::VERB)
      null = find_token(tokens, TokenType::NULL)
      expect(verb).not_to be_nil
      expect(null).not_to be_nil
    end

    it "verb with boolean argument" do
      tokens = tokenize("val = %if true @field")
      verb = find_token(tokens, TokenType::VERB)
      bool = find_token(tokens, TokenType::BOOLEAN)
      expect(verb).not_to be_nil
      expect(bool).not_to be_nil
    end

    it "currency with GBP code" do
      tokens = tokenize('val = #$100.00:GBP')
      cur = find_token(tokens, TokenType::CURRENCY)
      expect(cur.value).to eq("100.00:GBP")
    end

    it "multiple modifiers with space between" do
      tokens = tokenize('val = ! - * "secret"')
      mods = find_tokens(tokens, TokenType::MODIFIER)
      expect(mods.length).to eq(3)
    end
  end
end
