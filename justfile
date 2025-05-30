default:
    @just --list

build: codegen
    mv pkg.pl.gen pkg.pl

codegen:
    #!/bin/sh
    set -eu

    sed -e "/% === Generated code start ===/q" pkg.pl > pkg.pl.gen

    for file in scripts/*.sh; do
        script_string=$(scryer-prolog -f -g "
            use_module(library(pio)),
            use_module(library(dcgs)),
            phrase_from_file(seq(Script),\"${file}\"),
            write_term(Script, [quoted(true),double_quotes(true)]),
            halt.
        ")
        script_name=$(basename -s .sh "${file}")
        printf '%s\n' "script_string(\"${script_name}\", ${script_string})." >> pkg.pl.gen
    done
    sed -n -e "/% === Generated code end ===/,$ {p}" pkg.pl >> pkg.pl.gen

codegen-check: codegen
    diff pkg.pl pkg.pl.gen

lint-sh:
    shellcheck -s sh -S warning ./**/*.sh
    
# All the checks made in CI
ci: codegen-check lint-sh test

test: 
    just build 
    just test-example
    just test/build
    just test/test

test-example:
    just example/test

clean-codegen:
    rm -f pkg.pl.gen

clean: clean-codegen
