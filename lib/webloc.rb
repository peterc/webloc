require 'plist'

class Webloc
  class WeblocError < StandardError; end
  class FileNotFoundError < WeblocError; end
  class CorruptedFileError < WeblocError; end
  class InvalidFormatError < WeblocError; end
  class EmptyFileError < WeblocError; end

  attr_accessor :url

  def initialize(url)
    raise ArgumentError, "URL cannot be nil or empty" if url.nil? || url.empty?
    @url = url
  end

  def self.load(filename)
    raise FileNotFoundError, "File not found: #{filename}" unless File.exist?(filename)
    
    begin
      data = File.read(filename)
    rescue => e
      raise FileNotFoundError, "Unable to read file '#{filename}': #{e.message}"
    end
    
    raise EmptyFileError, "File is empty: #{filename}" if data.empty?
    
    data = data.force_encoding('binary') rescue data
    url = nil
    
    if data !~ /\<plist/
      # Handle binary plist format
      url = parse_binary_format(data, filename)
    else
      # Handle XML plist format
      url = parse_xml_format(filename)
    end
    
    raise CorruptedFileError, "No URL found in webloc file: #{filename}" if url.nil? || url.empty?
    new(url)
  end

  private

  def self.parse_binary_format(data, filename)
    offset = (data =~ /SURL_/)
    raise InvalidFormatError, "Invalid binary webloc format - missing SURL marker in file: #{filename}" unless offset
    
    begin
      length_offset = 7
      if data[offset + 5] == "\x10"
        length = data[offset + 6]
        length = length.unpack('C')[0]  
      elsif data[offset + 5] == "\x11"
        length_offset = 8
        length = data[offset + 6] + data[offset + 7]
        length = length.unpack('S>')[0]  
      else
        raise InvalidFormatError, "Unsupported length encoding in binary webloc file: #{filename}"
      end
      
      raise CorruptedFileError, "Invalid URL length (#{length}) in file: #{filename}" if length <= 0 || length > data.length
      
      url = data[offset + length_offset, length]
      raise CorruptedFileError, "Extracted URL is empty from file: #{filename}" if url.nil? || url.empty?
      
      url
    rescue CorruptedFileError, InvalidFormatError => e
      raise e
    rescue => e
      raise CorruptedFileError, "Failed to parse binary webloc format in file '#{filename}': #{e.message}"
    end
  end

  def self.parse_xml_format(filename)
    begin
      plist_data = Plist::parse_xml(filename)
      raise InvalidFormatError, "Invalid XML plist format - could not parse file: #{filename}" unless plist_data.is_a?(Hash)
      
      url = plist_data['URL']
      raise CorruptedFileError, "No 'URL' key found in plist file: #{filename}" unless url
      
      url
    rescue => e
      if e.message.include?('parse') || e.message.include?('XML') || e.message.include?('plist')
        raise InvalidFormatError, "Invalid XML plist format in file '#{filename}': #{e.message}"
      else
        raise CorruptedFileError, "Failed to parse XML webloc format in file '#{filename}': #{e.message}"
      end
    end
  end

  public

  def data
    # PLIST HEADER
    @data = "bplist\x30\x30".bytes

    # PLIST OBJECT TABLE
    @data += "\xD1\x01\x02".bytes   # object 1 is a dictionary
    @data += "SURL".bytes           # object 2

    length_suffix = @url.length > 255 ? "\x11" : "\x10"
    @data += ("\x5f" + length_suffix).bytes       # object 3 is an ASCII string with a variable length length encoding (I know..)
                              #   .. the '0' in \x10 denotes the length can be encoded within 2**0 bytes (i.e. 1)
                              #   .. the '1' in \x11 denotes the length can be encoded within 2**1 bytes (i.e. 2)
    
    if @url.length > 255
      @data += [@url.length].pack('S>').bytes
    else
      @data += [@url.length].pack('C').bytes
    end
    @data += @url.bytes             # and finally the URL itself

    # This is the offset table
    @data += "\x08\x0B\x0F".bytes   # so objects at 0x08, 0x0b and 0x0f

    # PLIST TRAILER
    # Bytes 0-4 are unused
    @data += "\x00\x00\x00\x00\x00".bytes
    # Byte 5 is the sort version
    @data += "\x00".bytes
    # Byte 6 is how many bytes are needed for each offset table offset
    @data += "\x01".bytes
    @data += "\x01".bytes
    # Bytes 8-15 are how many objects are contained in the plist
    @data += "\x00\x00\x00\x00\x00\x00\x00\x03".bytes
    # Bytes 16-23 are for an offset from the offset table
    @data += "\x00\x00\x00\x00\x00\x00\x00\x00".bytes
    # Bytes 24-31 denote the position of the offset table from the start of the file
    @data += "\x00\x00\x00\x00\x00\x00".bytes + [@url.length + 18].pack('S>').bytes

    @data = @data.pack('C*')
  end
  
  def save(filename)
    raise ArgumentError, "Filename cannot be nil or empty" if filename.nil? || filename.empty?
    
    begin
      File.open(filename, 'wb') { |f| f.write data }
    rescue => e
      raise WeblocError, "Failed to save webloc file '#{filename}': #{e.message}"
    end
  end
end