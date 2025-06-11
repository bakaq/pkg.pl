:- use_module(pkg).
:- use_module('../util_packages/scryer_libs/packages/testing/testing.pl').
:- use_module('../util_packages/assert.pl').
:- use_module('../util_packages/assert.pl').
:- use_module(library(ordsets)).
:- use_module(library(pio)).
:- use_module(library(format)).

main :-
    run_tests.
  
test("the package report is valid", (
        pkg_install(X),
        list_to_ord_set([
            validate_dependency(dependency("test", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git|abc")))-error(_),
            validate_dependency(dependency("test_branch", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git", branch("branch;"))))-error(_),
            validate_dependency(dependency("test_tag", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git|", tag("tag|"))))-error(_),
            validate_dependency(dependency("test_hash", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git;", hash("d19fefc1d7907f6675e181601bb9b8b94561b441|def"))))-error(_),
            validate_dependency(dependency("test_local", path("./local_packa|ge")))-error(_)
            ], Expected),
        list_to_ord_set(X, X_Set),
        test_unify(X_Set, Expected)
    )
).