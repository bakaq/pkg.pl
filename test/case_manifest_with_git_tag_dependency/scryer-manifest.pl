name("manifest_with_no_dependencies").
main_file("main.pl").
dependencies([
    dependency("test", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git", tag("tag")))
]).
