#!/bin/sh
set -eu

cd scryer_libs/packages/${DEPENDENCY_NAME}

echo "result(\"$(git rev-parse HEAD)\")." > scryer_libs/temp/lock_dependency_${DEPENDENCY_NAME}