require 'json'
require 'ios_parser/token'

module IOSParser
  class LexError < StandardError; end

  def self.lexer
    if const_defined?(:PureLexer)
      PureLexer
    else
      c_lexer
    end
  rescue LoadError
    pure_lexer
  end

  def self.c_lexer
    if RUBY_VERSION < '2.1'
      warn 'The C Lexer requires Ruby 2.1 or later. The pure Ruby lexer will '\
           'be used instead. You can eliminate this warning by upgrading ruby '\
           'or explicitly using the pure-Ruby lexer '\
           "(require 'ios_parser/pure')"
      pure_lexer
    else
      require_relative 'ios_parser/c_lexer'
      CLexer
    end
  end

  def self.pure_lexer
    require 'ios_parser/lexer'
    PureLexer
  end

  Lexer = lexer
end

require_relative 'ios_parser/ios'

module IOSParser
  class << self
    def parse(input)
      IOSParser::IOS.new.call(input)
    end

    def hash_to_ios(hash)
      IOSParser::IOS::Document.from_hash(hash)
    end

    def json_to_ios(text)
      hash_to_ios JSON.parse(text)
    end
  end
end
