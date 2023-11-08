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

Tokenize_Error :: enum {
	EOF,
}
/*
	Parsing!
*/
Token_Kind :: enum {
	Invalid,
	Comment,
	True,
	False,
	Nil,
	String,
	Integer,
	Real,
	Separator,
	Identifier,
}
Token_Kind_Set :: bit_set[Token_Kind]
Token :: struct {
	// Location in the source file
	using loc: Location,
	// Kind of token
	kind: Token_Kind,
	// Contained unquoted data
	text: string,
	// The token's width in the source file
	width: int,
}
Tokenizer :: struct {
	loc,
	last_loc: Location,

	next_token: Maybe(Token),

	data: string,

	lr,
	r: rune,
	w: int,
}

next_rune :: proc(t: ^Tokenizer) -> rune {
	t.last_loc = t.loc
	if t.r == '\n' {
		t.loc.column = 1
		t.loc.line += 1
	} else if t.r != '\r' {
		t.loc.column += 1
	}
	t.loc.offset += t.w 
	t.lr = t.r
	t.r, t.w = utf8.decode_rune(t.data[t.loc.offset:])
	if t.loc.offset >= len(t.data) {
		t.r = utf8.RUNE_EOF
	}
	return t.r
}

skip_rune :: proc(t: ^Tokenizer) {
	t.loc.offset += t.w
}

next_token :: proc(t: ^Tokenizer) -> (token: Token, err: Error) {
	if t.next_token != nil {
		token = t.next_token.?
		t.next_token = nil
		return
	} 

	if t.loc.line == 0 {
		t.loc.line = 1
	}

	skip_whitespace :: proc(t: ^Tokenizer) -> rune {
		for {
			next_rune(t)
			switch t.r {
				case ' ', '\t', '\v', '\r', '\f', '\n':
				continue
			}
			break
		}
		return t.r
	}

	skip_whitespace(t)
	token.loc = t.loc

	switch t.r {
		case utf8.RUNE_EOF: 
		err = Tokenize_Error.EOF 
		return

		case '#':
		token.kind = .Comment 
		cycle: for {
			switch next_rune(t) {
				case '\r', '\n', utf8.RUNE_EOF:
				break cycle
			}
		}
		token.text = t.data[token.offset:t.loc.offset]

		case SEPARATOR_RUNE:
		token.kind = .Separator
		token.text = t.data[token.offset:t.loc.offset + 1]

		case 'a'..='z', 'A'..='Z', '0'..='9', '_', '-':
		token.kind = .Integer
		loop: for {
			switch next_rune(t) {
				case '.':
				if token.kind == .Integer {
					token.kind = .Real
				} else if token.kind == .Real {
					token.kind = .Invalid
				}
				case 'a'..='z', 'A'..='Z', '_':
				token.kind = .Identifier
				case '\r', '\n', ' ', utf8.RUNE_EOF:
				break loop
			}
		}
		token.text = t.data[token.offset:t.loc.offset]
		if token.kind == .Identifier {
			switch token.text {
				case "true": token.kind = .True
				case "false": token.kind = .False
				case "nil": token.kind = .Nil
			}
		}

		case '"': 
		token.kind = .String
		b: strings.Builder
		string_loop: for {
			next_rune(t)
			if t.r == utf8.RUNE_EOF || t.r == '\n' {
				fmt.printf("\033[1m[%i:%i] Open ended string!\033[0m\n", t.loc.line, t.loc.column)
				print_loc_helper(t.data, t.last_loc, 1)
				token.kind = .Invalid
				break
			} else if t.lr == '\\' {
				switch t.r {
					case '\\': 	
					strings.write_rune(&b, '\\')
					t.r = 0
					case '"': 	strings.write_rune(&b, '"')
					case 'n': 	strings.write_rune(&b, '\n')
					case 'r': 	strings.write_rune(&b, '\r')
					case 't': 	strings.write_rune(&b, '\t')
					case '0': 	strings.write_rune(&b, 0x0)
					case: 
					token.kind = .Invalid 
					break string_loop
				}
			} else if t.r == '"' {
				// fmt.printf("\033[1m[%i:%i] Embedded quotes must be escaped like this: \\\"\033[0m\n", t.loc.line, t.loc.column)
				// print_loc_helper(t.data, t.last_loc, 1)
				break string_loop
			} else if t.r != '\\' {
				strings.write_rune(&b, t.r)
			}
		}
		if token.kind == .String {
			token.text = strings.to_string(b)
		} else {
			strings.builder_destroy(&b)
		}

		case '\r':
		skip_rune(t)
	}

	if token.kind == .Separator {
		token.width = 1
	} else {
		token.width = t.loc.offset - token.offset
		if token.kind == .Invalid {
			fmt.printf("\033[1m[%i:%i] Invalid token\033[0m\n", token.line, token.column)
			print_loc_helper(t.data, token.loc, token.width)
		}
	}

	return
}

print_loc_helper :: proc(str: string, loc: Location, width: int) {
	i := loc.offset
	for ;; i -= 1 {
		if i == 0 {
			break
		} else if str[i - 1] == '\n' {
			break
		}
	}
	j := i
	for ;; j += 1 {
		if j == len(str) || str[j] == '\n' {
			break
		}
	}
	fmt.printf("\033[1m%s\n", str[i:j])
	for k in 0..<(loc.offset - i) {
		fmt.printf(" ")
	}

	fmt.print("\033[31m")

	for k in 0..<width {
		fmt.printf("~")
	}

	fmt.print("\033[0m")

	fmt.printf("\n")
}