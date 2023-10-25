package example

import "../"

import "core:os"
import "core:io"
import "core:fmt"

Actor :: struct {
	point: [2]f32,
	flags: bit_set[0..<8],
	name: string `# Hi! I'm a comment`,
}

Choice :: enum {
	First,
	Second,
	Third,
}

Choice_Set :: bit_set[Choice]

Thing :: struct {
	number: f64,
	name: string,
	boolean: bool,
	choice: Choice,
	choices: Choice_Set,
	options: struct{mode: int, speed: f64},
}

Value :: union {
	string,
	i64,
	f64,
	bool,
}

Key :: struct {
	x,
	y: u32,
}

main :: proc() {
	using sil 

	pool: map[Key]Value

	thing: Thing

	if data, ok := os.read_entire_file("in.sil"); ok {
		p: Parser = {
			t = {
				data = string(data[:]),
			},
		}
		if err := parse(&p, &thing); err != nil {
			fmt.println(err)
		}
		fmt.println(thing)
		if file, err := os.open("out.sil", os.O_CREATE | os.O_WRONLY); err == os.ERROR_NONE {
			c: Composer = {
				w = io.to_writer(os.stream_from_handle(file))
			}
			compose(&c, thing)
		}
	}
}