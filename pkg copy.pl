/* SPDX-License-Identifier: Unlicense */

:- module(pkg, [pkg_install/0]).

:- use_module(library(os)).
:- use_module(library(pio)).
:- use_module(library(files)).
:- use_module(library(lists)).
:- use_module(library(format)).
:- use_module(library(debug)).

dependency_directory_name("scryer_libs").
manifest_file_name("scryer-manifest.pl").
lock_file_name("manifest-lock.pl").

scryer_path(ScryerPath) :-
    (   getenv("SCRYER_PATH", ScryerPath) ->
        true
    ;   dependency_directory_name(ScryerPath)
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

user:term_expansion((:- use_module(pkg(Package))), UsePackage) :-
    atom_chars(Package, PackageChars),
    scryer_path(ScryerPath),
    append([ScryerPath, "/", PackageChars], PackagePath),
    manifest_file_name(ManifestName),
    append([PackagePath, "/", ManifestName], ManifestPath),
    parse_manifest(ManifestPath, Manifest),
    member(main_file(MainFile), Manifest),
    append([PackagePath, "/", MainFile], PackageMainFileChars),
    atom_chars(PackageMainFile, PackageMainFileChars),
    UsePackage = (
        :- use_module(PackageMainFile)
    ).

pkg_install :-
    manifest_file_name(ManifestFileName),
    dependency_directory_name(DependencyDirectoryName),
    lock_file_name(LockFileFileName),
    parse_manifest(ManifestFileName, Manifest),
    
    (   directory_exists(DependencyDirectoryName) ->
        true
    ;   make_directory_path(DependencyDirectoryName)
    ),
    (   file_exists(LockFileFileName) ->
        parse_manifest(LockFileFileName, LockFile),
        member(lock_dependencies(LockDepsMat),LockFile)
    ;   LockDepsMat = []
    ),
    setenv("SHELL", "/bin/sh"),
    setenv("GIT_ADVICE", "0"),
    (   member(dependencies(Deps), Manifest) ->
        ensure_dependencies(Deps, LockDepsMat),
        ensure_lock_dependencies(Deps, LockDeps)
    ;   true
    ),
    materialize_lock_file(LockDeps).

materialize_lock_file(LockDeps) :-
    lock_file_name(LockFileFileName),
    open(LockFileFileName, write, Stream),
    write(Stream, '% WARNING: This file is auto-generated. Do NOT modify it manually.\n\n'),
    write_term(Stream, lock_dependencies(LockDeps), [double_quotes(true)]),
    write(Stream, '.\n'),
    close(Stream).

dependency(_, _, _).
lock_dependencies(_).

lock_dependency_with_name([dependency(Name, X, _)|_], dependency(Name, _), dependency(Name, X)) :- !.

lock_dependency_with_name([_|Ls], dependency(Name, _), Dep) :-
    lock_dependency_with_name(Ls, dependency(Name, _), Dep).


ensure_dependencies([], _).
ensure_dependencies([D|Ds], Ls) :-
    (   lock_dependency_with_name(Ls, D, L) ->
        ensure_dependency(L)
    ;   ensure_dependency(D)
    ),
    ensure_dependencies(Ds, Ls).    

ensure_lock_dependencies([], []).

ensure_lock_dependencies([D|Ds], [L|Ls]) :-
    ensure_lock_dependency(D, L),
    ensure_lock_dependencies(Ds, Ls).

ensure_lock_dependency(dependency(PkgName, X), LockedDependencyTerm) :-
    lock_dependency(dependency(PkgName, X), LockedDependencyTerm).

ensure_dependency(dependency(PkgName, DependencyTerm)) :-
    atom_chars(PkgName, Name),
    current_output(Out),
    dependency_directory_name(DF),
    append([DF, "/", Name], DepF),
    ( directory_exists(DepF) ->
        phrase_to_stream(("Already installed: ", portray_clause_(dependency(PkgName, DependencyTerm))), Out)
    ;
        phrase_to_stream(("Ensuring is installed: ", portray_clause_(dependency(PkgName, DependencyTerm))), Out),
        % Hell yeah, injection attack!
        dependency_aq_command(dependency(PkgName, DependencyTerm), Command),
        shell(Command)
    ).

dependency_aq_command(dependency(PkgName, git(X)), Command) :- atom_chars(PkgName, Name), git_command(git(X), Name, Command).
dependency_aq_command(dependency(PkgName, git(X, Y)), Command) :- atom_chars(PkgName, Name), git_command(git(X, Y), Name, Command).
dependency_aq_command(dependency(PkgName, path(X)), Command) :- atom_chars(PkgName, Name), path_command(path(X), Name, Command).

git_command(git(Url), PkgName, Command) :-
    dependency_directory_name(DF),
    Segments = ["git clone --quiet --depth 1 --single-branch ", Url, " ", DF, "/", PkgName, " &"],
    append(Segments, Command).

git_command(git(Url, branch(Branch)), PkgName,  Command) :-
    dependency_directory_name(DF),
    Segments = [
        "git clone --quiet --depth 1 --single-branch --branch ",
        Branch, " ", Url, " ", DF, "/", PkgName, " &"
    ],
    append(Segments, Command).

git_command(git(Url, tag(Tag)), PkgName, Command) :-
    git_command(git(Url, branch(Tag)), PkgName, Command).

git_command(git(Url, hash(Hash)), PkgName, Command) :-
    dependency_directory_name(DF),
    CloneCommand = ["(git clone --quiet --depth 1 --single-branch ", Url, " ", DF, "/", PkgName, " "],
    GetHashCommitCommand = [" && cd ", DF, "/", PkgName, " && git fetch --quiet --depth 1 origin ", Hash, " && git checkout --quiet ", Hash, " )"],
    append(CloneCommand, GetHashCommitCommand,  Segments),
    append(Segments, Command).

path_command(path(Path), PkgName, Command) :-
    dependency_directory_name(DF),
    Segments = ["ln -rs ", Path, " ", DF, "/", PkgName ],
    append(Segments, Command).

lock_dependency(dependency(PkgName, git(Url)), LockDependencyTerm) :-
    dependency_directory_name(DF),
    atom_chars(PkgName, Name),
    append(["cd ", DF,"/", Name, " && git rev-parse HEAD"], GitHashCmd),
    append(["find ",DF,"/", Name, " -type f -print0 | sort -z | xargs -0 sha1sum | sha1sum | awk '{print $1}'"], IntegrityHashCmd),
    run_command(GitHashCmd, temp_result(Hash)),
    run_command(IntegrityHashCmd, temp_result(IntegrityHash)),
    LockDependencyTerm=dependency(PkgName, git(Url, hash(Hash)), IntegrityHash).

lock_dependency(dependency(Name, git(Url, tag(_))), LockDependencyTerm) :-
    lock_dependency(dependency(Name, git(Url)), LockDependencyTerm).

lock_dependency(dependency(Name, git(Url, branch(_))), LockDependencyTerm) :-
    lock_dependency(dependency(Name, git(Url)), LockDependencyTerm).

lock_dependency(dependency(PkgName, git(Url, hash(Hash))), LockDependencyTerm):-
    dependency_directory_name(DF),
    atom_chars(PkgName, Name),
    append(["find ",DF,"/", Name, " -type f -print0 | sort -z | xargs -0 sha1sum | sha1sum | awk '{print $1}'"], IntegrityHashCmd),
    run_command(IntegrityHashCmd, temp_result(IntegrityHash)),
    LockDependencyTerm=dependency(PkgName, git(Url, hash(Hash)), IntegrityHash).

lock_dependency(dependency(PkgName, path(Path)), LockDependencyTerm) :-
    dependency_directory_name(DF),
    atom_chars(PkgName, Name),
    append(["find ",DF,"/", Name, " -type f -print0 | sort -z | xargs -0 sha1sum | sha1sum | awk '{print $1}'"], IntegrityHashCmd),
    run_command(IntegrityHashCmd, temp_result(IntegrityHash)),
    LockDependencyTerm=dependency(Name, path(Path), IntegrityHash).

/**
 A hack to get the result of a shell command.
 Maybe current_output could fix this
*/
run_command(Command, Output) :-
    append(["echo \"temp_result(\\\"$(",Command, ")\\\").\" > temp"], Command2),
    shell(Command2),
    open('temp', read, Stream),
    read(Stream, Output),
    close(Stream),
    shell("rm temp").