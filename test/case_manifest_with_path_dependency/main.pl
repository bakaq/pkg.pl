:- use_module(pkg).
:- use_module('../util_packages/scryer_libs/packages/testing/testing.pl').
:- use_module(library(os)).
:- use_module(library(pio)).

main :-
    shell("rm -rf scryer_libs && rm -f manifest-lock.pl"),
    (
        run_tests([halt(false)])->
            Code=0
        ;   Code=1
    ),
    shell("rm -rf scryer_libs && rm -f manifest-lock.pl"), 
    halt(Code).

test("the package report is valid", (
        pkg_install(X),
        X = [
        install_dependency(dependency("test", path("./local_package")))-success(true),
        lock(dependency("test", path("./local_package")))-success(true)
        ]
    )
).