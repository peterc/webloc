# webloc

*webloc* is a Ruby library that can read from and write to <tt>.webloc</tt> files as used on macOS.

It works on Ruby 1.8.7 and up, including Ruby 3.x. It appears to still work on macOS Monterey too, so I have made a quick tidy up and release for 2022!

## Installation

    gem install webloc
    
## Usage

Reading a .webloc file:

    Webloc.load(ARGV.first).url

Writing to a .webloc file:

    Webloc.new('https://rubyweekly.com/').save('rubyweekly.webloc')

## License

Copyright (C) 2011-2022 Peter Cooper

webloc is licensed under the terms of the MIT License