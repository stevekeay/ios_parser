module IOSParser
  class PureLexer
    attr_accessor :tokens, :token, :indents, :indent, :state, :char

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

    def root
      @token_start ||= @this_char

      case
      when space?             then space
      when banner_begin?      then transition(:banner_begin)
      when certificate_begin? then certificate_begin
      when newline?           then newline
      when comment?           then transition(:comment)
      when digit?             then transition(:integer)
      when word?              then transition(:word)
      else fail LexError, "Unknown character #{char.inspect}"
      end
    end

    def transition(new_state)
      self.state = new_state
      send new_state
    end

    def make_token(value, pos: nil)
      pos ||= @token_start || @this_char
      @token_start = nil
      [pos, value]
    end

    def comment
      self.state = :root if newline?
    end

    def comment?
      char == '#' || char == '!'
    end

    def banner_begin
      self.state = :banner
      tokens << make_token(:BANNER_BEGIN)
      @token_start = @this_char + 2
      @banner_delimiter = char
    end

    def banner_begin?
      tokens[-2] &&
        tokens[-2].last.is_a?(String) &&
        tokens[-2].last == 'banner'
    end

    def banner
      char == @banner_delimiter ? banner_end : token << char
    end

    def banner_end
      self.state = :root
      token.slice!(0) if token[0] == 'C'
      token.slice!(0) if (token[0] == "\n" || token[0] == ' ')
      token.slice!(-1) if token[1] == "\n"
      tokens << make_token(token) << make_token(:BANNER_END)
      self.token = ''
    end

    def scrub_banner_garbage
      tokens.each_index do |i|
        next unless tokens[i+1]
        if tokens[i].last == :BANNER_END && tokens[i+1].last == 'C'
          tokens.slice!(i+1)
        end
      end
    end

    def certificate_begin?
      tokens[-6] &&
        tokens[-6].last.is_a?(Symbol) &&
        tokens[-6].last == :INDENT &&
        tokens[-5] &&
        tokens[-5].last.is_a?(String) &&
        tokens[-5].last == 'certificate'
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
      case
      when dot?   then transition(:decimal)
      when digit? then token << char
      when word?  then transition(:word)
      else root
      end
    end

    def integer_token
      token[0] == '0' ? word_token : make_token(Integer(token))
    end

    def digit?
      ('0'..'9').cover? char
    end
    alias_method :integer?, :digit?

    def dot?
      char == '.'
    end

    def decimal
      case
      when digit? then token << char
      when dot?   then token << char
      when word?  then transition(:word)
      else root
      end
    end

    def decimal_token
      (token.count('.') > 1 || token[-1] == '.') ? word_token :
        make_token(Float(token))
    end

    def decimal?
      dot? || digit?
    end

    def word
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
         '^', '\\'].include?(char)
    end

    def space
      delimit
      self.indent += 1 if (tokens.last && tokens.last.last == :EOL)
    end

    def space?
      char == ' ' || char == "\t" || char == "\r"
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
        root
      end
    end

    def delimit
      if !token.empty?
        tokens << send(:"#{state}_token")
        self.state = :root
        self.token = ''
      end
    end

    def update_indentation
      while indent < indents.last
        tokens << make_token(:DEDENT)
        indents.pop
      end

      if indent > indents.last
        tokens << make_token(:INDENT)
        indents << indent
      end

      self.indent = 0
    end

    class LexError < StandardError; end
  end
end
