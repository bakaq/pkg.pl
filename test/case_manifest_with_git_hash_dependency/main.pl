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
        install_dependency(dependency("test", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git", hash("d19fefc1d7907f6675e181601bb9b8b94561b441"))))-success(true),
        lock(dependency("test", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git", hash("d19fefc1d7907f6675e181601bb9b8b94561b441"))))-success(true)
        ]
    )
).