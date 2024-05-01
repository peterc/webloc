# webloc

*webloc* is a Ruby library that can read from and write to <tt>.webloc</tt> files as used on macOS. These are a variant of 'plist' format files, specifically used for storing links to URLs.

It works on Ruby 2.7 and up, including Ruby 3.x, and supports URLs of up to 2048 characters in length (and probably longer, but this is around the de facto limit for URLs in most systems).

## Installation

    gem install webloc
    
## Usage

Reading a .webloc file:

    Webloc.load(ARGV.first).url

Writing to a .webloc file:

    Webloc.new('https://rubyweekly.com/').save('rubyweekly.webloc')

## Thanks

Thanks is due to Christos Karaiskos for [this article](https://medium.com/@karaiskc/understanding-apples-binary-property-list-format-281e6da00dbd
) which helped me understand the plist format a bit more when fixing a bug in 2024.

## License

Copyright (C) 2011-2024 Peter Cooper

webloc is licensed under the terms of the MIT License