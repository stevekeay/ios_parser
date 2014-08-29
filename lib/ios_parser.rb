module IOSParser
  Lexer = if const_defined?(:PureLexer)
            PureLexer
          else
            require_relative 'ios_parser/c_lexer'
            CLexer
          end
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
      hash_to_ios MultiJson.load(text)
    end
  end
end
