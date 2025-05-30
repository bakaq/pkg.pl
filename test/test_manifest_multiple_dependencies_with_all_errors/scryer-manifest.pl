name("name_of_the_package").
main_file("main.pl").

dependencies([
    dependency("test", git("https://github.com/constraintAutomaton/test-prolog-package-manager_.git")),
    dependency("test_branch", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git", branch("branch_"))),
    dependency("test_tag", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git", tag("tag_"))),
    dependency("test_hash", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git", hash("abc"))),
    dependency("test_local", path("./local_package_"))
]).
