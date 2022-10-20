require_relative '../../spec_helper'
require 'ios_parser'
require 'ios_parser/lexer'

module IOSParser
  describe PureLexer do
    describe '#call' do
      it 'accepts non-whitespace printable characters as words' do
        input = "before emdash – after emdash"
        tokens = PureLexer.new.call(input)
        expect(tokens.map(&:value)).to eq %w[before emdash – after emdash]
        expect(tokens.map(&:col)).to eq [1, 8, 15, 17, 23]
      end
    end
  end
end
