#!/bin/sh
set -eu

CHECKSUM=$(find scryer_libs/packages/${DEPENDENCY_NAME} -type f -print0 | sort -z | xargs -0 sha1sum | sha1sum | awk '{print $1}')
echo "result(\"$CHECKSUM\")." > ${RESULT_FILE}