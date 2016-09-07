require 'json'
require 'ios_parser/ios'

module IOSParser
  def self.parse(input)
    IOSParser::IOS.new.call(input)
  end

  def self.hash_to_ios(hash)
    IOSParser::IOS::Document.from_hash(hash)
  end

  def self.json_to_ios(text)
    hash_to_ios JSON.load(text)
  end
end
