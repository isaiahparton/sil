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
	Invalid_Enum_Value,
	Invalid_Enum_Value_Type,
	Indent_Increased,
	Indent_Decreased,
}

Parser :: struct {
	t: Tokenizer,
	token,
	last_token: Token,
	// Expected indentation of tokens
	indent: int,
	// If parser should delete old data
	// replace: bool,
	ignore_unexpected: bool,
}

parse :: proc(p: ^Parser, v: any) -> (err: Error) {
	// Get the pointer
	ti := runtime.type_info_base(type_info_of(v.id))

	#partial switch info in ti.variant {
		case runtime.Type_Info_Pointer:
		// Look where the pointer points and parse that
		return parse(p, any{data = (transmute(^rawptr)v.data)^, id = info.elem.id})

		case runtime.Type_Info_Slice: 
		data, _ := runtime.mem_alloc(info.elem_size, align_of(info.elem.id))
		// Make a dynamic array first
		raw_array: runtime.Raw_Dynamic_Array = {
			data = raw_data(data),
			cap = 1,
		}
		p.indent += 1
		defer p.indent -= 1
		// Loop until indent decreases
		for {
			p.token, err = expect_token_indent(p, {.Separator})
			// Handle indent errors
			if err == .Indent_Increased || err == .Indent_Decreased || err == Tokenize_Error.EOF {
				err = nil
				break
			} else if err != nil {
				return
			}
			item_data, _ := mem.alloc(info.elem.size)
			defer mem.free(item_data)
			parse(p, any{data = item_data, id = info.elem.id}) or_return
			runtime.__dynamic_array_append(&raw_array, info.elem_size, info.elem.align, item_data, 1)
		}
		// Assign the data to the slice
		(transmute(^runtime.Raw_Slice)v.data)^ = {
			data = raw_array.data,
			len = raw_array.len,
		}

		case runtime.Type_Info_Union: 
		tag_any := any{data = rawptr(uintptr(v.data) + info.tag_offset), id = info.tag_type.id}
		if info.no_nil {
			p.token = expect_token(p, {.Integer}) or_return
			if n, ok := strconv.parse_int(p.token.text); ok {
				parse(p, any{data = v.data, id = info.variants[n].id})
				switch t in &tag_any {
					case i8: t = i8(n)
					case u8: t = u8(n)
					case i16: t = i16(n)
					case u16: t = u16(n)
					case i32: t = i32(n)
					case u32: t = u32(n)
					case i64: t = i64(n)
					case u64: t = u64(n)
				}
			}
		} else {
			tag: Maybe(int) = 0
			if len(info.variants) > 1 {
				p.token = expect_token(p, {.Integer, .Nil}) or_return
				#partial switch p.token.kind {
					case .Integer: 
					if n, ok := strconv.parse_int(p.token.text); ok {
						tag = n
					}
					case .Nil: 
					tag = nil
				}
			}
			if i, ok := tag.?; ok {
				parse(p, any{data = v.data, id = info.variants[i].id})
			}
			n := 0
			if i, ok := tag.?; ok {
				n = i + 1
			}
			switch t in &tag_any {
				case i8: t = i8(n)
				case u8: t = u8(n)
				case i16: t = i16(n)
				case u16: t = u16(n)
				case i32: t = i32(n)
				case u32: t = u32(n)
				case i64: t = i64(n)
				case u64: t = u64(n)
			}
		}

		case runtime.Type_Info_Array: 
		{
			/*if p.replace {
				for i in 0..<info.count {
					destroy_recursive(rawptr(uintptr(v.data) + uintptr(info.elem_size * i)), info.elem)
				}
			}*/
			// Expected column for identifiers
			p.indent += 1
			defer p.indent -= 1
			// Require separator?
			//require_separator := type_requires_separator(info.elem)
			// Stuff
			index: int
			// Loop until indent decreases
			for {
				p.token, err = expect_token_indent(p, {.Separator})
				// Handle indent errors
				if err == .Indent_Increased || err == .Indent_Decreased || err == Tokenize_Error.EOF {
					err = nil
					break
				} else if err != nil {
					return
				}
				parse(p, any{data = rawptr(uintptr(v.data) + uintptr(index * info.elem_size)), id = info.elem.id}) or_return
				index += 1
				if index == info.count {
					break
				}
			}
		}

		case runtime.Type_Info_Enumerated_Array: 
		{
			/*if p.replace {
				for i in 0..<info.count {
					destroy_recursive(rawptr(uintptr(v.data) + uintptr(info.elem_size * i)), info.elem)
				}
			}*/
			enum_info := runtime.type_info_base(info.index).variant.(runtime.Type_Info_Enum)
			names_parsed := make([]bool, len(enum_info.names))
			// Expected column for identifiers
			p.indent += 1
			defer p.indent -= 1
			// Require separator?
			require_separator := type_requires_separator(info.elem)
			// Stuff
			index: int
			// Loop until indent decreases
			for {
				p.token, err = expect_token_indent(p, {.Identifier})
				// Handle indent errors
				if err == .Indent_Increased || err == .Indent_Decreased || err == Tokenize_Error.EOF {
					err = nil
					break
				} else if err != nil {
					return
				}
				for &name, i in enum_info.names {
					if !names_parsed[i] && name == p.token.text {
						names_parsed[i] = true 
						parse(p, any{data = rawptr(uintptr(v.data) + uintptr(i * info.elem_size)), id = info.elem.id}) or_return
						break
					}
				}
			}
		}

		case runtime.Type_Info_Dynamic_Array: 
		{
			/*if p.replace {
				raw_array := transmute(^runtime.Raw_Dynamic_Array)v.data
				for i in 0..<raw_array.len {
					destroy_recursive(rawptr(uintptr(raw_array.data) + uintptr(i * info.elem_size)), info.elem)
				}
			}*/
			// Expected column for identifiers
			p.indent += 1
			defer p.indent -= 1
			// Loop until indent decreases
			for {
				p.token, err = expect_token_indent(p, {.Separator})
				// Handle indent errors
				if err == .Indent_Increased || err == .Indent_Decreased || err == Tokenize_Error.EOF {
					err = nil
					break
				} else if err != nil {
					return
				}
				item_data, _ := mem.alloc(info.elem.size)
				defer mem.free(item_data)
				parse(p, any{data = item_data, id = info.elem.id}) or_return
				runtime.__dynamic_array_append(v.data, info.elem_size, info.elem.align, item_data, 1)
			}
		}

		/*
			Parsing of maps should allow for simpler notation if the key is a type that can be represented
			on one line
		*/
		case runtime.Type_Info_Map:
		{
			// Get raw map
			raw_map := transmute(^runtime.Raw_Map)v.data
			// Replacement
			/*if p.replace {
				ks, vs, hs, _, _ := runtime.map_kvh_data_dynamic(raw_map^, info.map_info)
				for it := 0; it < int(runtime.map_cap(raw_map^)); it += 1 {
					if hash := hs[it]; runtime.map_hash_is_valid(hash) {
						key   := runtime.map_cell_index_dynamic(ks, info.map_info.ks, uintptr(it))
						value := runtime.map_cell_index_dynamic(vs, info.map_info.vs, uintptr(it))
						destroy_recursive(rawptr(key), info.key)
						destroy_recursive(rawptr(value), info.value)
					}
				}
			}*/
			// Expected column for identifiers
			p.indent += 1
			defer p.indent -= 1
			#partial switch key_info in info.key.variant {
				case runtime.Type_Info_Struct, runtime.Type_Info_Array, runtime.Type_Info_Enumerated_Array: 
				// Loop until indent decreases
				for {
					p.token, err = expect_token_indent(p, {.Separator})
					// Handle indent errors
					if err == .Indent_Increased || err == .Indent_Decreased || err == Tokenize_Error.EOF {
						err = nil
						break
					} else if err != nil {
						return
					}
					p.indent += 1
					// Key
					p.token = expect_token_indent(p, {.Identifier}) or_return
					if p.token.text == "key" {
						key_data, _ := mem.alloc(info.key.size)
						defer mem.free(key_data)
						parse(p, any{data = key_data, id = info.key.id}) or_return 
						// Value
						p.token = expect_token_indent(p, {.Identifier}) or_return
						if p.token.text == "value" {
							value_data, _ := mem.alloc(info.value.size)
							defer mem.free(value_data)
							parse(p, any{data = value_data, id = info.value.id}) or_return 
							// Insert new pair
							runtime.__dynamic_map_set_without_hash(raw_map, info.map_info, key_data, value_data)
						}
					}
				}
				case runtime.Type_Info_Map:
				panic("Will not parse a map as a map key")
				/*
					Case for simple notation

						"key" "value"
				*/
				case: 
				p.ignore_unexpected = true
				defer p.ignore_unexpected = false
				for {
					// Parse the key
					key_data, _ := mem.alloc(info.key.size)
					defer mem.free(key_data)
					if key_err := parse(p, any{data = key_data, id = info.key.id}); key_err != nil {
						if key_err != .Unexpected_Token && key_err != Tokenize_Error.EOF {
							err = key_err
						}
						return
					}
					// Parse the Value
					value_data, _ := mem.alloc(info.value.size)
					defer mem.free(value_data)
					if value_err := parse(p, any{data = value_data, id = info.value.id}); value_err != nil {
						if value_err != .Unexpected_Token && value_err != Tokenize_Error.EOF {
							err = value_err
						}
						return
					}
					// Insert new pair
					runtime.__dynamic_map_set_without_hash(raw_map, info.map_info, key_data, value_data)
				}
			}
		}

		case runtime.Type_Info_Struct:
		// Expected column for identifiers
		p.indent += 1
		defer p.indent -= 1
		// Loop until indent decreases
		for {
			p.token, err = expect_token_indent(p, {.Identifier})
			// Handle indent errors
			if err != nil {
				switch err {
					// Ignore these errors
					case .Indent_Decreased, .Indent_Increased, Tokenize_Error.EOF:
					err = nil 
					case: break
				}
				return
			}
			// Find field
			found := false
			struct_loop: for name, i in info.names {
				if name == p.token.text {
					parse(p, any{data = rawptr(uintptr(v.data) + info.offsets[i]), id = info.types[i].id}) or_return
					found = true
					break
				} else if info.usings[i] {
					// Search for matching fields in used structs
					if using_info, ok := info.types[i].variant.(runtime.Type_Info_Struct); ok {
						for using_name, j in using_info.names {
							if using_name == p.token.text {
								parse(p, any{data = rawptr(uintptr(v.data) + info.offsets[i]), id = info.types[i].id}) or_return
								found = true
								break struct_loop
							}
						}
					}
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
		/*if p.replace {
			delete((transmute(^string)v.data)^)
		}*/
		(transmute(^string)v.data)^ = p.token.text

		case runtime.Type_Info_Boolean: 
		p.token = expect_literal(p, {.True, .False}) or_return
		switch &b in v {
			case bool: b = true if p.token.kind == .True else false
			case b8: b = true if p.token.kind == .True else false
			case b16: b = true if p.token.kind == .True else false
			case b32: b = true if p.token.kind == .True else false
			case b64: b = true if p.token.kind == .True else false
		}

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

		/*
			Allow parsing by enum value name or by integer value
		*/
		case runtime.Type_Info_Enum:
		p.token = expect_literal(p, {.Identifier, .Integer}) or_return
		#partial switch p.token.kind {
			case .Identifier:
			found := false
			for name, i in info.names {
				if name == p.token.text {
					mem.copy(v.data, &info.values[i], info.base.size)
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
			mem.copy(v.data, &info.values[strconv.parse_i64(p.token.text) or_else 0], info.base.size)
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
	for {
		token = next_token(&p.t) or_return
		if token.kind != .Comment {
			break
		}
	}
	return
}

expect_literal :: proc(p: ^Parser, kinds: Token_Kind_Set) -> (token: Token, err: Error) {
	loc := p.last_token.loc
	token = expect_token(p, kinds) or_return
	// Expect the token to be either directly after the last or on the next line with increased indent
	if token.line > loc.line && token.column == loc.column {
		err = .Literal_Not_Found
	}
	return
}

expect_token_indent :: proc(p: ^Parser, kinds: Token_Kind_Set) -> (token: Token, err: Error) {
	// Skip comments and get next token
	token, err = skip_comments(p)
	// EOF is not necessarily an error
	if err == Tokenize_Error.EOF {
		return
	}
	if token.kind == .Invalid {
		err = .Invalid_Token
	} else {
		// Check if indentation matches
		token_indent := token.column
		if token.line > p.last_token.line && token_indent != p.indent {
			p.t.next_token = token
			// Return what happened
			if token_indent > p.indent {
				err = .Indent_Increased
				fmt.printf("\033[1m[%i:%i] Unexpected indentation\033[0m\n", token.line, token.column)
				print_loc_helper(p.t.data, token.loc, token.width)
			} else {
				err = .Indent_Decreased
			}
			return
		}
		if kinds != {} && token.kind not_in kinds {
			// Print useful error messages
			err = .Unexpected_Token
			fmt.printf("\033[1m[%i:%i] Expected one of %v, but got %v\033[0m\n", token.line, token.column, kinds, token.kind)
			print_loc_helper(p.t.data, token.loc, token.width)
		}
	}
	p.last_token = token
	return
}

expect_token :: proc(p: ^Parser, kinds: Token_Kind_Set) -> (token: Token, err: Error) {
	// Skip comments and get next token
	token, err = skip_comments(p)
	// EOF is not necessarily an error
	if err == Tokenize_Error.EOF {
		return
	}
	if token.kind == .Invalid {
		err = .Invalid_Token
	} else if kinds != {} && token.kind not_in kinds {
		err = .Unexpected_Token
		if p.ignore_unexpected {
			p.t.next_token = token
		} else {
			// Print useful error messages
			fmt.printf("\033[1m[%i:%i] Expected one of %v, but got %v\033[0m\n", token.line, token.column, kinds, token.kind)
			print_loc_helper(p.t.data, token.loc, token.width)
		}
	}
	p.last_token = token
	return
}

unquote_string :: proc(token: Token) -> (value: string, err: Error) {
	get_u2_rune :: proc(s: string) -> rune {
		if len(s) < 4 || s[0] != '\\' || s[1] != 'x' {
			return -1
		}

		r: rune
		for c in s[2:4] {
			x: rune
			switch c {
			case '0'..='9': x = c - '0'
			case 'a'..='f': x = c - 'a' + 10
			case 'A'..='F': x = c - 'A' + 10
			case: return -1
			}
			r = r*16 + x
		}
		return r
	}
	get_u4_rune :: proc(s: string) -> rune {
		if len(s) < 6 || s[0] != '\\' || s[1] != 'u' {
			return -1
		}

		r: rune
		for c in s[2:6] {
			x: rune
			switch c {
			case '0'..='9': x = c - '0'
			case 'a'..='f': x = c - 'a' + 10
			case 'A'..='F': x = c - 'A' + 10
			case: return -1
			}
			r = r*16 + x
		}
		return r
	}

	if token.kind != .String {
		return "", nil
	}
	s := token.text
	if len(s) <= 2 {
		return "", nil
	}
	quote := s[0]
	if s[0] != s[len(s)-1] {
		// Invalid string
		return "", nil
	}
	s = s[1:len(s)-1]

	i := 0
	for i < len(s) {
		c := s[i]
		if c == '\\' || c == quote || c < ' ' {
			break
		}
		if c < utf8.RUNE_SELF {
			i += 1
			continue
		}
		r, w := utf8.decode_rune_in_string(s)
		if r == utf8.RUNE_ERROR && w == 1 {
			break
		}
		i += w
	}
	if i == len(s) {
		return strings.clone(s), nil
	}

	b := mem.alloc_bytes(len(s) + 2*utf8.UTF_MAX, 1) or_return
	w := copy(b, s[0:i])

	/*if len(b) == 0 && allocator.data == nil {
		// `unmarshal_count_array` calls us with a nil allocator
		return string(b[:w]), nil
	}*/

	loop: for i < len(s) {
		c := s[i]
		switch {
		case c == '\\':
			i += 1
			if i >= len(s) {
				break loop
			}
			switch s[i] {
			case: break loop
			case '"',  '\'', '\\', '/':
				b[w] = s[i]
				i += 1
				w += 1

			case 'b':
				b[w] = '\b'
				i += 1
				w += 1
			case 'f':
				b[w] = '\f'
				i += 1
				w += 1
			case 'r':
				b[w] = '\r'
				i += 1
				w += 1
			case 't':
				b[w] = '\t'
				i += 1
				w += 1
			case 'n':
				b[w] = '\n'
				i += 1
				w += 1
			case 'u':
				i -= 1 // Include the \u in the check for sanity sake
				r := get_u4_rune(s[i:])
				if r < 0 {
					break loop
				}
				i += 6

				buf, buf_width := utf8.encode_rune(r)
				copy(b[w:], buf[:buf_width])
				w += buf_width


			case '0':
				b[w] = '\x00'
				i += 1
				w += 1
			case 'v':
				b[w] = '\v'
				i += 1
				w += 1

			case 'x':
				i -= 1 // Include the \x in the check for sanity sake
				r := get_u2_rune(s[i:])
				if r < 0 {
					break loop
				}
				i += 4

				buf, buf_width := utf8.encode_rune(r)
				copy(b[w:], buf[:buf_width])
				w += buf_width
			}

		case c == quote, c < ' ':
			break loop

		case c < utf8.RUNE_SELF:
			b[w] = c
			i += 1
			w += 1

		case:
			r, width := utf8.decode_rune_in_string(s[i:])
			i += width

			buf, buf_width := utf8.encode_rune(r)
			assert(buf_width <= width)
			copy(b[w:], buf[:buf_width])
			w += buf_width
		}
	}

	return string(b[:w]), nil
}