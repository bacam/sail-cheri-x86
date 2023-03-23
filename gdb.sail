function gdb_decode_cap(v) : bits(129) -> Capability =
  let tag = v[128] == bitone in
  memBitsToCapability(tag, v[127..0])

function gdb_encode_cap(c) : Capability -> bits(129) =
  bool_to_bits(c.tag) @ capToMemBits(c)

overload gdb_decode_register = { gdb_decode_cap }
overload gdb_encode_register = { gdb_encode_cap }