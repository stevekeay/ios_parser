require_relative 'queryable'
require_relative 'command'

module IOSParser
  class IOS
    class Document
      include Queryable, Enumerable
      attr_accessor :commands, :parent, :source

      def initialize(source)
        @commands = []
        @parent = nil
        @source = source
      end

      [:[], :push].each do |method|
        define_method(method) { |*args| commands.send(method, *args) }
      end

      def each
        commands.each { |command| command.each { |cmd| yield cmd } }
      end

      def to_s(dedent: false)
        base = dedent ? indentation : 0
        map { |cmd| "#{cmd.indentation(base: base)}#{cmd.line}\n" }.join
      end

      def to_hash
        { commands: commands.map(&:to_hash) }
      end

      def to_json
        MultiJson.dump(to_hash)
      end

      class << self
        def from_hash(hash)
          hash[:parent] = parent
          [:commands, :source].each do |key|
            val = hash.delete(key.to_s)
            hash[key] = val unless hash.key?(key)
          end

          new(source).tap do |doc|
            doc.push(*(hash[:commands].map { |c| Command.from_hash(c) }))
          end
        end
      end # class << self
    end # class Document
  end # class IOS
end # class IOSParser
