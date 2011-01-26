# webloc

*webloc* is a Ruby library that can read from and write to <tt>.webloc</tt> files as used on OS X.

It works on both Ruby 1.9.2 and 1.8.7 (though development is focused on 1.9.2).

## Installation

    gem install webloc
    
## Usage

It's pretty simple.

Reading a .webloc file:

    Webloc.load(ARGV.first).url

Writing to a .webloc file:

    Webloc.new('http://peterc.org/').save('peterc.webloc')

## License

Copyright (C) 2011 Peter Cooper

webloc is licensed under the terms of the MIT License