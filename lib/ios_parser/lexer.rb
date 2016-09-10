require 'delegate'
require 'strscan'

module IOSParser
  class PureLexer
    LexError = IOSParser::LexError

    class Token
      attr_reader :type, :value, :pos

      def initialize(type, value, pos)
        @type = type
        @value = value || type
        @pos = pos
      end
    end

    extend Forwardable
    def_delegators :scanner,
                   :check, :eos?, :matched, :pos, :rest, :scan, :scan_until,
                   :skip, :unscan

    attr_accessor :text, :scanner, :token_start, :indents, :tokens

    def call(text)
      @text        = text
      @scanner     = StringScanner.new(text)
      @token_start = 0
      @indents     = [0]
      @tokens      = []

      start_of_line until eos?
      (indents.size - 1).times { add_token(pos, :DEDENT) }
      tokens
    end

    private

    TOKEN_TYPE = {
      Bignum  => :INTEGER,
      Fixnum  => :INTEGER,
      Integer => :INTEGER,
      Float   => :DECIMAL,
      String  => :STRING
    }.freeze

    def add_token(position, value)
      type = TOKEN_TYPE.fetch(value.class, value)
      tokens << Token.new(type, value, position)
    end

    def certificate
      return false unless certificate?

      certificate_begin_pos = pos
      skip(/\s+/)
      token_start = pos
      content = scan_until(/quit\n/) || return

      certificate_begin(certificate_begin_pos)
      certificate_end(certificate_begin_pos, token_start, content)
    end

    def certificate?
      tokens[-6] &&
        tokens[-6].type == :INDENT &&
        tokens[-5].value == 'certificate'
    end

    def certificate_begin(certificate_begin_pos)
      tokens.pop(2)
      indents.pop
      add_token(certificate_begin_pos, :CERTIFICATE_BEGIN)
    end

    def certificate_end(certificate_begin_pos, token_start, content)
      content = content[0..-6].rstrip
      certificate_end_pos = certificate_begin_pos + content.size - 1
      content = content.lstrip.gsub(/\s+/, ' ')
      add_token(token_start, content)
      add_token(certificate_end_pos, :CERTIFICATE_END)
      scanner.pos = pos - 1
    end

    def end_of_line
      return true if eos?
      return false unless scan(/![^\n]*(?:\n|$)|\n/o)
      add_token(pos - 1, :EOL) if matched[-1] == "\n"
      true
    end

    def banner
      return false unless banner?
      skip(/[\v\t ]+/)
      add_token(pos, :BANNER_BEGIN)
      banner_content
      add_token(pos - 1, :BANNER_END)
    end

    def banner?
      tokens[-2] && tokens[-2].value == 'banner'
    end

    def banner_content
      delimiter_word = scan(/\S+$/) || return
      delimiter = Regexp.escape(delimiter_word[0])
      skip(/\n/)
      token_start = pos
      content = scan_until(/^#{delimiter}|#{delimiter}$/)
      add_token(token_start, content[0..-2])
      skip(/C+/) # yay inexplicable garbage characters!
    end

    def middle_of_line
      loop do
        (end_of_line && return) || spaces || visible_token ||
          (raise LexError, 'Unknown characters at #{pos}: #{text[pos, 20]}')
      end
    end

    def spaces
      skip(/[\v\t ]+/o)
    end

    def quoted_string
      token_start = pos
      delimiter = scan(/['"]/o)
      return false unless delimiter
      content = scan_until(Regexp.new(delimiter)) ||
                (raise LexError, 'Unterminated quoted string starting at '\
                                 "#{token_start}: #{text[token_start, 20]}")
      add_token(token_start, delimiter + content)
    end

    def start_of_line
      return if scan(/[\t ]*[!#][^\n]*\n/o)
      update_indentation(scan(/[\t ]*/o))
      middle_of_line
    end

    def visible_token
      banner || certificate || quoted_string || word
    end

    def update_indentation(leading_spaces)
      return unless leading_spaces

      size = leading_spaces.size
      case size <=> indents.last
      when -1
        update_indentation_dedent(size)
      when +1
        update_indentation_indent(size)
      end
    end

    def update_indentation_dedent(size)
      while 1 < indents.size && size <= indents[-2]
        add_token(pos, :DEDENT)
        indents.pop
      end
    end

    def update_indentation_indent(size)
      add_token(pos, :INDENT)
      indents << size
    end

    def word
      token_start = pos
      converted = word_convert(scan(/\S+/o)) || return
      add_token(token_start, converted)
    end

    def word_convert(content)
      case content
      when nil, ''
        nil
      when /^[1-9]\d*$/o
        Integer(content)
      when /^\d*\.+d*$|^[1-9]\d*\.\d*$/o
        Float(content)
      else
        content
      end
    end
  end # PureLexer
end # module IOSParser
