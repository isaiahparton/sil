# Simple Information Language

A data notation language to be composed and parsed directly to/from your datatypes
Minimal for simplicity and speed when dealing with large file

Here is an array of structs
'-' is a generic element separator

-
	text "forthwith"
	hash 8591223410052
-
	text "heretofor"
	hash 9480212407
-
	text "without"
	hash 14015220251

Here is a map of positions to a string
';' is a generic field separator (here the key comes before the value)

-
	; 25 77
	; "The Town"
-
	; 82 10
	; "The Lich's Cave"