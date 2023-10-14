package monl

import "core:io"

/*
	Minimal Object Notation Language

	is an object notation and or markup language designed to be
	easily read by both humans and computers. it is structured
	with indentation. i like it.
*/

PLACEHOLDER_RUNE :: '-'
VALUE_SEPARATOR_RUNE :: ' '
INDENT_RUNE :: ' '

General_Error :: enum {
	Unsupported_Type,
	Invalid_Character,
	Unexpected_Token,
	Expected_Identifier,
	Expected_Value,
	EOF,
}

Error :: union {
	io.Error,
	General_Error,
}

Location :: struct {
	line, 
	column: int,
}