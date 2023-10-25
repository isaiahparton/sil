package sil

import "core:io"
import "core:os"
import "core:fmt"
import "core:mem"
import "core:math/bits"
import "core:strings"
import "core:strconv"
import "core:runtime"

import "core:unicode"
import "core:unicode/utf8"

Parse_Error :: enum {
	Literal_Not_Found,
	Invalid_Enum_Value,
	Invalid_Enum_Value_Type,
}

Parser :: struct {
	t: Tokenizer,
	token: Token,
}

parse :: proc(p: ^Parser, v: any) -> (err: Error) {
	// Get the pointer
	ti := runtime.type_info_base(type_info_of(v.id))

	#partial switch info in ti.variant {
		case runtime.Type_Info_Pointer:
		// Look where the pointer points and parse that
		return parse(p, any{data = (transmute(^rawptr)v.data)^, id = info.elem.id})

		case runtime.Type_Info_Struct:
		// Expected column for identifiers
		column := p.t.last_token.column + 1
		// Loop until indent decreases
		for {
			p.token = expect_token(&p.t, {.Identifier}) or_return
			if p.token.loc.column != column {
				if p.token.loc.column > column {
					fmt.printf("\033[1m[%i:%i] Invalid indentation in struct field\033[0m\n", p.token.line, p.token.column)
					print_loc_helper(p.t.data, p.token.loc, p.token.width)
				} else {
					p.t.next_token = p.token
				}
				break
			}
			// Find field
			found := false
			for name, i in info.names {
				if name == p.token.text {
					parse(p, any{data = rawptr(uintptr(v.data) + info.offsets[i]), id = info.types[i].id}) or_return
					found = true
					break
				}
			}
			if !found {
				fmt.printf("\033[1m[%i:%i] '%s' is not a valid struct field here\033[0m\n", p.token.line, p.token.column, p.token.text)
				print_loc_helper(p.t.data, p.token.loc, p.token.width)
				break
			}
		}

		case runtime.Type_Info_String: 
		p.token = expect_literal(&p.t, {.String}) or_return 
		(transmute(^string)v.data)^ = strings.clone(p.token.text)

		case runtime.Type_Info_Boolean: 
		p.token = expect_literal(&p.t, {.True, .False}) or_return
		(transmute(^bool)v.data)^ = true if p.token.kind == .True else false

		case runtime.Type_Info_Bit_Set:
		p.token = expect_literal(&p.t, {.Integer}) or_return 
		if info.underlying == nil {
			value := strconv.parse_u64(p.token.text) or_else 0
			mem.copy(v.data, &value, ti.size)
		} else {
			switch info.underlying.id {
				case u8: (transmute(^u8)v.data)^ = u8(strconv.parse_u64(p.token.text) or_else 0)
				case u16: (transmute(^u16)v.data)^ = u16(strconv.parse_u64(p.token.text) or_else 0)
				case u32: (transmute(^u32)v.data)^ = u32(strconv.parse_u64(p.token.text) or_else 0)
				case u64: (transmute(^u64)v.data)^ = u64(strconv.parse_u64(p.token.text) or_else 0)
				case u128: (transmute(^u128)v.data)^ = u128(strconv.parse_u128(p.token.text) or_else 0)
				case uint: (transmute(^uint)v.data)^ = uint(strconv.parse_uint(p.token.text) or_else 0)
				case i8: (transmute(^i8)v.data)^ = i8(strconv.parse_i64(p.token.text) or_else 0)
				case i16: (transmute(^i16)v.data)^ = i16(strconv.parse_i64(p.token.text) or_else 0)
				case i32: (transmute(^i32)v.data)^ = i32(strconv.parse_i64(p.token.text) or_else 0)
				case i64: (transmute(^i64)v.data)^ = i64(strconv.parse_i64(p.token.text) or_else 0)
				case i128: (transmute(^i128)v.data)^ = i128(strconv.parse_i128(p.token.text) or_else 0)
				case int: (transmute(^int)v.data)^ = int(strconv.parse_int(p.token.text) or_else 0)
			}
		}

		case runtime.Type_Info_Enum:
		p.token = expect_literal(&p.t, {.Identifier, .Integer}) or_return
		#partial switch p.token.kind {
			case .Identifier:
			found := false
			for name, i in info.names {
				if name == p.token.text {
					switch info.base.id {
						case u8: (transmute(^u8)v.data)^ = u8(info.values[i])
						case u16: (transmute(^u16)v.data)^ = u16(info.values[i])
						case u32: (transmute(^u32)v.data)^ = u32(info.values[i])
						case u64: (transmute(^u64)v.data)^ = u64(info.values[i])
						case u128: (transmute(^u128)v.data)^ = u128(info.values[i])
						case uint: (transmute(^uint)v.data)^ = uint(info.values[i])
						case i8: (transmute(^i8)v.data)^ = i8(info.values[i])
						case i16: (transmute(^i16)v.data)^ = i16(info.values[i])
						case i32: (transmute(^i32)v.data)^ = i32(info.values[i])
						case i64: (transmute(^i64)v.data)^ = i64(info.values[i])
						case i128: (transmute(^i128)v.data)^ = i128(info.values[i])
						case int: (transmute(^int)v.data)^ = int(info.values[i])
						case: return .Invalid_Enum_Value_Type
					}
					found = true
					break
				}
			}
			if !found {
				fmt.printf("\033[1m[%i:%i] '%s' is not a valid enum value\033[0m\n", p.token.line, p.token.column, p.token.text)
				print_loc_helper(p.t.data, p.token.loc, p.token.width)
				return .Invalid_Enum_Value
			}
			case .Integer:
			switch info.base.id {
				case u8: (transmute(^u8)v.data)^ = u8(strconv.parse_u64(p.token.text) or_else 0)
				case u16: (transmute(^u16)v.data)^ = u16(strconv.parse_u64(p.token.text) or_else 0)
				case u32: (transmute(^u32)v.data)^ = u32(strconv.parse_u64(p.token.text) or_else 0)
				case u64: (transmute(^u64)v.data)^ = u64(strconv.parse_u64(p.token.text) or_else 0)
				case u128: (transmute(^u128)v.data)^ = u128(strconv.parse_u128(p.token.text) or_else 0)
				case uint: (transmute(^uint)v.data)^ = uint(strconv.parse_uint(p.token.text) or_else 0)
				case i8: (transmute(^i8)v.data)^ = i8(strconv.parse_i64(p.token.text) or_else 0)
				case i16: (transmute(^i16)v.data)^ = i16(strconv.parse_i64(p.token.text) or_else 0)
				case i32: (transmute(^i32)v.data)^ = i32(strconv.parse_i64(p.token.text) or_else 0)
				case i64: (transmute(^i64)v.data)^ = i64(strconv.parse_i64(p.token.text) or_else 0)
				case i128: (transmute(^i128)v.data)^ = i128(strconv.parse_i128(p.token.text) or_else 0)
				case int: (transmute(^int)v.data)^ = int(strconv.parse_int(p.token.text) or_else 0)
				case: return .Invalid_Enum_Value_Type
			}
		}

		case runtime.Type_Info_Integer: 
		p.token = expect_literal(&p.t, {.Integer}) or_return
		switch &i in v {
			case int: i = strconv.parse_int(p.token.text) or_else 0
			case i128: i = strconv.parse_i128(p.token.text) or_else 0
			case i64: i = strconv.parse_i64(p.token.text) or_else 0
			case i32: i = i32(strconv.parse_i64(p.token.text) or_else 0)
			case i16: i = i16(strconv.parse_i64(p.token.text) or_else 0)
			case i8: i = i8(strconv.parse_i64(p.token.text) or_else 0)

			case uint: i = strconv.parse_uint(p.token.text) or_else 0
			case u128: i = strconv.parse_u128(p.token.text) or_else 0
			case u64: i = strconv.parse_u64(p.token.text) or_else 0
			case u32: i = u32(strconv.parse_u64(p.token.text) or_else 0)
			case u16: i = u16(strconv.parse_u64(p.token.text) or_else 0)
			case u8: i = u8(strconv.parse_u64(p.token.text) or_else 0)
		}

		case runtime.Type_Info_Float: 
		p.token = expect_literal(&p.t, {.Integer, .Real}) or_return
		switch &i in v {
			case f64: i = strconv.parse_f64(p.token.text) or_else 0
			case f32: i = f32(strconv.parse_f64(p.token.text) or_else 0)
			case f16: i = f16(strconv.parse_f64(p.token.text) or_else 0)
		}
	}
	return
}