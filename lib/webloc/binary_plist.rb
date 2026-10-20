class Webloc
  # Read the root dictionary's URL without recursively decoding unrelated metadata.
  class BinaryPlist
    HEADER = 'bplist00'.b.freeze
    PREFIX = "bplist00\xD1\x01\x02SURL".b.freeze
    INTEGER_FORMATS = { 1 => 'C', 2 => 'n', 4 => 'N', 8 => 'Q>' }.freeze

    def self.integer_width(value)
      INTEGER_FORMATS.each_key.find { |width| value < (1 << (8 * width)) } ||
        raise(ArgumentError, 'URL is too long to encode')
    end

    def self.dump(url)
      if url.ascii_only?
        payload = url.b
        length = payload.bytesize
        marker = 0x5f
      else
        payload = url.encode(Encoding::UTF_16BE).b
        length = payload.bytesize / 2 # UTF-16 code units, including surrogate pairs.
        marker = 0x6f
      end

      # Keep the historical object order and extended string length encoding,
      # so existing valid ASCII output (including the original fixture) is stable.
      width = integer_width(length)
      output = PREFIX + [marker, 0x10 + width.bit_length - 1].pack('CC')
      output << [length].pack(INTEGER_FORMATS.fetch(width)) << payload
      table_offset = output.bytesize
      offset_width = integer_width(table_offset)
      output << [8, 11, 15].pack("#{INTEGER_FORMATS.fetch(offset_width)}*")
      output << [offset_width, 1, 3, 0, table_offset].pack('x6CCQ>Q>Q>')
    end

    def initialize(data, filename)
      @data = data
      @filename = filename
    end

    def url
      unless @data.start_with?(HEADER)
        detail = @data.include?('SURL_') ? 'missing bplist00 header' : 'missing SURL marker'
        raise InvalidFormatError, "Invalid binary webloc format - #{detail} in file: #{@filename}"
      end

      # Recognize the complete historical layout, never just a URL marker.
      historical_url = legacy_url
      return historical_url if historical_url

      read_table
      type, count, cursor, limit = object(@root)
      corrupt('Root object is not a dictionary') unless type == 0xd
      read(cursor, count * 2 * @reference_width, limit)

      count.times do |index|
        key_ref = integer(cursor + index * @reference_width, @reference_width, limit)
        next unless string(key_ref) == 'URL'

        value_ref = integer(cursor + (count + index) * @reference_width, @reference_width, limit)
        return string(value_ref)
      end
      corrupt("No 'URL' key found")
    end

    private

    def corrupt(message)
      raise CorruptedFileError, "#{message} in binary webloc file: #{@filename}"
    end

    def read(offset, length, limit)
      corrupt('Truncated or invalid object') if offset < 8 || length < 0 || offset > limit || length > limit - offset
      @data.byteslice(offset, length)
    end

    def integer(offset, width, limit)
      read(offset, width, limit).each_byte.reduce(0) { |value, byte| (value << 8) | byte }
    end

    def read_table
      corrupt('Truncated plist trailer') if @data.bytesize < 40
      offset_width, @reference_width, count, @root, table_offset =
        @data.byteslice(-32, 32).unpack('x6CCQ>Q>Q>')
      unless (1..8).cover?(offset_width) && (1..8).cover?(@reference_width)
        corrupt('Invalid offset or reference width')
      end
      trailer_offset = @data.bytesize - 32
      unless count > 0 && @root < count && table_offset >= 8 &&
             table_offset + count * offset_width == trailer_offset
        corrupt('Invalid offset table')
      end

      @offsets = Array.new(count) do |index|
        offset = integer(table_offset + index * offset_width, offset_width, trailer_offset)
        corrupt('Object offset is outside the object table') unless offset >= 8 && offset < table_offset
        offset
      end
      # Objects need not be stored in reference order. Bound each read by the
      # following physical object, so a truncated URL cannot consume the table.
      boundaries = @offsets.uniq.sort + [table_offset]
      @limits = boundaries.each_cons(2).to_h
    end

    def object(reference)
      corrupt('Invalid object reference') unless reference < @offsets.length
      offset = @offsets.fetch(reference)
      limit = @limits.fetch(offset)
      marker = integer(offset, 1, limit)
      cursor = offset + 1
      length = marker & 0xf
      if length == 0xf
        size_marker = integer(cursor, 1, limit)
        unless (0x10..0x13).cover?(size_marker)
          raise InvalidFormatError, "Unsupported length encoding in binary webloc file: #{@filename}"
        end
        width = 1 << (size_marker & 0xf)
        length = integer(cursor + 1, width, limit)
        cursor += width + 1
      end
      [marker >> 4, length, cursor, limit]
    end

    def string(reference)
      type, length, cursor, limit = object(reference)
      case type
      when 0x5
        value = read(cursor, length, limit)
        corrupt('Invalid ASCII string') unless value.ascii_only?
        value
      when 0x6
        read(cursor, length * 2, limit).force_encoding(Encoding::UTF_16BE).encode(Encoding::UTF_8)
      else
        corrupt('Expected a string')
      end
    rescue EncodingError
      corrupt('Invalid Unicode string')
    end

    def legacy_url
      return unless @data.start_with?(PREFIX + "\x5f".b)
      width = { 0x10 => 1, 0x11 => 2 }[@data.getbyte(16)]
      return unless width && @data.bytesize >= 18 + width + 35

      length = @data.byteslice(17, width).unpack1(INTEGER_FORMATS.fetch(width))
      return unless length >= 238 && width == (length > 255 ? 2 : 1)
      table_offset = 17 + width + length
      return unless @data.bytesize == table_offset + 35

      # Match even the two-byte overflow in the old trailer, but require every
      # other byte of its structure and the full declared URL to be present.
      trailer = [1, 1, 3, 0, (length + 18) & 0xffff].pack('x6CCQ>Q>Q>')
      return unless @data.byteslice(table_offset, 35) == "\x08\x0b\x0f".b + trailer
      value = @data.byteslice(17 + width, length)
      value if value.ascii_only?
    end
  end

  private_constant :BinaryPlist
end
