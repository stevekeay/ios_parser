module IOSParser
  class IOS
    module Queryable

      def find_all(expr, &blk)
        _find_all(MatcherReader.query_expression(expr), &blk)
      end

      def find(expr, &blk)
        _find(MatcherReader.query_expression(expr), &blk)
      end

      def _find_all(expr, &blk)
        [].tap do |ret|
          commands.each do |command|
            if expr.keys.all? { |key| Matcher.send(key, expr[key], command) }
              ret << command
              blk.call(command) if blk
            end

            ret.push(*command._find_all(expr, &blk))
          end
        end
      end

      def _find(expr, &blk)
        _find_all(expr) do |command|
          blk.call(command) if blk
          return command
        end
        nil
      end

      module MatcherReader
        class << self

          def query_expression(raw)
            case raw
            when Hash
              raw.keys.each do |key|
                raw[key] &&= send(key, raw[key])
              end
              raw

            when Proc          then { procedure: procedure(raw) }
            when Regexp        then { line: line(raw) }
            when String, Array then { starts_with: starts_with(raw) }
            else fail("Invalid query: #{raw.inspect}")
            end
          end

          def name(expr)
            expr
          end

          def starts_with(expr)
            case expr
            when String then expr.split
            when Array  then expr
            else fail("Invalid #{__method__} condition in query: #{expr}")
            end
          end

          alias_method :contains, :starts_with
          alias_method :ends_with, :starts_with

          def procedure(expr)
            unless expr.respond_to?(:call)
              fail("Invalid procedure in query: #{expr}")
            end
            expr
          end

          def line(expr)
            case expr
            when String, Regexp then expr
            when Array          then expr.join(' ')
            else fail("Invalid line condition in query: #{expr}")
            end
          end

          alias_method :parent, :query_expression

          def any(expr)
            unless expr.kind_of?(Array)
              fail("Invalid disjunction in query: #{expr}")
            end
            expr.map { |e| query_expression(e) }
          end

          def all(expr)
            unless expr.kind_of?(Array)
              fail("Invalid conjunction in query: #{expr}")
            end
            expr.map { |e| query_expression(e) }
          end

          def depth(expr)
            unless expr.kind_of?(Integer)
              fail("Invalid depth constraint in query: #{expr}")
            end
            expr
          end

        end # class << self
      end # module MatcherReader

      module Matcher
        class << self

          def name(expr, command)
            expr === command.name
          end

          def starts_with(req_ary, command)
            (0 .. req_ary.length - 1).all? do |i|
              case req_ary[i]
              when String then req_ary[i] == command.args[i].to_s
              else             req_ary[i] === command.args[i]
              end
            end
          end

          def contains(req_ary, command)
            (0 .. command.args.length - req_ary.length).any? do |j|
              (0 .. req_ary.length - 1).all? do |i|
                case req_ary[i]
                when String then req_ary[i] == command.args[i+j].to_s
                else             req_ary[i] === command.args[i+j]
                end
              end
            end
          end

          def ends_with(req_ary, command)
            (1 .. req_ary.length).all? do |i|
              case req_ary[-i]
              when String then req_ary[-i] == command.args[-i].to_s
              else             req_ary[-i] === command.args[-i]
              end
            end
          end

          def procedure(expr, command)
            expr.call(command)
          end

          def line(expr, command)
            expr === command.line
          end

          def parent(expr, command)
            expr.keys.all? do |key|
              command.parent && send(key, expr[key], command.parent)
            end
          end

          def any(expressions, command)
            expressions.any? do |expr|
              expr.keys.all? do |key|
                send(key, expr[key], command)
              end
            end
          end

          def all(expressions, command)
            expressions.all? do |expr|
              expr.keys.all? do |key|
                send(key, expr[key], command)
              end
            end
          end

          def depth(expr, command)
            level = 0
            ptr = command
            while ptr.parent
              ptr = ptr.parent
              level += 1
              return false if level > expr
            end
            level == expr
          end

        end # class << self
      end # module Matcher

    end # module Queryable
  end # class IOS
end # module IOSParser

