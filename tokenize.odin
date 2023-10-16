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

	data: string,

	got_indent: bool,
	in_quotes: bool,
	is_numeric: bool,

	lr,
	r: rune,
	w: int,
}

skip_whitespace :: proc(t: ^Tokenizer) {
	for {
		switch next_rune(t) {
			case ' ', '\t':
			if !t.got_indent {
			}
			continue
		}
		break
	}
}

next_rune :: proc(t: ^Tokenizer) -> rune {
	t.loc.column += 1
	if t.r == '\n' {
		t.loc.column = 0
		t.loc.line += 1
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

is_valid_number :: proc(str: string) -> bool {
	saw_decimal: bool
	str := str
	if len(str) < 1 {
		return false
	}
	if str[0] == '-' || str[1] == '+' {
		str = str[1:]
	}
	for r, i in str {
		if !unicode.is_number(r) {
			if r == '.' {
				if saw_decimal {
					return false 
				} else {
					return true
				}
			} else {
				return false 
			}
		}
	}
	return true
}

next_token :: proc(t: ^Tokenizer) -> (token: Token, err: Error) {
	for {
		next_rune(t)

		if t.r == '"' && t.lr != '\\' {
			t.in_quotes = !t.in_quotes
		}

		r := t.r

		if t.loc.offset > t.last_loc.offset {
			if ((t.r == ' ' || t.r == '\n') && !t.in_quotes) || t.r == utf8.RUNE_EOF {
				// Return token
				token.text = t.data[t.last_loc.offset:t.loc.offset]
				token.kind = .Identifier

				token.width = t.loc.offset - t.last_loc.offset
				token.loc = t.last_loc

				//next_rune(t)
				t.last_loc = t.loc
				t.last_loc.offset += t.w
				// Parse token
				if t.is_numeric {
					token.kind = .Number
				} else {
					switch token.text {
						case "true": 		token.kind = .True
						case "false": 	token.kind = .False
						case "nil": 		token.kind = .Nil
						case: 
						if len(token.text) > 1 {
							if token.text[0] == '"' && token.text[len(token.text) - 1] == '"' {
								token.text = token.text[1:len(token.text) - 1]
								token.kind = .String 
							}
						}
					}
					t.is_numeric = true
				}
				fmt.println(token)
			}
		} else if t.r == ' ' || t.r == '\t' {
			//next_rune(t)
		}

		if !unicode.is_number(r) && r != '.' && r != ' ' {
			t.is_numeric = false
		}

		if token.width > 0 || r == utf8.RUNE_EOF {
			break
		}
	}
	return
}

expect_literal :: proc(t: ^Tokenizer, kind: Token_Kind) -> (token: Token, err: Error) {
	loc := t.loc
	token, err = expect_token(t, kind)
	if token.column <= loc.column || token.line < loc.line || token.line > loc.line + 1 {
		err = .Not_Found
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
		if j == len(str) - 1 || str[j] == '\n' {
			break
		}
	}
	fmt.printf("%s\n", str[i:j])
	for k in 0..<(loc.offset - i) {
		fmt.printf(" ")
	}
	for k in 0..<width {
		fmt.printf("~")
	}
	fmt.printf("\n")
}

expect_token :: proc(t: ^Tokenizer, kind: Token_Kind) -> (token: Token, err: Error) {
	token, err = next_token(t)
	if token.kind != kind {
		// Print useful error messages
		err = .Unexpected_Token
		if kind == .Identifier {
			if token.kind == .Identifier {
				if token.text == "-" {
					fmt.printf("[%i:%i] Expected an identifier, but got '-'\n", token.line, token.column)
					print_loc_helper(t.data, token.loc, token.width)
				}
			} else {
				fmt.printf("[%i:%i] Expected an identifier but got '%v'\n", token.line, token.column, token.kind)
				print_loc_helper(t.data, token.loc, token.width)
			}
		} else {
			fmt.printf("[%i:%i] Expected '%v' but got '%v'\n", token.line, token.column, kind, token.kind)
			print_loc_helper(t.data, token.loc, token.width)
		}
	}
	return
}