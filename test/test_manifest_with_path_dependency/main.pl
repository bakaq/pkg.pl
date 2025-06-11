:- use_module(pkg).
:- use_module('../util_packages/scryer_libs/packages/testing/testing.pl').
:- use_module('../util_packages/assert.pl').
:- use_module(library(pio)).
:- use_module(library(format)).

main :-
    run_tests.

test("the package report is valid", (
        pkg_install(X),
        Expected = [
            validate_dependency(dependency("test", path("./local_package")))-success,
            install_dependency(dependency("test", path("./local_package")))-success
        ],
        test_eq(X, Expected)
    )
).