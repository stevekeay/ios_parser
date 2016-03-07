module IOSParser
  class PureLexer
    attr_accessor :tokens, :token, :indents, :indent, :state, :char,
                  :string_terminator

    def initialize
      @text    = ''
      @token   = ''
      @tokens  = []
      @indent  = 0
      @indents = [0]
      @state   = :root
      @token_char = 0
      @this_char  = -1
    end

    def call(input_text)
      initialize

      input_text.each_char.with_index do |c, i|
        @this_char = i
        self.char = c
        send(state)
      end

      delimit
      update_indentation
      scrub_banner_garbage
      tokens
    end

    ROOT_TRANSITIONS = [
      :space,
      :banner_begin,
      :certificate_begin,
      :newline,
      :comment,
      :integer,
      :quoted_string,
      :word
    ].freeze

    def root
      @token_start ||= @this_char

      ROOT_TRANSITIONS.each do |meth|
        return send(meth) if send(:"#{meth}?")
      end

      raise LexError, "Unknown character #{char.inspect}"
    end

    def root_line_start
      if lead_comment?
        comment
      else
        root
      end
    end

    def make_token(value, pos: nil)
      pos ||= @token_start || @this_char
      @token_start = nil
      [pos, value]
    end

    def comment
      self.state = :comment
      update_indentation
      self.state = :root if newline?
    end

    def comment?
      char == '!'
    end

    def lead_comment?
      char == '#' || char == '!'
    end

    def banner_begin
      self.state = :banner
      tokens << make_token(:BANNER_BEGIN)
      @token_start = @this_char + 2
      @banner_delimiter = char
    end

    def banner_begin?
      tokens[-2] && tokens[-2].last == 'banner'
    end

    def banner
      char == @banner_delimiter ? banner_end : token << char
    end

    def banner_end
      self.state = :root
      banner_end_clean_token
      tokens << make_token(token) << make_token(:BANNER_END)
      self.token = ''
    end

    def banner_end_clean_token
      token.slice!(0) if token[0] == 'C'
      token.slice!(0) if ["\n", ' '].include?(token[0])
    end

    def scrub_banner_garbage
      tokens.each_index do |i|
        next unless tokens[i + 1]
        tokens.slice!(i + 1) if banner_garbage?(i)
      end
    end

    def banner_garbage?(i)
      tokens[i].last == :BANNER_END && tokens[i + 1].last == 'C'
    end

    def certificate_begin?
      tokens[-6] && tokens[-6].last == :INDENT &&
        tokens[-5] && tokens[-5].last == 'certificate'
    end

    def certificate_begin
      self.state = :certificate
      indents.pop
      tokens[-2..-1] = [make_token(:CERTIFICATE_BEGIN, pos: tokens[-1][0])]
      certificate
    end

    def certificate
      token[-5..-1] == "quit\n" ? certificate_end : token << char
    end

    def certificate_end
      tokens.concat certificate_end_tokens
      update_indentation
      @token_start = @this_char

      @token = ''
      self.state = :line_start
      self.indent = 0
      root
    end

    def certificate_end_tokens
      [
        make_token(token[0..-6].gsub!(/\s+/, ' ').strip, pos: tokens[-1][0]),
        make_token(:CERTIFICATE_END, pos: @this_char),
        make_token(:EOL, pos: @this_char)
      ]
    end

    def integer
      self.state = :integer
      case
      when dot?   then decimal
      when digit? then token << char
      when word?  then word
      else root
      end
    end

    def integer_token
      token[0] == '0' ? word_token : make_token(Integer(token))
    end

    def digit?
      ('0'..'9').cover? char
    end
    alias integer? digit?

    def dot?
      char == '.'
    end

    def decimal
      self.state = :decimal
      case
      when digit? then token << char
      when dot?   then token << char
      when word?  then word
      else root
      end
    end

    def decimal_token
      if token.count('.') > 1 || token[-1] == '.'
        word_token
      else
        make_token(Float(token))
      end
    end

    def decimal?
      dot? || digit?
    end

    def word
      self.state = :word
      word? ? token << char : root
    end

    def word_token
      make_token(token)
    end

    def word?
      digit? || dot? ||
        ('a'..'z').cover?(char) ||
        ('A'..'Z').cover?(char) ||
        ['-', '+', '$', ':', '/', ',', '(', ')', '|', '*', '#', '=', '<', '>',
         '!', '"', '&', '@', ';', '%', '~', '{', '}', "'", '?', '[', ']', '_',
         '^', '\\', '`'].include?(char)
    end

    def space
      delimit
      self.indent += 1 if tokens.last && tokens.last.last == :EOL
    end

    def space?
      char == ' ' || char == "\t" || char == "\r"
    end

    def quoted_string
      self.state = :quoted_string
      token << char
      if string_terminator.nil?
        self.string_terminator = char
      elsif char == string_terminator
        delimit
      end
    end

    def quoted_string_token
      make_token(token)
    end

    def quoted_string?
      char == '"' || char == "'"
    end

    def newline
      delimit
      self.state = :line_start
      self.indent = 0
      tokens << make_token(:EOL)
    end

    def newline?
      char == "\n"
    end

    def line_start
      if space?
        self.indent += 1
      else
        update_indentation
        root_line_start
      end
    end

    def delimit
      return if token.empty?
      tokens << send(:"#{state}_token")
      self.state = :root
      self.token = ''
    end

    def update_indentation
      pop_dedent while 1 < indents.size && indent <= indents[-2]
      push_indent if indent > indents.last
      self.indent = 0
    end

    def pop_dedent
      tokens << make_token(:DEDENT)
      indents.pop
    end

    def push_indent
      tokens << make_token(:INDENT)
      indents.push(indent)
    end

    class LexError < StandardError; end
  end # class PureLexer
end # module IOSParser
