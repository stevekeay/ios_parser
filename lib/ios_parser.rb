require 'json'

module IOSParser
  class LexError < StandardError; end

  def self.lexer
    if const_defined?(:PureLexer)
      PureLexer
    else
      require_relative 'ios_parser/c_lexer'
      CLexer
    end
  rescue LoadError
    require 'ios_parser/lexer'
    return PureLexer
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
      hash_to_ios JSON.load(text)
    end
  end
end
