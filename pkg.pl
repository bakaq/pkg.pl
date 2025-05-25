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

installation_execution(Plan, Results):-
    ensure_dependencies(Plan, Success),
    (
        Success == false ->
        fail_installation(Plan, [], Results)
        ;   true

    ),
    parse_install_report(Result_Report),
    installation_report(Plan, Result_Report, [], ResultsReversed),
    reverse(ResultsReversed, Results).

fail_installation([], Acc, Acc).
fail_installation([P|Ps], Acc, Results) :-
    Result = P-error("installation script failed"),
    fail_installation(Ps, [Result|Acc], Results).

installation_report([], _, Acc, Acc).
installation_report([P|Ps], Result_Report, Acc, Results):-
    report_result(P, Result_Report, R),
    installation_report(Ps, Result_Report, [R|Acc], Results).


parse_install_report(Result_List) :-
    open("scryer_libs/temp/install_resp.pl", read, Stream),
    parse_install_report_(Stream, [], Result_List),
    close(Stream),
    delete_file("scryer_libs/temp/install_resp.pl").


parse_install_report_(Stream, Acc, Result_List) :-
    read(Stream, Term),
    ( Term == end_of_file ->
        Result_List= Acc
    ; parse_install_report_(Stream, [Term | Acc], Result_List)
    ).

report_message(_, [], error("the result was not reported")).

report_message(Name, [result(Name, Message)| _], Message) :- !.

report_message(Name, [result(_, _)| Rs], Message) :-
    report_message(Name, Rs, Message).


report_result(do_nothing(dependency(Name, DependencyTerm)), _, do_nothing(dependency(Name, DependencyTerm))-success).

report_result(install_dependency(dependency(Name, DependencyTerm)), Result_Messages, Result):-
    report_message(Name, Result_Messages, Message),
    Result = install_dependency(dependency(Name, DependencyTerm))-Message.

report_result(install_locked_dependency(dependency(Name, DependencyTerm)), Result_Messages, Result):-
    report_message(Name, Result_Messages, Message),
    Result = install_locked_dependency(dependency(Name, DependencyTerm))-Message.

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

ensure_dependencies(Plan, Success) :-
    ensure_dependency_command_(Plan, Ls),
    (
        length(Ls, 0)->
            D_String = Ls
        ;   tail(Ls, D_String)
    ),
    Args = [
        "DEPENDENCIES_STRING"-D_String
    ],
    run_script_with_args("ensure_dependency", Args, Success).

tail([_|Ls], Ls).
ensure_dependency_command_([], []).

ensure_dependency_command_([P|Ps], Ls) :-
    ensure_dependency_command_(Ps, Ls0),
    ensure_dependency_command_arg(P, El),
    (
        El == do_nothing ->
            Ls = Ls0
        ;   append([Ls0, "|", El], Ls)
    ).

ensure_dependency_command_arg(do_nothing(D) , do_nothing):-
    current_output(Out),
    phrase_to_stream(("Already installed: ", portray_clause_(D)), Out).

ensure_dependency_command_arg(install_locked_dependency(D) ,El):-
    ensure_dependency_command_arg(install_dependency(D), El).

ensure_dependency_command_arg(install_dependency(dependency(Name, git(Url))) ,El):-
    atom_chars(Atom_Url, Url),
    write_term_to_chars(git(Atom_Url), [quoted(true), double_quotes(true)], DependencyTermChars),
    append(["dependency_term=", DependencyTermChars, ";dependency_name=", Name, ";dependency_kind=git_default;git_url=", Url], El).

ensure_dependency_command_arg(install_dependency(dependency(Name, git(Url,branch(Branch)))) ,El):-
    atom_chars(Atom_Url, Url),
    atom_chars(Atom_Branch, Branch),
    write_term_to_chars(git(Atom_Url,branch(Atom_Branch)), [quoted(true), double_quotes(true)], DependencyTermChars),
    append(["dependency_term=", DependencyTermChars, ";dependency_name=", Name, ";dependency_kind=git_branch;git_url=", Url, ";git_branch=", Branch], El).

ensure_dependency_command_arg(install_dependency(dependency(Name, git(Url,tag(Tag)))) ,El):-
    atom_chars(Atom_Url, Url),
    atom_chars(Atom_Tag, Tag),
    write_term_to_chars(git(Atom_Url,tag(Atom_Tag)), [quoted(true), double_quotes(true)], DependencyTermChars),
    append(["dependency_term=", DependencyTermChars, ";dependency_name=", Name, ";dependency_kind=git_branch;git_url=", Url, ";git_tag=", Tag], El).

ensure_dependency_command_arg(install_dependency(dependency(Name, git(Url,hash(Hash)))) ,El):-
    atom_chars(Atom_Url, Url),
    atom_chars(Atom_Hash, Hash),
    write_term_to_chars(git(Atom_Url,hash(Atom_Hash)), [quoted(true), double_quotes(true)], DependencyTermChars),
    append(["dependency_term=", DependencyTermChars, ";dependency_name=", Name, ";dependency_kind=git_hash;git_url=", Url, ";git_hash=", Hash], El).

ensure_dependency_command_arg(install_dependency(dependency(Name, path(Path))) ,El):-
    atom_chars(Atom_Path, Path),
    write_term_to_chars(path(Atom_Path), [quoted(true), double_quotes(true)], DependencyTermChars),
    append(["dependency_term=", DependencyTermChars, ";dependency_name=", Name, ";dependency_kind=path;dependency_path=", Path], El).

lock_dependency_with_name([dependency(Name, X, _)|_], dependency(Name, _), dependency(Name, X)) :- !.

lock_dependency_with_name([_|Ls], dependency(Name, _), Dep) :-
    lock_dependency_with_name(Ls, dependency(Name, _), Dep).

plan(logical_plan(IPlan, LPlan), Ds, LockDeps) :-
    installation_plan(IPlan, Ds, LockDeps),
    lock_plan(IPlan, [], LPlan).

installation_plan([], [], _).

installation_plan(Plan, [D|Ds], LockDeps) :-
    installation_plan(Plan0, Ds, LockDeps),
    install_step(Installation_Step, D, LockDeps),
    append([Plan0, [Installation_Step]], Plan).

lock_plan([], Acc, Acc).

lock_plan([IP|IPs], Acc, LPlan):-
    lock_step(IP, Step),
    lock_plan(IPs, [Step|Acc], LPlan).

lock_step(do_nothing(D), do_nothing(D)).
lock_step(install_dependency(D), lock(D)).
lock_step(install_locked_dependency(D), do_nothing(D)).

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

% === Generated code start ===
script_string("ensure_dependency", "#!/bin/sh\nset -eu\n\nIFS=\'|\' read -r -a DEPENDENCIES <<< \"$DEPENDENCIES_STRING\"\n\ntouch scryer_libs/temp/install_resp.pl\n\nfor dependency in \"${DEPENDENCIES[@]}\"; do\n    IFS=\';\' read -ra fields <<< \"$dependency\"\n    for field in \"${fields[@]}\"; do\n        key=\"${field%%=*}\"\n        value=\"${field#*=}\"\n        eval \"$key=\\\"\\$value\\\"\"\n    done\n\n    echo \"Ensuring is installed: ${dependency_term}\"\n\n    case \"${dependency_kind}\" in\n        git_default)\n            (\n                error_output=$(git clone \\\n                    --quiet \\\n                    --depth 1 \\\n                    --single-branch \\\n                    \"${git_url}\" \\\n                    \"scryer_libs/packages/${dependency_name}\" 2>&1 1>/dev/null\n                )\n\n                if [ -z \"$error_output\" ]; then\n                    flock scryer_libs/temp/install_resp.pl.lock \\\n                        -c \"echo \\\"result(\\\\\\\"${dependency_name}\\\\\\\", success).\\\" >> scryer_libs/temp/install_resp.pl\"\n                else\n                    flock scryer_libs/temp/install_resp.pl.lock \\\n                        -c \"echo \\\"result(\\\\\\\"${dependency_name}\\\\\\\", error(${error_output})).\\\" >> scryer_libs/temp/install_resp.pl\"\n                fi\n            ) &\n            ;;\n        git_branch)\n            (\n                error_output=$(git clone \\\n                    --quiet \\\n                    --depth 1 \\\n                    --single-branch \\\n                    --branch \"${git_branch}\" \\\n                    \"${git_url}\" \\\n                    \"scryer_libs/packages/${dependency_name}\" 2>&1 1>/dev/null\n                )\n\n                if [ -z \"$error_output\" ]; then\n                    flock scryer_libs/temp/install_resp.pl.lock \\\n                        -c \"echo \\\"result(\\\\\\\"${dependency_name}\\\\\\\", success).\\\" >> scryer_libs/temp/install_resp.pl\"\n                else\n                    flock scryer_libs/temp/install_resp.pl.lock \\\n                        -c \"echo \\\"result(\\\\\\\"${dependency_name}\\\\\\\", error(${error_output})).\\\" >> scryer_libs/temp/install_resp.pl\"\n                fi\n            ) &\n            ;;\n        git_tag)\n            (\n                error_output=$(git clone \\\n                    --quiet \\\n                    --depth 1 \\\n                    --single-branch \\\n                    --branch \"${git_tag}\" \\\n                    \"${git_url}\" \\\n                    \"scryer_libs/packages/${dependency_name}\" 2>&1 1>/dev/null\n                )\n\n                if [ -z \"$error_output\" ]; then\n                    flock scryer_libs/temp/install_resp.pl.lock \\\n                        -c \"echo \\\"result(\\\\\\\"${dependency_name}\\\\\\\", success).\\\" >> scryer_libs/temp/install_resp.pl\"\n                else\n                    flock scryer_libs/temp/install_resp.pl.lock \\\n                        -c \"echo \\\"result(\\\\\\\"${dependency_name}\\\\\\\", error(${error_output})).\\\" >> scryer_libs/temp/install_resp.pl\"\n                fi\n            ) &\n            ;;\n        git_hash)\n            (\n                error_output=$(git clone \\\n                    --quiet \\\n                    --depth 1 \\\n                    --single-branch \\\n                    \"${git_url}\" \\\n                    \"scryer_libs/packages/${dependency_name}\" 2>&1 1>/dev/null\n                )\n\n                if [ -z \"$error_output\" ]; then\n                    fetch_error=$(git -C \"scryer_libs/packages/${dependency_name}\" fetch \\\n                        --quiet \\\n                        --depth 1 \\\n                        origin \"${git_hash}\" 2>&1 1>/dev/null\n                    )\n                    switch_error=$(git -C \"scryer_libs/packages/${dependency_name}\" switch \\\n                        --quiet \\\n                        --detach \\\n                        \"${git_hash}\" 2>&1 1>/dev/null\n                    )\n                    combined_error=\"${fetch_error}${switch_error}\"\n\n                    if [ -z \"$combined_error\" ]; then\n                        flock scryer_libs/temp/install_resp.pl.lock \\\n                            -c \"echo \\\"result(\\\\\\\"${dependency_name}\\\\\\\", success).\\\" >> scryer_libs/temp/install_resp.pl\"\n                    else\n                        flock scryer_libs/temp/install_resp.pl.lock \\\n                            -c \"echo \\\"result(\\\\\\\"${dependency_name}\\\\\\\", error(${combined_error})).\\\" >> scryer_libs/temp/install_resp.pl\"\n                    fi\n                else\n                    flock scryer_libs/temp/install_resp.pl.lock \\\n                        -c \"echo \\\"result(\\\\\\\"${dependency_name}\\\\\\\", error(${error_output})).\\\" >> scryer_libs/temp/install_resp.pl\"\n                fi\n            ) &\n            ;;\n        path)\n            (\n                error_output=$(ln -rsf \"${dependency_path}\" \"scryer_libs/packages/${dependency_name}\" 2>&1 1>/dev/null)\n\n                if [ -z \"$error_output\" ]; then\n                    flock scryer_libs/temp/install_resp.pl.lock \\\n                        -c \"echo \\\"result(\\\\\\\"${dependency_name}\\\\\\\", success).\\\" >> scryer_libs/temp/install_resp.pl\"\n                else\n                    flock scryer_libs/temp/install_resp.pl.lock \\\n                        -c \"echo \\\"result(\\\\\\\"${dependency_name}\\\\\\\", error(${error_output})).\\\" >> scryer_libs/temp/install_resp.pl\"\n                fi\n            ) &\n            ;;\n        *)\n            echo \"Unknown dependency kind: ${dependency_kind}\"\n            lock scryer_libs/temp/install_resp.pl.lock \\\n                        -c \"echo \\\"result(\\\\\\\"${dependency_name}\\\\\\\", error(\\\"Unknown dependency kind: ${dependency_kind}\\\").\\\" >> scryer_libs/temp/install_resp.pl\"\n            ;;\n    esac\ndone\n\nwait\n\nrm -f scryer_libs/temp/install_resp.pl.lock\n").
script_string("ensure_integrity_hash", "#!/bin/sh\nset -eu\n\nCHECKSUM=$(find scryer_libs/packages/${DEPENDENCY_NAME} -type f -print0 | sort -z | xargs -0 sha1sum | sha1sum | awk \'{print $1}\')\necho \"result(\\\"$CHECKSUM\\\").\" > ${RESULT_FILE}").
script_string("ensure_lock_dependency", "#!/bin/sh\nset -eu\n\nIFS=\'|\' read -r -a DEPENDENCIES <<< \"$DEPENDENCIES_STRING\"\n\nmkdir -p scryer_libs/temp\n\nfor dependency in \"${DEPENDENCIES[@]}\"; do\n    IFS=\';\' read -ra fields <<< \"$dependency\"\n    for field in \"${fields[@]}\"; do\n        key=\"${field%%=*}\"\n        value=\"${field#*=}\"\n        eval \"$key=\\\"\\$value\\\"\"\n    done\n\n    echo \"Ensuring is locked: ${dependency_term}\"\n\n    (\n        cd \"scryer_libs/packages/${dependency_name}\"\n\n        ERROR=\"\"\n        CHECKSUM=$(find ./ -type f -print0 | sort -z | xargs -0 sha1sum | sha1sum 2>&1) || ERROR=\"checksum failure: $CHECKSUM\"\n        CHECKSUM=$(echo \"$CHECKSUM\" | awk \'{print $1}\')\n\n        if [ \"$dependency_kind\" = \"git\" ]; then\n            GIT_HASH=$(git rev-parse HEAD 2>&1) || ERROR=\"$ERROR git failure: $GIT_HASH\"\n            GIT_HASH=$(echo \"$GIT_HASH\" | head -n1)\n        else\n            GIT_HASH=\"none\"\n        fi\n\n        if [ -z \"$ERROR\" ]; then\n            RESULT=\"success\"\n        else\n            ESCAPED_ERROR=$(printf \'%s\' \"$ERROR\" | sed \'s/\\\\/\\\\\\\\/g; s/\"/\\\\\"/g\')\n            RESULT=\"error(\\\\\\\"$ESCAPED_ERROR\\\\\\\")\"\n        fi\n\n        flock scryer_libs/temp/lock_resp.pl.lock \\\n            -c \"echo \\\"result(\\\\\\\"${dependency_name}\\\\\\\", \\\\\\\"${GIT_HASH}\\\\\\\", \\\\\\\"${CHECKSUM}\\\\\\\", ${RESULT}).\\\" >> scryer_libs/temp/lock_resp.pl\"\n    )&\ndone\n\nwait\n").
% === Generated code end ===
