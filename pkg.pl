/* SPDX-License-Identifier: Unlicense */

:- module(pkg, [pkg_install/1]).

:- use_module(library(os)).
:- use_module(library(pio)).
:- use_module(library(files)).
:- use_module(library(lists)).
:- use_module(library(charsio)).
:- use_module(library(format)).
:- use_module(library(debug)).

% Cleanly pass arguments to a script through environment variables

run_script_with_args(ScriptName, Args, Success) :-
    maplist(define_script_arg, Args),
    append(["sh scryer_libs/scripts/", ScriptName, ".sh"], Script),
    (
        shell(Script) ->
            Success = true
        ;   Success = false
    ),
    maplist(undefine_script_arg, Args).

run_script_with_args(ScriptName, Args, Result_Filename, Result, Success) :-
    run_script_with_args(ScriptName, Args, Success),
    ( 
        Success == true -> 
            result_from_file(Result_Filename, Result)
        ;   Result = failure
    ).

result_from_file(Result_Filename, Result) :-
    open(Result_Filename, read, Stream),
    read(Stream, result(Result)),
    close(Stream),
    delete_file(Result_Filename).

define_script_arg(Arg-Value) :- setenv(Arg, Value).
undefine_script_arg(Arg-_) :- unsetenv(Arg).

scryer_path(ScryerPath) :-
    (   getenv("SCRYER_PATH", ScryerPath) ->
        true
    ;   ScryerPath = "scryer_libs"
    ).

parse_manifest(Filename, Manifest) :-
    open(Filename, read, Stream),
    parse_manifest_(Stream, Manifest),
    close(Stream).

parse_manifest_(Stream, Manifest) :-
    read(Stream, Term),
    (   Term == end_of_file ->
        Manifest = []
    ;   Manifest = [Term|Ms],
        parse_manifest_(Stream, Ms)
    ).

user:term_expansion((:- use_module(pkg(Package))), (:- use_module(PackageMainFile))) :-
    atom_chars(Package, PackageChars),
    scryer_path(ScryerPath),
    append([ScryerPath, "/packages/", PackageChars], PackagePath),
    append([PackagePath, "/", "scryer-manifest.pl"], ManifestPath),
    parse_manifest(ManifestPath, Manifest),
    member(main_file(MainFile), Manifest),
    append([PackagePath, "/", MainFile], PackageMainFileChars),
    atom_chars(PackageMainFile, PackageMainFileChars).

% This creates the directory structure we want
ensure_scryer_libs :-
    (   directory_exists("scryer_libs") ->
        true
    ;   make_directory_path("scryer_libs")
    ),
    (   directory_exists("scryer_libs/packages") ->
        true
    ;   make_directory_path("scryer_libs/packages")
    ),
    (   directory_exists("scryer_libs/scripts") ->
        true
    ;   make_directory_path("scryer_libs/scripts"),
        ensure_scripts
    ),
    (   directory_exists("scryer_libs/temp") ->
        true
    ;   make_directory_path("scryer_libs/temp")
    ).

% Installs helper scripts
ensure_scripts :-
    findall(ScriptName-ScriptString, script_string(ScriptName, ScriptString), Scripts),
    maplist(ensure_script, Scripts).

ensure_script(Name-String) :-
    append(["scryer_libs/scripts/", Name, ".sh"], Path),
    phrase_to_file(String, Path).

pkg_install(Results) :-
    parse_manifest("scryer-manifest.pl", Manifest),
    ensure_scryer_libs,
    setenv("SHELL", "/bin/sh"),
    setenv("GIT_ADVICE", "0"),
    (   file_exists("manifest-lock.pl") ->
        parse_manifest("manifest-lock.pl", LockFile),
        member(lock_dependencies(LockDeps),LockFile)
    ;   LockDeps = []
    ),
    (   member(dependencies(Deps), Manifest) ->
        plan(logical_plan(IPlan, LPlan), Deps, LockDeps)
    ;   true
    ),
    installation_execution(IPlan, InstallResults),
    installation_steps_ended(IPlan),
    lock_execution(LPlan, LockTerms, LockResult),
    materialize_lock_file(LockTerms),
    append([InstallResults, LockResult], Results),
    delete_directory("scryer_libs/temp").

materialize_lock_file(LockTerms) :-
    open('manifest-lock.pl', write, Stream),
    write(Stream, '% WARNING: This file is auto-generated. Do NOT modify it manually.\n\n'),
    write_term(Stream, lock_dependencies(LockTerms), [double_quotes(true)]),
    write(Stream, '.\n'),
    close(Stream).

installation_execution([], []).
installation_execution([P|Ps], Results):-
    installation_execution(Ps, Result0),
    execution_step(P, Result),
    append([Result0, [Result]],Results).

lock_execution([], [], []).

lock_execution([P|Ps], LockTerms, Results):-
    lock_execution(Ps, LockTerms0, Results0),
    execution_lock_step(P, LockTerm, Result),
    append([Results0, [Result]],Results),
    (
        LockTerm == null ->
            true
        ;   append([LockTerms0, [LockTerm]], LockTerms)
    ).

installation_steps_ended([]).
installation_steps_ended([P|Ps]):-
    dependency_installed(P),
    installation_steps_ended(Ps).

dependency_installed(do_nothing(_)).

dependency_installed(install_locked_dependency(dependency(Name, _))):-
    dependency_installed(install_dependency(dependency(Name, _))).

dependency_installed(install_dependency(dependency(Name, _))) :-
    append(["scryer_libs/temp/parallel_lock_", Name], LockFileName),
    (
        file_exists(LockFileName)->
            delete_file(LockFileName)
        ; dependency_installed(install_dependency(dependency(Name, _)))
    ).

execution_step(do_nothing(dependency(Name, DependencyTerm)), do_nothing(dependency(Name, DependencyTerm))-success(true)) :-
    current_output(Out),
    phrase_to_stream(("Already installed: ", portray_clause_(dependency(Name, DependencyTerm))), Out).

execution_step(install_dependency(D), Result) :-
    ensure_dependency(D, Success),
    Result = install_dependency(D)-success(Success).

execution_step(install_locked_dependency(D), install_locked_dependency(D)-Success) :- 
    execution_step(install_dependency(D), _-Success).

execution_lock_step(lock(dependency(Name, git(Url,hash(Hash)))), dependency(Name, git(Url,hash(Hash)), IntegrityHash), lock(dependency(Name, git(Url,hash(Hash))))-success(Success)) :- 
    ensure_integrity_hash(dependency(Name, git(Url,hash(Hash))), IntegrityHash, Success),
    !.

execution_lock_step(lock(dependency(Name, path(Path))), dependency(Name, path(Path), IntegrityHash), lock(dependency(Name, path(Path)))-success(Success)) :-
    ensure_integrity_hash(dependency(Name, path(Path)), IntegrityHash, Success).

execution_lock_step(lock(dependency(Name, git(Url))), LockedDependency, Result) :-
    execution_lock_step(lock(dependency(Name, git(Url, none))), LockedDependency, Result).

execution_lock_step(lock(dependency(Name, git(Url, Opt))), LockedDependency, Result) :-
    ensure_lock(dependency(Name, git(Url, Opt)), Hash, Success_Lock),
    ensure_integrity_hash(dependency(Name, git(Url, Opt)), IntegrityHash, Success_Integrity),
    (
        (Success_Lock == Success_Integrity,  Success_Lock == true) ->
            LockedDependency = dependency(Name, git(Url, hash(Hash)), IntegrityHash),
            Success=true
        ;   
            LockedDependency = null,
            Success=false
    ),
    (
        Opt == none ->
            Result = lock(dependency(Name, git(Url)))-success(Success)
        ;   Result = lock(dependency(Name, git(Url, Opt)))-success(Success)
    ).


lock_dependency_with_name([dependency(Name, X, _)|_], dependency(Name, _), dependency(Name, X)) :- !.

lock_dependency_with_name([_|Ls], dependency(Name, _), Dep) :-
    lock_dependency_with_name(Ls, dependency(Name, _), Dep).

plan(logical_plan(IPlan, LPlan), Ds, LockDeps) :-
    installation_plan(IPlan, Ds, LockDeps),
    lock_plan(LPlan, Ds).

installation_plan([], [], _).

installation_plan(Plan, [D|Ds], LockDeps) :-
    installation_plan(Plan0, Ds, LockDeps),
    install_step(Installation_Step, D, LockDeps),
    append([Plan0, [Installation_Step]], Plan).

lock_plan([], []).

lock_plan(Plan, [D|Ds]):-
    lock_plan(Plan0, Ds),
    append([Plan0, [lock(D)]], Plan).


install_step(Installation_Step, dependency(Name, DependencyTerm), LockDeps):-
    append(["scryer_libs/packages/", Name], DepRepo),
    (
    directory_exists(DepRepo) ->
        Installation_Step = do_nothing(dependency(Name, DependencyTerm))
    ;   (
            lock_dependency_with_name(LockDeps, dependency(Name, DependencyTerm), D) ->
                Installation_Step = install_locked_dependency(D)
            ;   Installation_Step = install_dependency(dependency(Name, DependencyTerm))
        )
    ).

ensure_integrity_hash(dependency(Name, _), Hash, Success) :-
    append(["scryer_libs/temp/integrity_hash_", Name], Result_Filename),
    Arg = [
        "DEPENDENCY_NAME"-Name,
        "RESULT_FILE"-Result_Filename
    ],
    run_script_with_args("ensure_integrity_hash", Arg, Result_Filename, Hash, Success).

ensure_lock(dependency(Name, _), Hash, Success) :-
    append(["scryer_libs/temp/lock_dependency_", Name], Result_Filename),
    Arg = [
        "DEPENDENCY_NAME"-Name,
        "RESULT_FILE"-Result_Filename
    ],
    run_script_with_args("ensure_lock_dependency", Arg, Result_Filename, Hash, Success).

ensure_dependency(dependency(Name, DependencyTerm), Success) :-
    write_term_to_chars(DependencyTerm, [quoted(true), double_quotes(true)], DependencyTermChars),
    CommonArgs = [
        "DEPENDENCY_NAME"-Name,
        "DEPENDENCY_TERM"-DependencyTermChars
    ],
    ensure_dependency_extra_args(DependencyTerm, ExtraArgs),
    append(CommonArgs, ExtraArgs, Args),
    run_script_with_args("ensure_dependency", Args, Success).

ensure_dependency_extra_args(git(Url), [
    "DEPENDENCY_KIND"-"git_default",
    "GIT_URL"-Url
]).
ensure_dependency_extra_args(git(Url,branch(Branch)), [
    "DEPENDENCY_KIND"-"git_branch",
    "GIT_URL"-Url,
    "GIT_BRANCH"-Branch
]).
ensure_dependency_extra_args(git(Url,tag(Tag)), [
    "DEPENDENCY_KIND"-"git_tag",
    "GIT_URL"-Url,
    "GIT_TAG"-Tag
]).
ensure_dependency_extra_args(git(Url,hash(Hash)), [
    "DEPENDENCY_KIND"-"git_hash",
    "GIT_URL"-Url,
    "GIT_HASH"-Hash
]).
ensure_dependency_extra_args(path(Path), [
    "DEPENDENCY_KIND"-"path",
    "DEPENDENCY_PATH"-Path
]).

% === Generated code start ===
script_string("ensure_dependency", "#!/bin/sh\nset -eu\n\necho \"Ensuring is installed: ${DEPENDENCY_TERM}\"\n\ncase \"${DEPENDENCY_KIND}\" in\n    git_default)\n        (git clone \\\n            --quiet \\\n            --depth 1 \\\n            --single-branch \\\n            \"${GIT_URL}\" \\\n            scryer_libs/packages/${DEPENDENCY_NAME} && \\\n            touch scryer_libs/temp/parallel_lock_${DEPENDENCY_NAME}) &\n        ;;\n    git_branch)\n        (git clone \\\n            --quiet \\\n            --depth 1 \\\n            --single-branch \\\n            --branch \"${GIT_BRANCH}\" \\\n            \"${GIT_URL}\" \\\n            scryer_libs/packages/${DEPENDENCY_NAME} && \\\n            touch scryer_libs/temp/parallel_lock_${DEPENDENCY_NAME}) &\n        ;;\n    git_tag)\n        (git clone \\\n            --quiet \\\n            --depth 1 \\\n            --single-branch \\\n            --branch \"${GIT_TAG}\" \\\n            \"${GIT_URL}\" \\\n            scryer_libs/packages/${DEPENDENCY_NAME} && \\\n            touch scryer_libs/temp/parallel_lock_${DEPENDENCY_NAME}) &\n        ;;\n    git_hash)\n        (git clone \\\n            --quiet \\\n            --depth 1 \\\n            --single-branch \\\n            \"${GIT_URL}\" \\\n            scryer_libs/packages/${DEPENDENCY_NAME}\n        git -C scryer_libs/packages/${DEPENDENCY_NAME} fetch \\\n            --quiet \\\n            --depth 1 \\\n            origin \"${GIT_HASH}\"\n        git -C scryer_libs/packages/${DEPENDENCY_NAME} switch \\\n            --quiet \\\n            --detach \\\n            \"${GIT_HASH}\" && \\\n            touch scryer_libs/temp/parallel_lock_${DEPENDENCY_NAME}) &\n        ;;\n    path)\n        (ln -rsf \"${DEPENDENCY_PATH}\" \"scryer_libs/packages/${DEPENDENCY_NAME}\" && \\\n            touch scryer_libs/temp/parallel_lock_${DEPENDENCY_NAME}) &\n        ;;\n    *)\n        echo \"Unknown dependency kind\"\n        exit 1\n        ;;\nesac\n").
script_string("ensure_integrity_hash", "#!/bin/sh\nset -eu\n\nCHECKSUM=$(find scryer_libs/packages/${DEPENDENCY_NAME} -type f -print0 | sort -z | xargs -0 sha1sum | sha1sum | awk \'{print $1}\')\necho \"result(\\\"$CHECKSUM\\\").\" > ${RESULT_FILE}").
script_string("ensure_lock_dependency", "#!/bin/sh\nset -eu\n\nGIT_HASH=$(cd scryer_libs/packages/${DEPENDENCY_NAME} && git rev-parse HEAD)\necho \"result(\\\"$GIT_HASH\\\").\" > ${RESULT_FILE}").
% === Generated code end ===
