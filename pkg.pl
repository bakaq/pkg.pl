/* SPDX-License-Identifier: Unlicense */

:- module(pkg, [pkg_install/1]).

:- use_module(library(os)).
:- use_module(library(pio)).
:- use_module(library(files)).
:- use_module(library(lists)).
:- use_module(library(charsio)).
:- use_module(library(format)).

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

% Link the pkg depedencies to the right physical module
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

% Predicate to install the dependencies
pkg_install(Report) :-
    parse_manifest("scryer-manifest.pl", Manifest),
    ensure_scryer_libs,
    setenv("SHELL", "/bin/sh"),
    setenv("GIT_ADVICE", "0"),
    (   member(dependencies(Deps), Manifest) ->
       logical_plan(Plan, Deps)
    ;   true
    ),
    installation_execution(Plan, Report),
    delete_directory("scryer_libs/temp").

% A logical plan to install the dependencies
logical_plan(Plan, Ds) :-
    fetch_plan(Plan,[], Ds).

% A logical plan to fetch the dependencies
fetch_plan(Acc, Acc, []).

fetch_plan(Plan, Acc, [D|Ds]) :-
    fetch_step(Installation_Step, D),
    fetch_plan(Plan, [Installation_Step|Acc], Ds).

% A step of a logical plan to fetch the dependencies
fetch_step(Installation_Step, dependency(Name, DependencyTerm)):-
    append(["scryer_libs/packages/", Name], DepRepo),
    (
    directory_exists(DepRepo) ->
        Installation_Step = do_nothing(dependency(Name, DependencyTerm))
    ;   Installation_Step = install_dependency(dependency(Name, DependencyTerm))
    ).

% Execute the physical installation of the dependencies
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

% All dependency installation failed
fail_installation([], Acc, Acc).
fail_installation([P|Ps], Acc, Results) :-
    Result = P-error("installation script failed"),
    fail_installation(Ps, [Result|Acc], Results).

% Parse the report of the installation of the dependencies
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

% The installation report of the dependencies
installation_report([], _, Acc, Acc).
installation_report([P|Ps], Result_Report, Acc, Results):-
    report_installation_step(P, Result_Report, R),
    installation_report(Ps, Result_Report, [R|Acc], Results).

% A message of an installation report 
report_message(_, [], error("the result was not reported")).

report_message(Name, [result(Name, Message)| _], Message) :- !.

report_message(Name, [result(_, _)| Rs], Message) :-
    report_message(Name, Rs, Message).

% The result of a logical step
report_installation_step(do_nothing(dependency(Name, DependencyTerm)), _, do_nothing(dependency(Name, DependencyTerm))-success).

report_installation_step(install_dependency(dependency(Name, DependencyTerm)), Result_Messages, Result):-
    report_message(Name, Result_Messages, Message),
    Result = install_dependency(dependency(Name, DependencyTerm))-Message.

% Execute the logical plan
ensure_dependencies(Plan, Success) :-
    physical_plan(Plan, Ls),
    (
        length(Ls, 0)->
            D_String = Ls
        ;   tail(Ls, D_String)
    ),
    Args = [
        "DEPENDENCIES_STRING"-D_String
    ],
    run_script_with_args("ensure_dependency", Args, Success).

% Create a physical plan in shell script
physical_plan([], []).

physical_plan([P|Ps], Ls) :-
    physical_plan(Ps, Ls0),
    physical_plan_step(P, El),
    (
        El == do_nothing ->
            Ls = Ls0
        ;   append([Ls0, "|", El], Ls)
    ).

% Create a step for the shell script physical plan  
physical_plan_step(do_nothing(D) , do_nothing):-
    current_output(Out),
    phrase_to_stream(("Already installed: ", portray_clause_(D)), Out).
    
physical_plan_step(install_dependency(dependency(Name, git(Url))) ,El):-
    atom_chars(Atom_Url, Url),
    write_term_to_chars(git(Atom_Url), [quoted(true), double_quotes(true)], DependencyTermChars),
    append(["dependency_term=", DependencyTermChars, ";dependency_name=", Name, ";dependency_kind=git_default;git_url=", Url], El).

physical_plan_step(install_dependency(dependency(Name, git(Url,branch(Branch)))) ,El):-
    atom_chars(Atom_Url, Url),
    atom_chars(Atom_Branch, Branch),
    write_term_to_chars(git(Atom_Url,branch(Atom_Branch)), [quoted(true), double_quotes(true)], DependencyTermChars),
    append(["dependency_term=", DependencyTermChars, ";dependency_name=", Name, ";dependency_kind=git_branch;git_url=", Url, ";git_branch=", Branch], El).

physical_plan_step(install_dependency(dependency(Name, git(Url,tag(Tag)))) ,El):-
    atom_chars(Atom_Url, Url),
    atom_chars(Atom_Tag, Tag),
    write_term_to_chars(git(Atom_Url,tag(Atom_Tag)), [quoted(true), double_quotes(true)], DependencyTermChars),
    append(["dependency_term=", DependencyTermChars, ";dependency_name=", Name, ";dependency_kind=git_tag;git_url=", Url, ";git_tag=", Tag], El).

physical_plan_step(install_dependency(dependency(Name, git(Url,hash(Hash)))) ,El):-
    atom_chars(Atom_Url, Url),
    atom_chars(Atom_Hash, Hash),
    write_term_to_chars(git(Atom_Url,hash(Atom_Hash)), [quoted(true), double_quotes(true)], DependencyTermChars),
    append(["dependency_term=", DependencyTermChars, ";dependency_name=", Name, ";dependency_kind=git_hash;git_url=", Url, ";git_hash=", Hash], El).

physical_plan_step(install_dependency(dependency(Name, path(Path))) ,El):-
    atom_chars(Atom_Path, Path),
    write_term_to_chars(path(Atom_Path), [quoted(true), double_quotes(true)], DependencyTermChars),
    append(["dependency_term=", DependencyTermChars, ";dependency_name=", Name, ";dependency_kind=path;dependency_path=", Path], El).

% the tail of a list
tail([_|Ls], Ls).

% === Generated code start ===
script_string("ensure_dependency", "#!/bin/sh\nset -u\n\nwrite_result() {\n  flock scryer_libs/temp/install_resp.pl.lock -c \\\n    \"printf \'result(\\\"%s\\\", %s).\\n\' \\\"$1\\\" \\\"$2\\\" >> scryer_libs/temp/install_resp.pl\"\n}\n\nwrite_success() {\n  write_result \"$1\" \"success\"\n}\n\nwrite_error() {\n  escaped_error=$(printf \'%s\' \"$2\" | sed -e \'s/\\\\/\\\\\\\\/g\' -e \'s/\"/\\\\\"/g\')\n  escaped_error=$(printf \'%s\' \"$escaped_error\" | tr \'\\r\\n\' \'\\\\n\')\n  escaped_error=$(printf \'%s\' \"$escaped_error\" | sed \'s/\xa0\/ /g\')\n  write_result \"$1\" \"error(\\\\\\\"$escaped_error\\\\\\\")\"\n}\n\nOLD_IFS=$IFS\nIFS=\'|\'\nset -- $DEPENDENCIES_STRING\nIFS=$OLD_IFS\n\ntouch scryer_libs/temp/install_resp.pl\n\nfor dependency in \"$@\"; do\n    unset dependency_term dependency_kind dependency_name git_url git_branch git_tag git_hash dependency_path\n    \n    IFS=\';\'\n    set -- $dependency\n    IFS=$OLD_IFS\n\n    while [ \"$#\" -gt 0 ]; do\n        field=$1\n        shift\n\n        key=$(printf \"%s\" \"$field\" | cut -d= -f1)\n        value=$(printf \"%s\" \"$field\" | cut -d= -f2-)\n\n        case \"$key\" in\n            dependency_term) dependency_term=$value ;;\n            dependency_kind) dependency_kind=$value ;;\n            dependency_name) dependency_name=$value ;;\n            git_url) git_url=$value ;;\n            git_branch) git_branch=$value ;;\n            git_tag) git_tag=$value ;;\n            git_hash) git_hash=$value ;;\n            dependency_path) dependency_path=$value ;;\n        esac\n    done\n\n    printf \"Ensuring is installed: %s\\n\" \"${dependency_term}\"\n\n    case \"${dependency_kind}\" in\n        git_default)\n            (\n                error_output=$(git clone \\\n                    --quiet \\\n                    --depth 1 \\\n                    --single-branch \\\n                    \"${git_url}\" \\\n                    \"scryer_libs/packages/${dependency_name}\" 2>&1 1>/dev/null\n                )\n\n                if [ -z \"$error_output\" ]; then\n                    write_success \"${dependency_name}\"\n                else\n                    write_error \"${dependency_name}\" \"$error_output\"\n                fi\n            ) &\n            ;;\n        git_branch)\n            (\n                error_output=$(git clone \\\n                    --quiet \\\n                    --depth 1 \\\n                    --single-branch \\\n                    --branch \"${git_branch}\" \\\n                    \"${git_url}\" \\\n                    \"scryer_libs/packages/${dependency_name}\" 2>&1 1>/dev/null\n                )\n                \n                if [ -z \"$error_output\" ]; then\n                    write_success \"${dependency_name}\"\n                else\n                    write_error \"${dependency_name}\" \"$error_output\"\n                fi\n            ) &\n            ;;\n        git_tag)\n            (\n                error_output=$(git clone \\\n                    --quiet \\\n                    --depth 1 \\\n                    --single-branch \\\n                    --branch \"${git_tag}\" \\\n                    \"${git_url}\" \\\n                    \"scryer_libs/packages/${dependency_name}\" 2>&1 1>/dev/null\n                )\n                \n                if [ -z \"$error_output\" ]; then\n                    write_success \"${dependency_name}\"\n                else\n                    write_error \"${dependency_name}\" \"$error_output\"\n                fi\n            ) &\n            ;;\n        git_hash)\n            (\n                error_output=$(git clone \\\n                    --quiet \\\n                    --depth 1 \\\n                    --single-branch \\\n                    \"${git_url}\" \\\n                    \"scryer_libs/packages/${dependency_name}\" 2>&1 1>/dev/null\n                )\n                \n                if [ -z \"$error_output\" ]; then\n                    fetch_error=$(git -C \"scryer_libs/packages/${dependency_name}\" fetch \\\n                        --quiet \\\n                        --depth 1 \\\n                        origin \"${git_hash}\" 2>&1 1>/dev/null\n                    )\n                    switch_error=$(git -C \"scryer_libs/packages/${dependency_name}\" switch \\\n                        --quiet \\\n                        --detach \\\n                        \"${git_hash}\" 2>&1 1>/dev/null\n                    )\n                    combined_error=\"${fetch_error}; ${switch_error}\"\n\n                    if [ -z \"$fetch_error\" ] && [ -z \"$switch_error\" ]; then\n                        write_success \"${dependency_name}\"\n                    else\n                        write_error \"${dependency_name}\" \"$combined_error\"\n                    fi\n                else\n                    write_error \"${dependency_name}\" \"$error_output\"\n                fi\n            ) &\n            ;;\n        path)\n            (\n                if [ -d \"${dependency_path}\" ]; then\n                    error_output=$(ln -rsf \"${dependency_path}\" \"scryer_libs/packages/${dependency_name}\" 2>&1 1>/dev/null)\n\n                    if [ -z \"$error_output\" ]; then\n                        write_success \"${dependency_name}\"\n                    else\n                        write_error \"${dependency_name}\" \"$error_output\"\n                    fi\n                else\n                    write_error \"${dependency_name}\" \"${dependency_path} does not exist\"\n                fi\n            ) &\n            ;;\n        *)\n            printf \"Unknown dependency kind: %s\\n\" \"${dependency_kind}\"\n            write_error \"${dependency_name}\" \"Unknown dependency kind: ${dependency_kind}\"\n            ;;\n    esac\ndone\n\nwait\n\nrm -f scryer_libs/temp/install_resp.pl.lock\n").
% === Generated code end ===
