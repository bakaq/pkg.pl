:- use_module(pkg).
:- use_module(pkg(test)).
:- use_module(pkg(test_branch)).
:- use_module(pkg(test_tag)).
:- use_module(pkg(test_hash)).
:- use_module(pkg(test_local)).
:- use_module('../util_packages/scryer_libs/packages/testing/testing.pl').
:- use_module('../util_packages/assert.pl').

main :-
    run_tests.

test("test if the git dependency work", (main_code(exist))).
test("test if the branch dependency works", (tag(exist))).
test("test if the tag dependency works", (branch(exist))).
test("test if the hash dependency works", (hash(exist))).
test("test if the local dependency works", (local(exist))).
