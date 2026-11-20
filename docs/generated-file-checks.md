# Generated source validation

Generated source keeps its normal syntax, type and lint validation. Project-owned
generated-output assertion and runtime suites have been retired; there is no
`generated-checks` aggregate. See [testing](testing.md) for the library-only policy.

Bash writers use syntax checking and ShellCheck. Python quality uses compileall,
Ruff and ty. JavaScript and TypeScript use compiler checks and Oxlint. Lua,
PowerShell, Nushell and GTK CSS helpers keep language-specific static parsing
where their owning production build requires it. A parser's rejected input is a
normal validation failure, not a separate regression test.

Keep maintained source in language files. Render templates with the strict
helpers described in [Nix function conventions](nix-function-conventions.md).
Library tests cover pure substitution and escaping contracts; they do not run
application commands or compare an evaluated host with a chosen setting.

Package-local generated hook sources retain Bash/Python syntax checks in the
package repository. Upstream build tests and production input/runtime guards
remain enabled independently of the removed project-owned test suites.
