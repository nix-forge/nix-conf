# Both choices must survive parsing; Nu 0.115 silently dropped the second value.
if (nu-complete --log-file-mode) != ["w", "a"] { error make {msg: "log-file-mode choices differ"} }
if (nu-complete --assert) != ["plain", "rewrite"] { error make {msg: "assert choices differ"} }
