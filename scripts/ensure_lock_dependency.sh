#!/bin/sh
set -eu

GIT_HASH=$(cd scryer_libs/packages/${DEPENDENCY_NAME} && git rev-parse HEAD)
echo "result(\"$GIT_HASH\")." > ${RESULT_FILE}