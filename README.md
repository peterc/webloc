# webloc

*webloc* is a Ruby library that can read from and write to <tt>.webloc</tt> files as used on macOS. These are a variant of 'plist' format files, specifically used for storing links to URLs.

It works on Ruby 2.7 and up, including Ruby 3.x, and supports URLs of up to 2048 characters in length (and probably longer, but this is around the de facto limit for URLs in most systems).

## Installation

    gem install webloc
    
## Usage

### Basic Usage

Reading a .webloc file:

    webloc = Webloc.load('bookmark.webloc')
    puts webloc.url
    # => "https://example.com"

Writing to a .webloc file:

    Webloc.new('https://rubyweekly.com/').save('rubyweekly.webloc')

### Advanced Examples

#### Processing multiple .webloc files

```ruby
require 'webloc'

Dir.glob('*.webloc').each do |file|
  webloc = Webloc.load(file)
  puts "#{file}: #{webloc.url}"
end
```

#### Creating webloc files from a list of URLs

```ruby
require 'webloc'

urls = [
  'https://github.com',
  'https://stackoverflow.com',
  'https://ruby-lang.org'
]

urls.each_with_index do |url, index|
  filename = "bookmark_#{index + 1}.webloc"
  Webloc.new(url).save(filename)
  puts "Created #{filename}"
end
```

#### Error handling

```ruby
require 'webloc'

begin
  webloc = Webloc.load('suspicious.webloc')
  puts webloc.url
rescue Webloc::FileNotFoundError => e
  puts "File not found: #{e.message}"
rescue Webloc::CorruptedFileError => e
  puts "File is corrupted: #{e.message}"
rescue Webloc::InvalidFormatError => e
  puts "Invalid file format: #{e.message}"
rescue Webloc::WeblocError => e
  puts "General webloc error: #{e.message}"
end
```

#### Validating URLs before creating webloc files

```ruby
require 'webloc'
require 'uri'

def create_webloc_safely(url, filename)
  # Basic URL validation
  uri = URI.parse(url)
  unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    puts "Invalid URL scheme: #{url}"
    return false
  end
  
  # Create the webloc file
  Webloc.new(url).save(filename)
  puts "Created #{filename} for #{url}"
  true
rescue URI::InvalidURIError
  puts "Invalid URL format: #{url}"
  false
rescue Webloc::WeblocError => e
  puts "Failed to create webloc: #{e.message}"
  false
end

create_webloc_safely('https://example.com', 'example.webloc')
create_webloc_safely('invalid-url', 'invalid.webloc')
```

#### Converting between formats

```ruby
require 'webloc'
require 'json'

# Convert webloc to JSON
webloc = Webloc.load('bookmark.webloc')
json_data = { url: webloc.url, title: File.basename('bookmark.webloc', '.webloc') }
File.write('bookmark.json', JSON.pretty_generate(json_data))

# Convert JSON back to webloc
json_content = JSON.parse(File.read('bookmark.json'))
Webloc.new(json_content['url']).save('restored.webloc')
```

## Thanks

Thanks is due to Christos Karaiskos for [this article](https://medium.com/@karaiskc/understanding-apples-binary-property-list-format-281e6da00dbd
) which helped me understand the plist format a bit more when fixing a bug in 2024.

## License

Copyright (C) 2011-2025 Peter Cooper

webloc is licensed under the terms of the MIT License