package example

import "../"

import "core:os"
import "core:io"
import "core:fmt"
import "core:time"

Choice :: enum {
	First,
	Second,
	Third,
}

Choice_Set :: bit_set[Choice]

Thing :: struct {
	things: [dynamic]Other_Thing,
	choice: Choice,
	perhaps: Maybe(Other_Thing),
}
Other_Thing :: struct {
	name: string,
	age: int,
	value: Value,
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

	thing: Thing

	if data, ok := os.read_entire_file("in.sil"); ok {
		p: Parser = {
			t = {
				data = string(data[:]),
			},
		}

		t := time.now()
		if err := parse(&p, &thing); err != nil {
			fmt.println(err)
		}
		fmt.printf("Finished parsing in %fms\n", time.duration_milliseconds(time.since(t)))

		fmt.println(thing)
		if file, err := os.open("out.sil", os.O_CREATE | os.O_WRONLY | os.O_TRUNC); err == os.ERROR_NONE {
			c: Composer = {
				w = io.to_writer(os.stream_from_handle(file)),
			}
			compose(&c, thing)
		}
	}
}