name("name_of_the_package").
main_file("main.pl").

dependencies([
    dependency("test", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git")),
    dependency("test_branch", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git", branch("branch"))),
    dependency("test_tag", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git", tag("tag"))),
    dependency("test_hash", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git", hash("d19fefc1d7907f6675e181601bb9b8b94561b441"))),
    dependency("test_local", path("./local_package")),
    dependency("error", path("./bar"))
]).
