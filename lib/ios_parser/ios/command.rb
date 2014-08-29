require_relative 'queryable'

module IOSParser
  class IOS
    class Command

      include Queryable, Enumerable
      attr_accessor :args, :commands, :parent, :pos, :document

      def initialize(opts = {})
        defaults = {
          args: [],
          commands: [],
          parent: nil,
          pos: nil,
          document: nil
        }

        defaults.keys.each do |key|
          self.send(:"#{key}=", opts[key] || defaults[key])
        end
      end

      def name
        args[0]
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

      def indentation(base: 0)
        " " * (path.length - base)
      end

      def each
        yield self
        commands.each { |command| command.each { |cmd| yield cmd } }
      end

      def inspect
        "<IOSParser::IOS::Command:0x#{object_id.to_s(16)} "\
        "@args=#{args.inspect}, "\
        "@commands=#{commands.inspect}, "\
        "@pos=#{pos.inspect}, "\
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
          pos: pos
        }
      end

      def to_json
        MultiJson.dump(to_hash)
      end

      class << self
        def from_hash(hash, parent = nil)
          hash[:parent] = parent
          [:args, :commands, :pos].each do |key|
            val = hash.delete(key.to_s)
            hash[key] = val unless hash.key?(key)
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

