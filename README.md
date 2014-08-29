ios_parser
==========

convert switch and router config files to structured data

Basic Parsing
-------------
    require 'ios_parser'
    text = my_method_to_get_a_raw_config
    config = IOSParser.parse(text)

JSON Serialization and Deserialization
--------------------------------------
    my_http_client.put_json(config.to_json)
    config = IOSParser.from_json(my_http_client.get_json)

Query for a single element (the first to match)
-----------------------------------------------
    config.find('hostname').to_hash
    # => { :args => ["hostname", "myswitch"], :commands => [] }

`case`-style Queries
--------------------
    config.find_all(starts_with: ['interface', /Gigabit/])
    # => [{:args=>["interface", "GigabitEthernet0/1"],
    #      :commands=>[{:args=>["switchport", "mode", "trunk"], :commands=>[]},
    #                  {:args=>["logging", "event", "trunk-status"], :commands=>[]},
    #                  {:args=>["speed", 1000], :commands=>[]}]},
    #     {:args=>["interface", "GigabitEthernet0/2"],
    #      :commands=>[{:args=>["switchport", "mode", "trunk"], :commands=>[]},
    #                  {:args=>["logging", "event", "trunk-status"], :commands=>[]},
    #                  {:args=>["speed", 1000], :commands=>[]}]}]

Chained Queries
---------------
    config.find(starts_with: ['interface', 'GigabitEthernet0/1']).find('speed').args[1]
    # => 1000
    
Nesting Queries
---------------
`#find_all` returns an `Array`, so you can't chain `IOSParser` queries after it. Instead, you can use nested queries with Ruby's `Array` and `Enumerable` APIs. This is useful to transform and clean data.

    config.find_all("interface").flat_map do |i|
      s = i.find("speed")
      s ? [{  interface: i.args.last,  speed: s.args.last  }] : []
    end
    # => [{:interface=>"GigabitEthernet0/1", :speed=>1000},
    #     {:interface=>"GigabitEthernet0/2", :speed=>1000}]

Available Query Matchers
------------------------
* `name` - matches the first argument of a command (e.g., `name: ip` will match `ip route` or `ip http server`)
* `starts_with` - matches the leading arguments of a command
* `contains` - matches any sequence of arguments of a command
* `ends_with` - matches the trailling arguments of a command
* `line` - matches the string form of a command (all the arguments separated by single spaces)
* `parent` - matches commands by their parents (e.g., `parent: { starts_with: 'interface' }` will match the first level of subcommands of any interface section)
* `any` - matches commands that match any of an array of queries (e.g., `any: [{ starts_with: 'interface' }, { contains: 'ip route' }]` will match all interfaces and all static routes)
* `all` - matches commands that match all of an array of queries (e.g., `all: ['interface', { line: /FastEthernet/ }]` will match all FastEthernet interfaces)
* `depth` - matches based on how many command sections contain the command (e.g., `depth: 0` will only match top-level commands)
