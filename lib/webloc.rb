require 'plist'

class Webloc
  attr_accessor :url

  def initialize(url)
    @url = url
  end

  def self.load(filename)
    data = File.read(filename)
    data = data.force_encoding('binary') rescue data
    
    if data !~ /\<plist/
      offset = (data =~ /SURL_/)
      length_offset = 7
      if data[offset + 5] == "\x10"
        length = data[offset + 6]
        length = length.unpack('C')[0]  
      elsif data[offset + 5] == "\x11"
        length_offset = 8
        length = data[offset + 6] + data[offset + 7]
        length = length.unpack('S>')[0]  
      end
      url = data[offset + length_offset,length]
    else
      url = Plist::parse_xml(filename)['URL'] rescue nil
    end
    
    raise ArgumentError unless url
    new(url)
  end

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
    File.open(filename, 'wb') { |f| f.write data }
  end
end