# frozen_string_literal: true

require "set"

module Odin
  module Validation
    module FormatValidators
      # Email: RFC 5322 simplified
      EMAIL_RE = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

      # URI: scheme://...
      URI_RE = /\A[a-zA-Z][a-zA-Z0-9+\-.]*:/

      # URL: http(s)://...
      URL_RE = %r{\Ahttps?://[^\s/$.?#].[^\s]*\z}

      # UUID: 8-4-4-4-12 hex
      UUID_RE = /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/

      # Date: YYYY-MM-DD
      DATE_RE = /\A\d{4}-\d{2}-\d{2}\z/

      # Time: HH:MM:SS or HH:MM
      TIME_RE = /\A[T]?\d{2}:\d{2}(:\d{2})?\z/

      # DateTime: ISO 8601
      DATETIME_RE = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/

      # Duration: ISO 8601 P...
      DURATION_RE = /\AP(\d+Y)?(\d+M)?(\d+W)?(\d+D)?(T(\d+H)?(\d+M)?(\d+(\.\d+)?S)?)?\z/

      # Hostname: RFC 952/1123
      HOSTNAME_RE = /\A[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?)*\z/

      # Phone: international format
      PHONE_RE = /\A\+?[\d\s\-().]{7,20}\z/

      # Credit card: 13-19 digits (spaces/dashes allowed)
      CREDIT_CARD_RE = /\A[\d\s\-]{13,25}\z/

      # SSN: 123-45-6789 or 123456789
      SSN_RE = /\A\d{3}-?\d{2}-?\d{4}\z/

      # NAIC: 5-digit insurance code
      NAIC_RE = /\A\d{5}\z/

      # EIN/FEIN: 12-3456789
      EIN_RE = /\A\d{2}-\d{7}\z/
      FEIN_RE = EIN_RE

      # ZIP: 12345 or 12345-6789
      ZIP_RE = /\A\d{5}(-\d{4})?\z/

      # VIN: 17 chars, no I/O/Q
      VIN_RE = /\A[A-HJ-NPR-Z0-9]{17}\z/

      # IBAN: 2 letters + 2 digits + up to 30 alphanumeric
      IBAN_RE = /\A[A-Z]{2}\d{2}[A-Z0-9]{4,30}\z/

      # BIC/SWIFT: 8 or 11 chars
      BIC_RE = /\A[A-Z]{4}[A-Z]{2}[A-Z0-9]{2}([A-Z0-9]{3})?\z/

      # Routing number: 9 digits
      ROUTING_RE = /\A\d{9}\z/

      # CUSIP: 9 chars alphanumeric
      CUSIP_RE = /\A[A-Z0-9]{9}\z/

      # ISIN: 2 letters + 9 chars + 1 check digit
      ISIN_RE = /\A[A-Z]{2}[A-Z0-9]{9}\d\z/

      # LEI: 20 chars alphanumeric
      LEI_RE = /\A[A-Z0-9]{18}\d{2}\z/

      # NPI: 10 digits
      NPI_RE = /\A\d{10}\z/

      # DEA: 2 chars + 7 digits
      DEA_RE = /\A[A-Z]{2}\d{7}\z/

      # IMEI: 15 digits
      IMEI_RE = /\A\d{15}\z/

      # ICCID: 19-20 digits
      ICCID_RE = /\A\d{19,20}\z/

      # Hex: hex string
      HEX_RE = /\A[0-9a-fA-F]+\z/

      # ISO 4217 currency codes
      CURRENCY_CODES = %w[
        AED AFN ALL AMD ANG AOA ARS AUD AWG AZN
        BAM BBD BDT BGN BHD BIF BMD BND BOB BRL
        BSD BTN BWP BYN BZD CAD CDF CHF CLP CNY
        COP CRC CUP CVE CZK DJF DKK DOP DZD EGP
        ERN ETB EUR FJD FKP GBP GEL GHS GIP GMD
        GNF GTQ GYD HKD HNL HRK HTG HUF IDR ILS
        INR IQD IRR ISK JMD JOD JPY KES KGS KHR
        KMF KPW KRW KWD KYD KZT LAK LBP LKR LRD
        LSL LYD MAD MDL MGA MKD MMK MNT MOP MRU
        MUR MVR MWK MXN MYR MZN NAD NGN NIO NOK
        NPR NZD OMR PAB PEN PGK PHP PKR PLN PYG
        QAR RON RSD RUB RWF SAR SBD SCR SDG SEK
        SGD SHP SLE SOS SRD SSP STN SVC SYP SZL
        THB TJS TMT TND TOP TRY TTD TWD TZS UAH
        UGX USD UYU UZS VES VND VUV WST XAF XCD
        XOF XPF YER ZAR ZMW ZWL
      ].to_set.freeze

      # US state/territory codes
      US_STATES = %w[
        AK AL AR AS AZ CA CO CT DC DE
        FL GA GU HI IA ID IL IN KS KY
        LA MA MD ME MI MN MO MP MS MT
        NC ND NE NH NJ NM NV NY OH OK
        OR PA PR RI SC SD TN TX UT VA
        VI VT WA WI WV WY
      ].to_set.freeze

      VALIDATORS = {
        "email"         => ->(v) { EMAIL_RE.match?(v) },
        "uri"           => ->(v) { URI_RE.match?(v) },
        "url"           => ->(v) { URL_RE.match?(v) },
        "uuid"          => ->(v) { UUID_RE.match?(v) },
        "date"          => ->(v) { DATE_RE.match?(v) },
        "time"          => ->(v) { TIME_RE.match?(v) },
        "datetime"      => ->(v) { DATETIME_RE.match?(v) },
        "date-time"     => ->(v) { DATETIME_RE.match?(v) },
        "date-iso"      => ->(_v) { true },
        "duration"      => ->(v) { DURATION_RE.match?(v) },
        "hostname"      => ->(v) { HOSTNAME_RE.match?(v) && v.length <= 253 },
        "ipv4"          => ->(v) { validate_ipv4(v) },
        "ipv6"          => ->(v) { validate_ipv6(v) },
        "phone"         => ->(v) { PHONE_RE.match?(v) },
        "credit-card"   => ->(v) { validate_creditcard(v) },
        "creditcard"    => ->(v) { validate_creditcard(v) },
        "ssn"           => ->(v) { validate_ssn(v) },
        "ein"           => ->(v) { EIN_RE.match?(v) },
        "fein"          => ->(v) { EIN_RE.match?(v) },
        "zip"           => ->(v) { ZIP_RE.match?(v) },
        "vin"           => ->(v) { VIN_RE.match?(v.upcase) },
        "iban"          => ->(v) { IBAN_RE.match?(v.gsub(/\s/, "").upcase) },
        "bic"           => ->(v) { BIC_RE.match?(v.upcase) },
        "swift"         => ->(v) { BIC_RE.match?(v.upcase) },
        "routing"       => ->(v) { ROUTING_RE.match?(v) },
        "cusip"         => ->(v) { CUSIP_RE.match?(v.upcase) },
        "isin"          => ->(v) { ISIN_RE.match?(v.upcase) },
        "lei"           => ->(v) { LEI_RE.match?(v.upcase) },
        "npi"           => ->(v) { NPI_RE.match?(v) },
        "naic"          => ->(v) { NAIC_RE.match?(v) },
        "dea"           => ->(v) { DEA_RE.match?(v.upcase) },
        "imei"          => ->(v) { IMEI_RE.match?(v) },
        "iccid"         => ->(v) { ICCID_RE.match?(v) },
        "hex"           => ->(v) { HEX_RE.match?(v) },
        "currency-code" => ->(v) { v.length == 3 && v.match?(/\A[A-Z]{3}\z/) && CURRENCY_CODES.include?(v) },
        "state-us"      => ->(v) { v.length == 2 && v.match?(/\A[A-Z]{2}\z/) && US_STATES.include?(v) },
      }.freeze

      def self.validate(format_name, value)
        validator = VALIDATORS[format_name]
        return true unless validator # unknown format is permissive
        return false unless value.is_a?(String)
        validator.call(value)
      end

      def self.known?(format_name)
        VALIDATORS.key?(format_name)
      end

      def self.validate_ipv4(value)
        parts = value.split(".")
        return false unless parts.length == 4
        parts.all? do |p|
          p.match?(/\A\d{1,3}\z/) && p.to_i.between?(0, 255) && (p == "0" || !p.start_with?("0"))
        end
      end

      def self.validate_ipv6(value)
        # Handle :: shorthand
        return false if value.empty?
        return false unless value.match?(/\A[\da-fA-F:]+\z/)
        return false unless value.include?(":")

        # Split on :: (preserve empty trailing parts)
        has_double_colon = value.include?("::")
        return false if value.scan("::").length > 1

        if has_double_colon
          parts = value.split("::", -1)
          return false if parts.length > 2
          left = parts[0].empty? ? [] : parts[0].split(":")
          right = parts[1].empty? ? [] : parts[1].split(":")
          return false if left.length + right.length > 7
          (left + right).all? { |g| g.match?(/\A[\da-fA-F]{1,4}\z/) }
        else
          return false unless value.include?(":") && !has_double_colon
          groups = value.split(":")
          return false unless groups.length == 8
          groups.all? { |g| g.match?(/\A[\da-fA-F]{1,4}\z/) }
        end
      end

      def self.luhn_check?(digits)
        return false unless digits.match?(/\A\d+\z/)
        sum = 0
        digits.reverse.each_char.with_index do |ch, i|
          n = ch.to_i
          if i.odd?
            n *= 2
            n -= 9 if n > 9
          end
          sum += n
        end
        (sum % 10).zero?
      end

      def self.validate_ssn(value)
        digits = value.gsub("-", "")
        return false unless digits.length == 9 && digits.match?(/\A\d{9}\z/)
        # Must be either 9 digits or XXX-XX-XXXX format
        return false unless value.length == 9 || (value.length == 11 && value[3] == "-" && value[6] == "-")
        # Area code (first 3 digits) cannot be 000
        return false if digits[0..2] == "000"
        true
      end

      def self.validate_creditcard(value)
        return false unless CREDIT_CARD_RE.match?(value)
        digits = value.gsub(/[\s\-]/, "")
        return false if digits.length < 13 || digits.length > 19
        luhn_check?(digits)
      end

      private_class_method :validate_ipv4, :validate_ipv6, :luhn_check?,
                           :validate_ssn, :validate_creditcard
    end
  end
end
