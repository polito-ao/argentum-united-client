extends Node
class_name ServerConnection

## TCP connection to the Argentum United server with MessagePack framing.
## Wire format: [uint16 length][uint16 packet_id][MessagePack payload]

signal connected
signal disconnected
signal packet_received(packet_id: int, payload: Dictionary)

@export var host: String = "127.0.0.1"
@export var port: int = 7666

var _socket: StreamPeerTCP
var _buffer: PackedByteArray = PackedByteArray()
var _connected: bool = false

func _ready():
	_socket = StreamPeerTCP.new()
	_socket.set_big_endian(true)

func connect_to_server() -> Error:
	var err = _socket.connect_to_host(host, port)
	if err != OK:
		push_error("Failed to connect: %s" % err)
		return err
	return OK

func _process(_delta):
	if _socket == null:
		return

	_socket.poll()
	var status = _socket.get_status()

	match status:
		StreamPeerTCP.STATUS_CONNECTED:
			if not _connected:
				_connected = true
				connected.emit()
			_read_packets()
		StreamPeerTCP.STATUS_NONE, StreamPeerTCP.STATUS_ERROR:
			if _connected:
				_connected = false
				disconnected.emit()

func send_packet(packet_id: int, payload: Dictionary = {}) -> void:
	var packed = _msgpack_encode(payload)
	var body_length = 2 + packed.size()

	var header = PackedByteArray()
	header.resize(4)
	header[0] = (body_length >> 8) & 0xff  # big-endian length
	header[1] = body_length & 0xff
	header[2] = (packet_id >> 8) & 0xff    # big-endian packet_id
	header[3] = packet_id & 0xff

	_socket.put_data(header + packed)

func disconnect_from_server() -> void:
	if _socket:
		_socket.disconnect_from_host()
	_connected = false

func is_connected_to_server() -> bool:
	return _connected

func _read_packets() -> void:
	var available = _socket.get_available_bytes()
	if available <= 0:
		return

	var result = _socket.get_data(available)
	if result[0] != OK:
		print("[net] get_data error: ", result[0])
		return

	print("[net] Received %d bytes" % result[1].size())
	_buffer.append_array(result[1])
	_process_buffer()

func _read_u16_be(data: PackedByteArray, offset: int) -> int:
	return (data[offset] << 8) | data[offset + 1]

func _process_buffer() -> void:
	while _buffer.size() >= 4:
		var body_length = _read_u16_be(_buffer, 0)
		var total_length = 2 + body_length

		if _buffer.size() < total_length:
			break

		var packet_id = _read_u16_be(_buffer, 2)
		var payload_bytes = _buffer.slice(4, total_length)

		print("[net] Decoding packet 0x%04x, %d payload bytes" % [packet_id, payload_bytes.size()])

		var payload = {}
		if payload_bytes.size() > 0:
			payload = _msgpack_decode(payload_bytes)

		print("[net] Decoded: %s" % payload)
		_buffer = _buffer.slice(total_length)
		packet_received.emit(packet_id, payload)

# --- Minimal MessagePack encoder/decoder ---
# Handles: nil, bool, int, float, string, array, dict
# Enough for our protocol. Not a full implementation.

func _msgpack_encode(value) -> PackedByteArray:
	var buf = PackedByteArray()

	if value == null:
		buf.append(0xc0)
	elif value is bool:
		buf.append(0xc3 if value else 0xc2)
	elif value is int:
		if value >= 0 and value <= 127:
			buf.append(value)
		elif value >= -32 and value < 0:
			buf.append(value & 0xff)
		elif value >= 0 and value <= 0xffff:
			buf.append(0xcd)
			var b = PackedByteArray()
			b.resize(2)
			b.encode_u16(0, value)
			buf.append_array(b)
		elif value >= 0 and value <= 0xffffffff:
			buf.append(0xce)
			var b = PackedByteArray()
			b.resize(4)
			b.encode_u32(0, value)
			buf.append_array(b)
		elif value >= -128 and value < 0:
			buf.append(0xd0)
			buf.append(value & 0xff)
		elif value >= -32768 and value < 0:
			buf.append(0xd1)
			var b = PackedByteArray()
			b.resize(2)
			b.encode_s16(0, value)
			buf.append_array(b)
		else:
			buf.append(0xd2)
			var b = PackedByteArray()
			b.resize(4)
			b.encode_s32(0, value)
			buf.append_array(b)
	elif value is float:
		buf.append(0xcb)
		var b = PackedByteArray()
		b.resize(8)
		b.encode_double(0, value)
		buf.append_array(b)
	elif value is String:
		var utf8 = value.to_utf8_buffer()
		if utf8.size() <= 31:
			buf.append(0xa0 | utf8.size())
		elif utf8.size() <= 0xff:
			buf.append(0xd9)
			buf.append(utf8.size())
		elif utf8.size() <= 0xffff:
			buf.append(0xda)
			var b = PackedByteArray()
			b.resize(2)
			b.encode_u16(0, utf8.size())
			buf.append_array(b)
		buf.append_array(utf8)
	elif value is Array:
		if value.size() <= 15:
			buf.append(0x90 | value.size())
		elif value.size() <= 0xffff:
			buf.append(0xdc)
			var b = PackedByteArray()
			b.resize(2)
			b.encode_u16(0, value.size())
			buf.append_array(b)
		for item in value:
			buf.append_array(_msgpack_encode(item))
	elif value is Dictionary:
		if value.size() <= 15:
			buf.append(0x80 | value.size())
		elif value.size() <= 0xffff:
			buf.append(0xde)
			var b = PackedByteArray()
			b.resize(2)
			b.encode_u16(0, value.size())
			buf.append_array(b)
		for key in value:
			buf.append_array(_msgpack_encode(key))
			buf.append_array(_msgpack_encode(value[key]))

	return buf

func _msgpack_decode(data: PackedByteArray):
	var result = _msgpack_decode_at(data, 0)
	return result[0]

func _msgpack_decode_at(data: PackedByteArray, offset: int) -> Array:
	if offset >= data.size():
		return [null, offset]

	var byte = data[offset]

	# Positive fixint (0x00 - 0x7f)
	if byte <= 0x7f:
		return [byte, offset + 1]

	# Fixmap (0x80 - 0x8f)
	if byte >= 0x80 and byte <= 0x8f:
		var count = byte & 0x0f
		return _decode_map(data, offset + 1, count)

	# Fixarray (0x90 - 0x9f)
	if byte >= 0x90 and byte <= 0x9f:
		var count = byte & 0x0f
		return _decode_array(data, offset + 1, count)

	# Fixstr (0xa0 - 0xbf)
	if byte >= 0xa0 and byte <= 0xbf:
		var length = byte & 0x1f
		var str_data = data.slice(offset + 1, offset + 1 + length)
		return [str_data.get_string_from_utf8(), offset + 1 + length]

	# Negative fixint (0xe0 - 0xff)
	if byte >= 0xe0:
		return [byte - 256, offset + 1]

	match byte:
		0xc0: return [null, offset + 1]  # nil
		0xc2: return [false, offset + 1]  # false
		0xc3: return [true, offset + 1]   # true
		0xcc: return [data[offset + 1], offset + 2]  # uint8
		0xcd: return [data.decode_u16(offset + 1), offset + 3]  # uint16
		0xce: return [data.decode_u32(offset + 1), offset + 5]  # uint32
		0xd0: # int8
			var v = data[offset + 1]
			if v >= 128: v -= 256
			return [v, offset + 2]
		0xd1: return [data.decode_s16(offset + 1), offset + 3]  # int16
		0xd2: return [data.decode_s32(offset + 1), offset + 5]  # int32
		0xcb: return [data.decode_double(offset + 1), offset + 9]  # float64
		0xd9: # str8
			var length = data[offset + 1]
			var str_data = data.slice(offset + 2, offset + 2 + length)
			return [str_data.get_string_from_utf8(), offset + 2 + length]
		0xda: # str16
			var length = data.decode_u16(offset + 1)
			var str_data = data.slice(offset + 3, offset + 3 + length)
			return [str_data.get_string_from_utf8(), offset + 3 + length]
		0xdc: # array16
			var count = data.decode_u16(offset + 1)
			return _decode_array(data, offset + 3, count)
		0xde: # map16
			var count = data.decode_u16(offset + 1)
			return _decode_map(data, offset + 3, count)

	push_warning("Unknown msgpack byte: 0x%02x at offset %d" % [byte, offset])
	return [null, offset + 1]

func _decode_map(data: PackedByteArray, offset: int, count: int) -> Array:
	var result = {}
	for i in count:
		var key_result = _msgpack_decode_at(data, offset)
		offset = key_result[1]
		var val_result = _msgpack_decode_at(data, offset)
		offset = val_result[1]
		result[key_result[0]] = val_result[0]
	return [result, offset]

func _decode_array(data: PackedByteArray, offset: int, count: int) -> Array:
	var result = []
	for i in count:
		var item_result = _msgpack_decode_at(data, offset)
		offset = item_result[1]
		result.append(item_result[0])
	return [result, offset]
