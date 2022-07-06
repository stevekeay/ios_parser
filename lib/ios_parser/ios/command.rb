require 'json'
require_relative 'queryable'

module IOSParser
  class IOS
    class Command
      include Enumerable
      include Queryable
      attr_accessor :commands, :parent, :document, :indent, :tokens
      def initialize(tokens: [], commands: [],
                     parent: nil, document: nil, indent: nil)
        @tokens = tokens
        @commands = commands
        @parent = parent
        @document = document
        @indent = indent || 0
      end

      def args
        tokens.map(&:value)
      end

      def name
        (tokens.first) && tokens.first.value
      end

      def ==(other)
        args == other.args && commands == other.commands
      end

      def eql?(other)
        self == other && self.class == other.class
      end

      def line
        args.join(' ')
      end

      def path
        parent ? parent.path + [parent.line] : []
      end

      def pos
        tokens.first && tokens.first.pos
      end

      def indentation(base: 0)
        ' ' * (path.length - base)
      end

      def each
        yield self
        commands.each { |command| command.each { |cmd| yield cmd } }
      end

      def inspect
        "<IOSParser::IOS::Command:0x#{object_id.to_s(16)} "\
        "@tokens=#{tokens.inspect}, "\
        "@commands=#{commands.inspect}, "\
        "@pos=#{pos.inspect}, "\
        "@indent=#{indent}, "\
        "@document=<IOSParser::IOS::Document:0x#{document.object_id.to_s(16)}>>"
      end

      def to_s(dedent: false)
        indent_opts = { base: dedent ? path.length : 0 }
        map { |cmd| "#{cmd.indentation(indent_opts)}#{cmd.line}\n" }.join
      end

      def to_hash
        {
          args: args,
          commands: commands.map(&:to_hash),
          pos: pos,
          indent: indent
        }
      end

      def to_json
        JSON.dump(to_hash)
      end

      class << self
        def from_hash(hash, parent = nil)
          hash[:parent] = parent
          [:args, :commands, :pos].each do |key|
            val = hash.delete(key.to_s)
            hash[key] ||= val
          end

          hash[:commands] ||= []
          hash[:commands].each_index do |i|
            hash[:commands][i] = from_hash(hash[:commands][i])
          end
          new(hash)
        end
      end
    end # class Command
  end # class IOS
end # module IOSParser
