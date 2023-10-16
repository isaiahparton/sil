package sil

import "core:io"

/*
	Simple Information Language
*/

PLACEHOLDER_RUNE :: '-'
VALUE_SEPARATOR_RUNE :: ' '
INDENT_RUNE :: ' '

General_Error :: enum {
	Unsupported_Type,
	Invalid_Character,
	Invalid_Number,
	Unexpected_Token,
	Not_Found,
	EOF,
}

Error :: union {
	io.Error,
	General_Error,
}

Location :: struct {
	offset,
	line, 
	column: int,
}