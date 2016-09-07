require_relative 'ios/document'

module IOSParser
  class IOS
    attr_accessor :lexer, :tokens, :source, :document

    def initialize(parent: nil, lexer: IOSParser::Lexer.new)
      @document = Document.new(nil)
      @parent = parent
      @lexer  = lexer
    end

    def tokens
      @tokens ||= lexer.call(@source)
    end

    def call(source)
      unless source.respond_to? :each_char
        raise ArgumentError, 'Provided configuration source is invalid.'
      end
      @source = source
      @document.source = source
      @document.push(*section) until tokens.empty?
      @document
    end

    def section(parent = nil)
      [].tap do |commands|
        until tokens.empty? || tokens.first.type == :DEDENT
          commands.push(command(parent, @document))
        end
        tokens.shift # discard :DEDENT
      end
    end

    def command(parent = nil, document = nil)
      pos = tokens.first.pos
      opts = { args: arguments, parent: parent, document: document, pos: pos }

      Command.new(opts).tap do |cmd|
        cmd.commands = subsections(cmd)
      end
    end

    def arguments_to_discard
      [:INDENT, :DEDENT,
       :CERTIFICATE_BEGIN, :CERTIFICATE_END,
       :BANNER_BEGIN, :BANNER_END]
    end

    def arguments
      args = []
      while (token = tokens.shift) && token.type != :EOL
        next if arguments_to_discard.include?(token.type)
        args << token.value
      end
      args
    end

    def subsections(parent = nil)
      if !tokens.empty? && tokens.first.type == :INDENT
        tokens.shift # discard :INDENT
        section(parent)
      else
        []
      end
    end
  end
end
