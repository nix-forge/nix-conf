BEGIN {
	FS = "="
}

FILENAME == ARGV[1] {
	key = $1
	keys[++count] = key
	values[key] = substr($0, length(key) + 2)
	next
}

index($0, "=") && $1 in values {
	if (! found[$1]++) {
		print $1 "=" values[$1]
	}
	next
}

{
	print
}

END {
	for (i = 1; i <= count; i++) {
		if (! found[keys[i]]) {
			print keys[i] "=" values[keys[i]]
		}
	}
}
