package sil

import "core:io"
import "core:mem"
import "core:strings"
import "core:runtime"

/*
	Simple Information Language
*/
SEPARATOR_RUNE :: ';'

General_Error :: enum {
	Invalid_Token,
	Unsupported_Type,
	Invalid_Character,
	Unexpected_Token,
}

Error :: union {
	io.Error,
	mem.Allocator_Error,
	General_Error,
	Parse_Error,
	Tokenize_Error,
}

Location :: struct {
	offset,
	line, 
	column: int,
}

type_requires_separator :: proc(ti: ^runtime.Type_Info) -> bool {
	#partial switch v in ti.variant {
		case runtime.Type_Info_Array, runtime.Type_Info_Dynamic_Array, runtime.Type_Info_Slice, runtime.Type_Info_Enumerated_Array, runtime.Type_Info_Map, runtime.Type_Info_Struct:
		return true 
		case: 
		return false
	}
	return false
}