#if !defined(_FORTIFY_SOURCE) || _FORTIFY_SOURCE != 2
#error Clang importer is missing the fortify setting
#endif
#if !defined(__SSP_STRONG__) || __SSP_STRONG__ != 2
#error Clang importer is missing strong stack protection
#endif
static inline int hardening_probe(void) { return 42; }
