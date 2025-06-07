name("manifest_with_no_dependencies").
main_file("main.pl").
dependencies([
    dependency("test", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git", hash("d19fefc1d7907f6675e181601bb9b8b94561b441")))
]).
