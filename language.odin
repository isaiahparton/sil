package sil

import "core:io"
import "core:strings"

/*
	Simple Information Language
*/

PLACEHOLDER_RUNE :: '-'
VALUE_SEPARATOR_RUNE :: ' '
INDENT_RUNE :: ' '

General_Error :: enum {
	Invalid_Token,
	Unsupported_Type,
	Invalid_Character,
	Unexpected_Token,
}

Error :: union {
	io.Error,
	General_Error,
	Parse_Error,
	Tokenize_Error,
}

Location :: struct {
	offset,
	line, 
	column: int,
}