:- use_module(pkg).
:- use_module('../util_packages/scryer_libs/packages/testing/testing.pl').

main :-
    run_tests.

test("test if no dependencies are installed", (pkg_install(X), X == [])).
