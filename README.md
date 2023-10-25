# Simple Information Language

A data notation language to be composed and parsed directly to/from your datatypes.  It's designed to be easily read by both humans and computers, structured by indentation.

Given:

```odin
Item :: struct {
	hash: u32,
	description: string,
	previous, next: u32,
}
```

```
item := Item{
	hash = 555,
	description = "An item in a linked list",
}
```

would be composed to:

```
hash 555
description "An item in a linked list"
```