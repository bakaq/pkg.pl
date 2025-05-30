:- use_module(pkg).
:- use_module('../util_packages/scryer_libs/packages/testing/testing.pl').

main :-
    pkg_install(_),
    run_tests.

test("the package report is valid", (
        pkg_install(X),
        X == [
        do_nothing(dependency("test", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git")))-success
        ]
    )
).