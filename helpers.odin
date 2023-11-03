package sil

import "core:io"
import "core:os"
import "core:strings"

parse_slice :: proc(data: []u8, v: any) -> (err: Error) {
	p: Parser = {
		t = {
			data = string(data[:]),
		},
	}
	return parse(&p, v)
}
parse_string :: proc(data: string, v: any) -> (err: Error) {
	p: Parser = {
		t = {
			data = data,
		},
	}
	return parse(&p, v)
}
compose_to_string :: proc(v: any) -> (str: string, err: Error) {
	b: strings.Builder
	c: Composer = {
		w = strings.to_writer(&b),
	}
	err = compose(&c, v)
	str = strings.to_string(b)
	return
}
compose_to_writer :: proc(w: io.Writer, v: any) -> (err: Error) {
	c: Composer = {
		w = w,
	}
	return compose(&c, v)
}
compose_to_file :: proc(file: string, v: any) -> (err: Error) {
	if file, err := os.open(file, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, 644); err == os.ERROR_NONE {
		compose_to_writer(io.to_writer(os.stream_from_handle(file)), v) or_return
		os.close(file)
	}
	return
}