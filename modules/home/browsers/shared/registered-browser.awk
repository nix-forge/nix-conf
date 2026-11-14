BEGIN {
	app_path_re = app_path
	gsub(/[][\\.^$*+?(){}|]/, "\\\\&", app_path_re)
}

$0 ~ /^-+$/ {
	if (block != "" && found) {
		printf "%s", block
		block = ""
		exit
	}
	block = $0 ORS
	found = 0
	next
}

{
	block = block $0 ORS
	if ($0 ~ ("path:[[:space:]]+" app_path_re " \\(")) {
		found = 1
	}
}

END {
	if (block != "" && found) {
		printf "%s", block
	}
}
