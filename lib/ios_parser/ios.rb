require_relative 'ios/document'

module IOSParser
  class IOS
    attr_accessor :document
    attr_accessor :lexer
    attr_accessor :source
    attr_writer :tokens

    def initialize(parent: nil, lexer: IOSParser::Lexer.new)
      @document = Document.new(nil)
      @parent = parent
      @lexer  = lexer
      @indent = 0
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
        until tokens.empty? || tokens.first.value == :DEDENT
          commands.push(command(parent, @document))
        end
        token = tokens.shift # discard :DEDENT
        @indent -= 1 if token && token.value == :DEDENT
      end
    end

    def command(parent = nil, document = nil)
      opts = {
        tokens: command_tokens,
        parent: parent,
        document: document,
        indent: @indent
      }

      Command.new(**opts).tap do |cmd|
        cmd.commands = subsections(cmd)
      end
    end

    def command_tokens
      toks = []
      until tokens.empty? || tokens.first.value == :EOL
        tok = tokens.shift
        toks << tok unless argument_to_discard?(tok.value)
      end
      tokens.shift # discard :EOL
      toks
    end

    def argument_to_discard?(arg)
      arguments_to_discard.include?(arg)
    end

    def arguments_to_discard
      [:INDENT, :DEDENT,
       :CERTIFICATE_BEGIN, :CERTIFICATE_END,
       :BANNER_BEGIN, :BANNER_END]
    end

    def subsections(parent = nil)
      if !tokens.empty? && tokens.first.value == :INDENT
        @indent += 1
        tokens.shift # discard :INDENT
        section(parent)
      else
        []
      end
    end
  end
end
