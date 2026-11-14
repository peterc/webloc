require 'strscan'

class Webloc
  # Read the root dictionary's URL in one pass, without building the document.
  class XMLPlist
    BOM = "\xEF\xBB\xBF".b.freeze
    NAME = '[A-Za-z_][A-Za-z0-9_.-]*+'.freeze
    OPEN_TAG = %r{<(#{NAME})(?:\s++[^<>]*?)?(/)?>}
    CLOSE_TAG = %r{</(#{NAME})\s*+>}
    DOCTYPE = /<!DOCTYPE\s[^<>\[]*+>/
    ELEMENTS = %w[plist dict key string integer real true false date data array].freeze
    DECLARATION = /\A<\?xml[^?>]*+/n
    ENCODING_ATTRIBUTE = /\Gencoding(\s*+=\s*+)(["'])([^"']*+)\2/n
    ENCODINGS = {
      'utf-8' => Encoding::UTF_8, 'utf8' => Encoding::UTF_8,
      'us-ascii' => Encoding::US_ASCII, 'ascii' => Encoding::US_ASCII,
      'iso-8859-1' => Encoding::ISO_8859_1, 'iso_8859-1' => Encoding::ISO_8859_1, 'latin1' => Encoding::ISO_8859_1,
      'windows-1252' => Encoding::Windows_1252, 'cp1252' => Encoding::Windows_1252,
    }.freeze
    REFERENCE = /&(?:#(x[0-9a-fA-F]++|[0-9]++)|(amp|lt|gt|quot|apos));/
    ENTITIES = { 'amp' => '&', 'lt' => '<', 'gt' => '>', 'quot' => '"', 'apos' => "'" }.freeze

    def initialize(data, filename)
      @data = data
      @filename = filename
    end

    def url
      @scanner = StringScanner.new(text)
      open = []
      root_seen = dict_seen = found = false
      key = url = nil

      until @scanner.eos?
        next if skip_misc(open.empty? && !root_seen)
        next if open.length > 2 && (@scanner.skip(/[^<]++/) || cdata)

        if @scanner.scan(CLOSE_TAG)
          invalid("Unexpected </#{@scanner[1]}>") unless open.pop == @scanner[1]
          invalid('Missing value for key') if open.length == 1 && key
          break if open.empty?

          next
        end
        invalid('Unexpected content') unless @scanner.scan(OPEN_TAG)

        name = @scanner[1]
        empty = !@scanner[2].nil?
        case open.length
        when 0
          invalid('Root element is not a single <plist>') unless name == 'plist' && !root_seen
          root_seen = true
        when 1
          invalid('Root object is not a single dictionary') unless name == 'dict' && !dict_seen
          dict_seen = true
        when 2
          if key.nil?
            invalid('Expected a <key>') unless name == 'key' && !empty
            key = text_until_close(name)
            next
          elsif key == 'URL'
            unless name == 'string'
              raise CorruptedFileError, "URL must be a string in webloc file: #{@filename}"
            end
            url = empty ? '' : text_until_close(name)
            found = true
            key = nil
            next
          end
          key = nil
        end
        invalid("Unknown element <#{name}>") unless ELEMENTS.include?(name)
        open << name unless empty
      end

      invalid('Unexpected end of document') unless open.empty? && dict_seen
      raise InvalidFormatError, "No 'URL' key found in plist file: #{@filename}" unless found
      url
    end

    private

    def invalid(detail)
      raise InvalidFormatError, "Invalid XML plist format in file '#{@filename}': #{detail}"
    end

    def text
      encoding = declared_encoding
      text = @data.start_with?(BOM) ? @data.byteslice(BOM.bytesize..) : @data.dup
      text.force_encoding(encoding)
      invalid("Document is not valid #{encoding}") unless text.valid_encoding?
      text.encode(Encoding::UTF_8)
    rescue EncodingError
      invalid("Document cannot be converted from #{encoding}")
    end

    # Apple reads an encoding only from a declaration at the first byte, and
    # converts the whole document from it before parsing.
    def declared_encoding
      declaration = @data[DECLARATION]
      first = declaration&.index(/encoding/i)
      return Encoding::UTF_8 unless first

      match = ENCODING_ATTRIBUTE.match(declaration, first)
      encoding = match && ENCODINGS[match[3].downcase]
      return encoding if encoding && (match[1] == '=' || encoding == Encoding::UTF_8)

      invalid('Unsupported encoding declaration')
    end

    def skip_misc(prolog)
      if @scanner.skip(/\s++/)
        true
      elsif @scanner.skip(/<!--/)
        @scanner.skip_until(/-->/) || invalid('Unterminated comment')
      elsif @scanner.skip(/<\?/)
        @scanner.skip_until(/\?>/) || invalid('Unterminated processing instruction')
      elsif prolog
        @scanner.skip(DOCTYPE)
      end
    end

    def text_until_close(name)
      value = +''
      loop do
        value << decode(@scanner.scan(/[^<]*+/))
        section = cdata
        break unless section

        value << section
      end
      invalid("Expected only text in <#{name}>") unless @scanner.scan(CLOSE_TAG) && @scanner[1] == name
      value
    end

    def cdata
      return unless @scanner.skip(/<!\[CDATA\[/)

      section = @scanner.scan_until(/\]\]>/) || invalid('Unterminated CDATA section')
      section.delete_suffix(']]>')
    end

    def decode(raw)
      return raw unless raw.include?('&')

      raw.gsub(REFERENCE) { $2 ? ENTITIES.fetch($2) : character($1) }
    end

    def character(reference)
      base = reference.start_with?('x') ? 16 : 10
      digits = reference.delete_prefix('x').sub(/\A0++/, '')
      code = digits.length > 8 ? -1 : digits.to_i(base)
      unless (0..0xd7ff).cover?(code) || (0xe000..0x10ffff).cover?(code)
        invalid("Invalid character reference &##{reference};")
      end
      [code].pack('U')
    end
  end

  private_constant :XMLPlist
end
