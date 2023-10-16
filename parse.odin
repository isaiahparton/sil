package sil

import "core:io"
import "core:os"
import "core:fmt"
import "core:math/bits"
import "core:strings"
import "core:strconv"
import "core:runtime"

import "core:unicode"
import "core:unicode/utf8"

Parser :: struct {
	t: Tokenizer,
}

parse :: proc(p: ^Parser, v: any) -> (err: Error) {
	// Get the pointer
	ti := runtime.type_info_base(type_info_of(v.id))

	#partial switch info in ti.variant {
		case runtime.Type_Info_Pointer:
		// Look where the pointer points and parse that
		return parse(p, any{data = (transmute(^rawptr)v.data)^, id = info.elem.id})

		case runtime.Type_Info_Struct:
		loc := p.t.loc
		loc.column += 1
		for {
			token := expect_token(&p.t, .Identifier) or_return
			if token.loc.column != loc.column {
				//break
			}
			// Find field
			found := false
			for name, i in info.names {
				if name == token.text {
					parse(p, any{data = rawptr(uintptr(v.data) + info.offsets[i]), id = info.types[i].id}) or_return
					found = true
					break
				}
			}
			if !found {
				break
			}
		}

		case runtime.Type_Info_String: 
		tok := expect_literal(&p.t, .String) or_return 
		(transmute(^string)v.data)^ = strings.clone(tok.text)

		case runtime.Type_Info_Boolean: 
		tok := expect_literal(&p.t, .True) or_else expect_literal(&p.t, .False) or_return
		(transmute(^bool)v.data)^ = true if tok.kind == .True else false

		case runtime.Type_Info_Integer, runtime.Type_Info_Float: 
		tok := expect_literal(&p.t, .Number) or_return
		switch &i in v {
			case int: i = strconv.parse_int(tok.text) or_else 0
			case i64: i = strconv.parse_i64(tok.text) or_else 0
			case f64: i = strconv.parse_f64(tok.text) or_else 0
			case f32: i = f32(strconv.parse_f64(tok.text) or_else 0)
		}
	}
	return
}