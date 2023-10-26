package sil

import "core:io"
import "core:os"
import "core:fmt"
import "core:mem"
import "core:slice"
import "core:math/bits"
import "core:strings"
import "core:strconv"
import "core:runtime"

import "core:unicode"
import "core:unicode/utf8"

Parse_Error :: enum {
	Literal_Not_Found,
	Invalid_Indentation,
	Invalid_Enum_Value,
	Invalid_Enum_Value_Type,
}

Parser :: struct {
	t: Tokenizer,
	token,
	last_token: Token,
}

parse :: proc(p: ^Parser, v: any) -> (err: Error) {
	// Get the pointer
	ti := runtime.type_info_base(type_info_of(v.id))

	#partial switch info in ti.variant {
		case runtime.Type_Info_Pointer:
		// Look where the pointer points and parse that
		return parse(p, any{data = (transmute(^rawptr)v.data)^, id = info.elem.id})

		case runtime.Type_Info_Slice: 
		return .Unsupported_Type
		/*// Make a dynamic array first
		raw_array: runtime.Raw_Dynamic_Array
		// Expected column for identifiers
		column := p.last_token.column + 1
		// Loop until indent decreases
		for {
			p.token, err = expect_token_indent(p, {.Separator}, column)
			if err != nil {
				if err == .Invalid_Indentation {
					err = nil
					break
				} else {
					return
				}
			}
			item_data, _ := mem.alloc(info.elem.size)
			defer mem.free(item_data)
			parse(p, any{data = item_data, id = info.elem.id}) or_return
			runtime.__dynamic_array_append(v.data, info.elem_size, info.elem.align, item_data, 1)
		}
		// Assign the data to the slice*/

		case runtime.Type_Info_Union: 
		index := 1
		if len(info.variants) > 1 {
			// Get tag value
			p.token = expect_token(p, {.Integer}) or_return
			if n, ok := strconv.parse_int(p.token.text); ok {
				if n > len(info.variants) {
					fmt.printf("\033[1m[%i:%i] Union tag out of bounds!\033[0m\n", p.token.line, p.token.column)
					print_loc_helper(p.t.data, p.token.loc, p.token.width)
					break
				} else {
					index = n
				}
			}
		}
		parse(p, any{data = v.data, id = info.variants[index if info.no_nil else (index - 1)].id})
		tag_v := any{data = rawptr(uintptr(v.data) + info.tag_offset), id = info.tag_type.id}
		switch &tag in &tag_v {
			case i8: tag = i8(index)
			case u8: tag = u8(index)
			case i16: tag = i16(index)
			case u16: tag = u16(index)
			case i32: tag = i32(index)
			case u32: tag = u32(index)
			case i64: tag = i64(index)
			case u64: tag = u64(index)
		}

		case runtime.Type_Info_Array: 
		// Expected column for identifiers
		column := p.last_token.column + 1
		// Require separator?
		require_separator := type_requires_separator(info.elem)
		// Stuff
		index: int
		// Loop until indent decreases
		for {
			p.token, err = expect_token_indent(p, {.Separator}, column)
			if err != nil {
				if err == .Invalid_Indentation {
					err = nil
					break
				} else {
					return
				}
			}
			parse(p, any{data = rawptr(uintptr(v.data) + uintptr(index * info.elem_size)), id = info.elem.id}) or_return
			index += 1
			if index == info.count {
				break
			}
		}

		case runtime.Type_Info_Dynamic_Array: 
		// Expected column for identifiers
		column := p.last_token.column + 1
		// Loop until indent decreases
		for {
			p.token, err = expect_token_indent(p, {.Separator}, column)
			if err != nil {
				if err == .Invalid_Indentation {
					err = nil
					break
				} else {
					return
				}
			}
			item_data, _ := mem.alloc(info.elem.size)
			defer mem.free(item_data)
			parse(p, any{data = item_data, id = info.elem.id}) or_return
			runtime.__dynamic_array_append(v.data, info.elem_size, info.elem.align, item_data, 1)
		}

		case runtime.Type_Info_Map:
		// Get raw map
		raw_map := transmute(^runtime.Raw_Map)v.data
		// Expected column for identifiers
		column := p.last_token.column + 1
		// Loop until indent decreases
		for {
			p.token, err = expect_token_indent(p, {.Separator}, column)
			if err != nil {
				if err == .Invalid_Indentation {
					err = nil
					break
				} else {
					return
				}
			}
			column := p.last_token.column + 1
			// Key
			p.token = expect_token_indent(p, {.Identifier}, column) or_return
			if p.token.text == "key" {
				key_data, _ := mem.alloc(info.key.size)
				defer mem.free(key_data)
				parse(p, any{data = key_data, id = info.key.id}) or_return 
				// Value
				p.token = expect_token_indent(p, {.Identifier}, column) or_return
				if p.token.text == "value" {
					value_data, _ := mem.alloc(info.value.size)
					defer mem.free(value_data)
					parse(p, any{data = value_data, id = info.value.id}) or_return 
					// Insert new pair
					runtime.__dynamic_map_set_without_hash(raw_map, info.map_info, key_data, value_data)
				}
			}
		}

		case runtime.Type_Info_Struct:
		// Expected column for identifiers
		column := p.last_token.column + 1
		// Loop until indent decreases
		for {
			p.token, err = expect_token_indent(p, {.Identifier}, column)
			if err != nil {
				if err == .Invalid_Indentation {
					err = nil
					break
				} else {
					return
				}
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
		p.token = expect_literal(p, {.String}) or_return 
		(transmute(^string)v.data)^ = strings.clone(p.token.text)

		case runtime.Type_Info_Boolean: 
		p.token = expect_literal(p, {.True, .False}) or_return
		(transmute(^bool)v.data)^ = true if p.token.kind == .True else false

		case runtime.Type_Info_Bit_Set:
		p.token = expect_literal(p, {.Integer}) or_return 
		if info.underlying == nil {
			value := strconv.parse_u64(p.token.text) or_else 0
			mem.copy(v.data, &value, ti.size)
		} else {
			switch info.underlying.id {
				case u8: 		(transmute(^u8)v.data)^ = u8(strconv.parse_u64(p.token.text) or_else 0)
				case u16: 	(transmute(^u16)v.data)^ = u16(strconv.parse_u64(p.token.text) or_else 0)
				case u32: 	(transmute(^u32)v.data)^ = u32(strconv.parse_u64(p.token.text) or_else 0)
				case u64: 	(transmute(^u64)v.data)^ = u64(strconv.parse_u64(p.token.text) or_else 0)
				case u128: 	(transmute(^u128)v.data)^ = u128(strconv.parse_u128(p.token.text) or_else 0)
				case uint: 	(transmute(^uint)v.data)^ = uint(strconv.parse_uint(p.token.text) or_else 0)
				case i8: 		(transmute(^i8)v.data)^ = i8(strconv.parse_i64(p.token.text) or_else 0)
				case i16: 	(transmute(^i16)v.data)^ = i16(strconv.parse_i64(p.token.text) or_else 0)
				case i32: 	(transmute(^i32)v.data)^ = i32(strconv.parse_i64(p.token.text) or_else 0)
				case i64: 	(transmute(^i64)v.data)^ = i64(strconv.parse_i64(p.token.text) or_else 0)
				case i128: 	(transmute(^i128)v.data)^ = i128(strconv.parse_i128(p.token.text) or_else 0)
				case int: 	(transmute(^int)v.data)^ = int(strconv.parse_int(p.token.text) or_else 0)
			}
		}

		case runtime.Type_Info_Enum:
		p.token = expect_literal(p, {.Identifier, .Integer}) or_return
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
		p.token = expect_literal(p, {.Integer}) or_return
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
		p.token = expect_literal(p, {.Integer, .Real}) or_return
		switch &i in v {
			case f64: i = strconv.parse_f64(p.token.text) or_else 0
			case f32: i = f32(strconv.parse_f64(p.token.text) or_else 0)
			case f16: i = f16(strconv.parse_f64(p.token.text) or_else 0)
		}
	}

	return
}

skip_comments :: proc(p: ^Parser) -> (token: Token, err: Error) {
	token, err = next_token(&p.t)
	for token.kind == .Comment {
		token, err = next_token(&p.t)
	}
	return
}

expect_literal :: proc(p: ^Parser, kinds: Token_Kind_Set) -> (token: Token, err: Error) {
	loc := p.last_token.loc
	token, err = expect_token(p, kinds)
	if token.column <= loc.column || token.line < loc.line || token.line > loc.line + 1 {
		err = .Literal_Not_Found
	}
	p.last_token = token
	return
}

expect_token_indent :: proc(p: ^Parser, kinds: Token_Kind_Set, column: int) -> (token: Token, err: Error) {
	token, err = skip_comments(p)
	if token.column != column {
		p.t.next_token = token
		err = .Invalid_Indentation
		return
	}
	if err == Tokenize_Error.EOF {
		return
	}
	if token.kind == .Invalid {
		err = .Invalid_Token
	} else if token.kind not_in kinds {
		// Print useful error messages
		err = .Unexpected_Token
		fmt.printf("\033[1m[%i:%i] Expected one of %v, but got %v\033[0m\n", token.line, token.column, kinds, token.kind)
		print_loc_helper(p.t.data, token.loc, token.width)
	}
	p.last_token = token
	return
}

expect_token :: proc(p: ^Parser, kinds: Token_Kind_Set) -> (token: Token, err: Error) {
	token, err = skip_comments(p)
	if token.kind == .Invalid {
		err = .Invalid_Token
	} else if token.kind not_in kinds {
		// Print useful error messages
		err = .Unexpected_Token
		fmt.printf("\033[1m[%i:%i] Expected one of %v, but got %v\033[0m\n", token.line, token.column, kinds, token.kind)
		print_loc_helper(p.t.data, token.loc, token.width)
	}
	p.last_token = token
	return
}