require 'plist'
require_relative 'webloc/binary_plist'

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
      url = parse_xml_format(filename)
    end
    
    raise CorruptedFileError, "No URL found in webloc file: #{filename}" if url.nil? || (url.is_a?(String) && url.empty?)
    raise CorruptedFileError, "URL must be a string in webloc file: #{filename}" unless url.is_a?(String)
    new(url)
  end

  private

  def self.parse_binary_format(data, filename)
    BinaryPlist.new(data.b, filename).url
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
