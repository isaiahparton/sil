package son

import "core:io"
import "core:os"
import "core:fmt"
import "core:math/bits"
import "core:strings"
import "core:strconv"
import "core:runtime"

import "core:unicode"
import "core:unicode/utf8"

Composer :: struct {
	w: io.Writer,
	indent: int,
	lines: int,
	ignore_zero_fields: bool,
}
write_indent :: proc(c: ^Composer) -> (err: Error) {
	io.write_byte(c.w, '\n') or_return
	for i in 0..<c.indent {
		io.write_rune(c.w, INDENT_RUNE) or_return
	}
	return
}
write_value_separator :: proc(c: ^Composer, type_info: ^runtime.Type_Info) -> (err: Error) {
	#partial switch info in type_info.variant {
		case runtime.Type_Info_Array, runtime.Type_Info_Dynamic_Array, runtime.Type_Info_Slice, runtime.Type_Info_Enumerated_Array, runtime.Type_Info_Map, runtime.Type_Info_Struct:
		c.indent += 1
		write_indent(c)

		case: 
		io.write_rune(c.w, VALUE_SEPARATOR_RUNE) or_return
	}
	return
}
write_element_separator :: proc(c: ^Composer, type_info: ^runtime.Type_Info) -> (err: Error) {
	#partial switch info in type_info.variant {
		case runtime.Type_Info_Array, runtime.Type_Info_Dynamic_Array, runtime.Type_Info_Slice, runtime.Type_Info_Enumerated_Array, runtime.Type_Info_Map, runtime.Type_Info_Struct:
		io.write_byte(c.w, '-') or_return
		c.indent += 1
		write_indent(c) or_return
	}
	return
}
compose :: proc(c: ^Composer, v: any) -> (err: Error) {
	ti := runtime.type_info_base(type_info_of(v.id))

	#partial switch info in ti.variant {
		case runtime.Type_Info_Dynamic_Array:
		arr := transmute(^runtime.Raw_Dynamic_Array)v.data
		for i in 0..<arr.len {
			if (i > 0) {
				write_indent(c)
			}
			prev_indent := c.indent
			write_element_separator(c, runtime.type_info_base(info.elem)) or_return
			compose(c, any{data = rawptr(uintptr(arr.data) + uintptr(i * info.elem_size)), id = info.elem.id}) or_return
			c.indent = prev_indent
		}

		case runtime.Type_Info_Slice:
		slc := transmute(^runtime.Raw_Slice)v.data
		for i in 0..<slc.len {
			if (i > 0) {
				write_indent(c)
			}
			prev_indent := c.indent
			write_element_separator(c, runtime.type_info_base(info.elem)) or_return
			compose(c, any{data = rawptr(uintptr(slc.data) + uintptr(i * info.elem_size)), id = info.elem.id}) or_return
			c.indent = prev_indent
		}

		case runtime.Type_Info_Array:
		for i in 0..<info.count {
			if (i > 0) {
				write_indent(c)
			}
			prev_indent := c.indent
			write_element_separator(c, runtime.type_info_base(info.elem)) or_return
			compose(c, any{data = rawptr(uintptr(v.data) + uintptr(i * info.elem_size)), id = info.elem.id}) or_return
			c.indent = prev_indent
		}

		case runtime.Type_Info_Union:
		tag_ptr := uintptr(v.data) + info.tag_offset
		tag_any := any{rawptr(tag_ptr), info.tag_type.id}
		tag: i64 = -1
		switch i in tag_any {
			case u8:   tag = i64(i)
			case i8:   tag = i64(i)
			case u16:  tag = i64(i)
			case i16:  tag = i64(i)
			case u32:  tag = i64(i)
			case i32:  tag = i64(i)
			case u64:  tag = i64(i)
			case i64:  tag = i64(i)
			case: panic("Invalid union tag type")
		}
		if v.data == nil || tag == 0 {
			io.write_string(c.w, "nil") or_return
		} else {
			id := info.variants[tag-1].id
			io.write_i64(c.w, tag - 1) or_return
			write_value_separator(c, info.variants[tag-1])
			compose(c, any{v.data, id}) or_return
		}

		case runtime.Type_Info_Struct:
		for name, i in info.names {
			if (i > 0) {
				write_indent(c)
			}
			if (len(info.tags[i]) > 0) && (info.tags[i][0] == '#') {
				io.write_string(c.w, info.tags[i])
				write_indent(c)
			}
			io.write_string(c.w, name) or_return
			prev_indent := c.indent
			write_value_separator(c, runtime.type_info_base(info.types[i])) or_return
			compose(c, any{data = rawptr(uintptr(v.data) + info.offsets[i]), id = info.types[i].id}) or_return
			c.indent = prev_indent
		}

		case runtime.Type_Info_String: 
		switch i in v {
			case string:
			io.write_quoted_string(c.w, i) or_return
		}

		case runtime.Type_Info_Bit_Set: 
		is_bit_set_different_endian_to_platform :: proc(ti: ^runtime.Type_Info) -> bool {
			if (ti == nil) {
				return false
			}
			t := runtime.type_info_base(ti)
			#partial switch info in t.variant {
				case runtime.Type_Info_Integer:
				switch info.endianness {
					case .Platform: return false
					case .Little:   return ODIN_ENDIAN != .Little
					case .Big:      return ODIN_ENDIAN != .Big
				}
			}
			return false
		}
		bit_data: u64
		bit_size := u64(8*ti.size)
		do_byte_swap := is_bit_set_different_endian_to_platform(info.underlying)
		switch bit_size {
			case  0: bit_data = 0
			case  8:
				x := (^u8)(v.data)^
				bit_data = u64(x)
			case 16:
				x := (^u16)(v.data)^
				if do_byte_swap {
					x = bits.byte_swap(x)
				}
				bit_data = u64(x)
			case 32:
				x := (^u32)(v.data)^
				if do_byte_swap {
					x = bits.byte_swap(x)
				}
				bit_data = u64(x)
			case 64:
				x := (^u64)(v.data)^
				if do_byte_swap {
					x = bits.byte_swap(x)
				}
				bit_data = u64(x)
			case: panic("unknown bit_size size")
		}
		io.write_u64(c.w, bit_data, 16) or_return

		case runtime.Type_Info_Enum: 
		compose(c, {v.data, info.base.id})

		case runtime.Type_Info_Integer: 
		switch i in v {
			case int: 	io.write_int(c.w, i) or_return
			case i128: 	io.write_i128(c.w, i) or_return
			case i64: 	io.write_i64(c.w, i) or_return
			case i32: 	io.write_i64(c.w, i64(i)) or_return
			case i16: 	io.write_i64(c.w, i64(i)) or_return
			case i8: 		io.write_i64(c.w, i64(i)) or_return
			case uint: 	io.write_uint(c.w, i) or_return
			case u128: 	io.write_u128(c.w, i) or_return
			case u64: 	io.write_u64(c.w, i) or_return
			case u32: 	io.write_u64(c.w, u64(i)) or_return
			case u16: 	io.write_u64(c.w, u64(i)) or_return
			case u8: 		io.write_u64(c.w, u64(i)) or_return
			case: 
			return .Unsupported_Type,
		}

		case runtime.Type_Info_Float: 
		buf: [84]u8
		switch i in v {
			case f64, f32, f16: io.write_string(c.w, fmt.bprintf(buf[:], "%.3f", i))
		}

		case runtime.Type_Info_Boolean:
		value: bool 
		switch i in v {
			case bool: value = i
			case b8: value = bool(i)
			case b16: value = bool(i)
			case b32: value = bool(i)
			case b64: value = bool(i)
		}
		io.write_string(c.w, "true" if value else "false")

		case runtime.Type_Info_Procedure: 
		return

		case runtime.Type_Info_Pointer:
		return

		case runtime.Type_Info_Rune: 
		io.write_byte(c.w, '\'')
		io.write_escaped_rune(c.w, v.(rune), '\'') or_return
		io.write_byte(c.w, '\'')

		case runtime.Type_Info_Map: 
		m := (^runtime.Raw_Map)(v.data)
		if m != nil {
			if info.map_info == nil {
				return .Unsupported_Type
			}
			map_cap := uintptr(runtime.map_cap(m^))
			ks, vs, hs, _, _ := runtime.map_kvh_data_dynamic(m^, info.map_info)
			i := 0
			for bucket_index in 0..<map_cap {
				if !runtime.map_hash_is_valid(hs[bucket_index]) {
					continue
				}
				if i > 0 {
					write_indent(c) or_return
				}
				i += 1
				key   := rawptr(runtime.map_cell_index_dynamic(ks, info.map_info.ks, bucket_index))
				value := rawptr(runtime.map_cell_index_dynamic(vs, info.map_info.vs, bucket_index))
				// Save previous indent
				prev_indent := c.indent
				// Begin the entry
				io.write_string(c.w, "-") or_return
				c.indent += 1
				write_indent(c) or_return
				// Print the key as a struct field
				{
					io.write_string(c.w, "key") or_return
					prev_indent := c.indent
					write_value_separator(c, runtime.type_info_base(info.key)) or_return
					compose(c, any{key, info.key.id}) or_return
					c.indent = prev_indent
					write_indent(c) or_return
				}
				// And likewise, the value
				{
					io.write_string(c.w, "value") or_return
					prev_indent := c.indent
					write_value_separator(c, runtime.type_info_base(info.value)) or_return
					compose(c, any{value, info.value.id}) or_return
					c.indent = prev_indent
				}
				// Return to previous indent
				c.indent = prev_indent
			}
		}
	}
	c.lines += 1

	return
}