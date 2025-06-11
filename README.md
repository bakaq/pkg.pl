# pkg.pl: An experimental package manager for Scryer Prolog

This project is intended to be a testing ground for how to do a package manager
for Scryer Prolog. This is still really rough (currently it has trivially
exploitable arbitrary remote code execution) and is not intended for general
use yet. If you want to contribute or have any ideas or questions feel free to
get in touch and create issues, pull requests and
[discussions](https://github.com/bakaq/pkg.pl/discussions).

## How to use

A package is a directory with a `scryer-manifest.pl`, the current schema is something like:

```prolog
name("name_of_the_package").
% Optional. The file that will be imported when this package is used.
main_file("main.pl").
% Optional
dependencies([
    % A git url to clone
    dependency("testing", git("https://github.com/bakaq/testing.pl.git")),
    % A git url to clone at a specific branch
    dependency("test_branch", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git", branch("branch"))),
    % A git url to clone at a tag
    dependency("test_tag", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git", tag("tag"))),
    % A git url to clone at a specific commit hash
    dependency("test_hash", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git", hash("d19fefc1d7907f6675e181601bb9b8b94561b441"))),
    % A path to a local package
    dependency("test_local", path("./local_package"))
]).

```

Copy the `pkg.pl` file into your project. It is both the dependency manager and
the package loader. Use `scryer-prolog pkg.pl -g "pkg_install(X),halt."` to download
the dependencies to a `scryer_libs` directory (it doesn't handle transitive
dependencies yet). You can then import packages in your code as follows:

```prolog
% Loads the package loader
:- use_module(pkg).

% Loads a package. The argument should be an atom equal to the name of the
% dependency package specified in the `name/1` field of its manifest.
:- use_module(pkg(testing)).

% You can then use the predicates exported by the main file of the dependency
% in the rest of the program.

main :-
    % `run_tests/0` is exported by `pkg(testing)`
    run_tests,
    halt.

test("Example test", (true)).
test("Another test", (false)).
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
