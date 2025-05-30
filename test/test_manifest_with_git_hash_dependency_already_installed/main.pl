:- use_module(pkg).
:- use_module('../util_packages/scryer_libs/packages/testing/testing.pl').

main :-
    pkg_install(_),
    run_tests.

test("the package report is valid", (
        pkg_install(X),
        X == [
        do_nothing(dependency("test", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git", hash("d19fefc1d7907f6675e181601bb9b8b94561b441"))))-success
        ]
    )
).