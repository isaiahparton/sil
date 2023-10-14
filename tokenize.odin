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

/*
	Parsing!
*/
Token_Kind :: enum {
	True,
	False,
	Nil,
	String,
	Number,

	Identifier,
}
Token :: struct {
	using loc: Location,
	width: int,
	kind: Token_Kind,
	text: string,
}
Tokenizer :: struct {
	loc: Location,
	data: string,

	last_indent,
	indent: int,

	last_offset,
	offset: int,

	is_token: bool,
	is_numeric: bool,

	r: rune,
	w: int,
}

next_rune :: proc(t: ^Tokenizer) -> rune {
	t.offset += t.w 
	t.r, t.w = utf8.decode_rune(t.data[t.offset:])
	if t.offset >= len(t.data) {
		t.r = utf8.RUNE_EOF
	}
	return t.r
}

tokenize :: proc(t: ^Tokenizer) -> (token: Token, err: Error) {
	for {
		r, w := utf8.decode_rune(t.data[t.offset:])
		if w <= 0 {
			return
		}

		if !unicode.is_number(r) && r != '.' {
			t.is_numeric = false
		}

		if r == ' ' || r == '\t' {
			t.indent += 1
		}
		if r == ' ' || r == '\n' {
			// Return token
			token.text = t.data[t.last_offset:t.offset]
			token.kind = .Identifier
			token.width = t.offset - t.last_offset

			token.loc = t.loc
			token.column -= token.width
				fmt.println(token.text)

			t.last_offset = t.offset + w
			// Parse token
			if t.is_numeric {
				token.kind = .Number
			} else {
				switch token.text {
					case "true": token.kind = .True
					case "false": token.kind = .False
					case "nil": token.kind = .Nil
					case: 
					if len(token.text) > 1 {
						if token.text[0] == '"' && token.text[len(token.text) - 1] == '"' {
							token.text = token.text[1:len(token.text) - 1]
							token.kind = .String 
						}
					}
				}
			}
			// Reset indent
			t.last_indent = t.indent
			t.indent = 0
			t.is_numeric = true
		}
		if r == '\n' {
			// New line
			t.loc.line += 1 
			t.loc.column = 0
		}

		t.offset += w
		t.loc.column += 1

		if token.width > 0 {
			break
		}
	}
	return
}

expect_token :: proc(t: ^Tokenizer, kind: Token_Kind) -> (token: Token, err: Error) {
	token, err = tokenize(t)
	if token.kind != kind {
		err = .Unexpected_Token
		fmt.printf("Expected '%v' but got '%v'\n", kind, token.kind)
	}
	return
}