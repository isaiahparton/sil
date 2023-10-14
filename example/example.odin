package example

import son "../"

import "core:os"
import "core:io"
import "core:fmt"

Actor :: struct {
	point: [2]f32,
	flags: bit_set[0..<8],
	name: string `# Hi! I'm a comment`,
}

Thing :: struct {
	number: int,
	name: string,
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
	using son 

	pool: map[Key]Value

	thing: Thing

	if data, ok := os.read_entire_file("example.sml"); ok {
		p: Parser = {
			t = {
				data = string(data[:]),
			},
		}

		if err := parse(&p, &thing); err != nil {
			fmt.println(err)
		}

		fmt.println(thing)
	}
}