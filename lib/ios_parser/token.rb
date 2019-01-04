module IOSParser
  Token = Struct.new(
    :value,
    :pos,
    :line,
    :col
  )
end
