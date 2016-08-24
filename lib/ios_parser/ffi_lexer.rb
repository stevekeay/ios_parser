require 'ffi'
require 'ffi-compiler/loader'

module IOSParser
  class FFILexer
    module Ext
      extend FFI::Library
      ffi_lib FFI::Compiler::Loader.find('ios_parser_ext')

      TokenType = enum(
        :ERROR,
        :STRING,
        :INTEGER,
        :DECIMAL,
        :COMMENT,
        :INDENT,
        :DEDENT,
        :EOL,
        :BANNER_BEGIN,
        :BANNER_END,
        :CERTIFICATE_BEGIN,
        :CERTIFICATE_END
      )

      class Token < FFI::Struct
        layout :value, :string,
               :pos, :int,
               :type, Ext::TokenType

        def type
          self[:type]
        end

        def value
          self[:value]
        end

        def pos
          self[:pos]
        end

        def read
          case type
          when Fixnum   then raise "Invalid token type #{type}"
          when :ERROR   then raise LexError, value
          when :INTEGER then value.to_i
          when :DECIMAL then value.to_f
          when :STRING  then value
          else               type
          end
        end
      end

      class TokenStream < FFI::Struct
        include Enumerable

        layout :size, :int32,
               :capacity, :int32,
               :tokens, :pointer

        def size
          self[:size]
        end

        def token(index)
          Token.new(self[:tokens] + index * Token.size)
        end

        def each
          size.times do |i|
            tok = token(i)
            yield [tok.pos, tok.read]
          end
          self
        end

        def self.release(pointer)
          Ext.free_token_stream(pointer) unless pointer.null?
        end
      end

      attach_function :tokenize, [:string, :int], :pointer
      attach_function :free_token_stream, [:pointer], :void
    end

    def call(input_text)
      ptr = Ext.tokenize(input_text, input_text.size)
      Ext::TokenStream.new(ptr).to_a
    ensure
      Ext.free_token_stream(ptr)
    end
  end
end
