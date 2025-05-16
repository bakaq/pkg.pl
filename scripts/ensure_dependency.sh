#!/bin/sh
set -eu

echo "Ensuring is installed: ${DEPENDENCY_TERM}"

case "${DEPENDENCY_KIND}" in
    git_default)
        git clone \
            --quiet \
            --depth 1 \
            --single-branch \
            "${GIT_URL}" \
            scryer_libs/packages/${DEPENDENCY_NAME}
        ;;
    git_branch)
        git clone \
            --quiet \
            --depth 1 \
            --single-branch \
            --branch "${GIT_BRANCH}" \
            "${GIT_URL}" \
            scryer_libs/packages/${DEPENDENCY_NAME}
        ;;
    git_tag)
        git clone \
            --quiet \
            --depth 1 \
            --single-branch \
            --branch "${GIT_TAG}" \
            "${GIT_URL}" \
            scryer_libs/packages/${DEPENDENCY_NAME}
        ;;
    git_hash)
        git clone \
            --quiet \
            --depth 1 \
            --single-branch \
            "${GIT_URL}" \
            scryer_libs/${DEPENDENCY_NAME}
        git -C scryer_libs/packages/${DEPENDENCY_NAME} fetch \
            --quiet \
            --depth 1 \
            origin "${GIT_HASH}"
        git -C scryer_libs/packages/${DEPENDENCY_NAME} switch \
            --quiet \
            --detach \
            "${GIT_HASH}"
        ;;
    path)
        ln -rsf "${DEPENDENCY_PATH}" "scryer_libs/packages/${DEPENDENCY_NAME}"
        ;;
    *)
        echo "Unknown dependency kind"
        exit 1
        ;;
esac
