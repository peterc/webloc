require_relative 'webloc/binary_plist'
require_relative 'webloc/xml_plist'

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
      data = File.binread(filename)
    rescue => e
      raise FileNotFoundError, "Unable to read file '#{filename}': #{e.message}"
    end
    
    raise EmptyFileError, "File is empty: #{filename}" if data.empty?
    
    url = nil
    
    if data.start_with?('bplist00') || !data.include?('<plist')
      # Handle binary plist format
      url = parse_binary_format(data, filename)
    else
      # Handle XML plist format
      url = parse_xml_format(data, filename)
    end
    
    raise CorruptedFileError, "No URL found in webloc file: #{filename}" if url.nil? || (url.is_a?(String) && url.empty?)
    raise CorruptedFileError, "URL must be a string in webloc file: #{filename}" unless url.is_a?(String)
    new(url)
  end

  private

  def self.parse_binary_format(data, filename)
    BinaryPlist.new(data.b, filename).url
  end

  def self.parse_xml_format(data, filename)
    XMLPlist.new(data, filename).url
  end

  public

  def data
    BinaryPlist.dump(@url)
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
