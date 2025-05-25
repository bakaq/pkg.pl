#!/bin/sh
set -eu

IFS='|' read -r -a DEPENDENCIES <<< "$DEPENDENCIES_STRING"

touch scryer_libs/temp/install_resp.pl

for dependency in "${DEPENDENCIES[@]}"; do
    IFS=';' read -ra fields <<< "$dependency"
    for field in "${fields[@]}"; do
        key="${field%%=*}"
        value="${field#*=}"
        eval "$key=\"\$value\""
    done

    echo "Ensuring is installed: ${dependency_term}"

    case "${dependency_kind}" in
        git_default)
            (
                error_output=$(git clone \
                    --quiet \
                    --depth 1 \
                    --single-branch \
                    "${git_url}" \
                    "scryer_libs/packages/${dependency_name}" 2>&1 1>/dev/null
                )

                if [ -z "$error_output" ]; then
                    flock scryer_libs/temp/install_resp.pl.lock \
                        -c "echo \"result(\\\"${dependency_name}\\\", success).\" >> scryer_libs/temp/install_resp.pl"
                else
                    flock scryer_libs/temp/install_resp.pl.lock \
                        -c "echo \"result(\\\"${dependency_name}\\\", error(${error_output})).\" >> scryer_libs/temp/install_resp.pl"
                fi
            ) &
            ;;
        git_branch)
            (
                error_output=$(git clone \
                    --quiet \
                    --depth 1 \
                    --single-branch \
                    --branch "${git_branch}" \
                    "${git_url}" \
                    "scryer_libs/packages/${dependency_name}" 2>&1 1>/dev/null
                )

                if [ -z "$error_output" ]; then
                    flock scryer_libs/temp/install_resp.pl.lock \
                        -c "echo \"result(\\\"${dependency_name}\\\", success).\" >> scryer_libs/temp/install_resp.pl"
                else
                    flock scryer_libs/temp/install_resp.pl.lock \
                        -c "echo \"result(\\\"${dependency_name}\\\", error(${error_output})).\" >> scryer_libs/temp/install_resp.pl"
                fi
            ) &
            ;;
        git_tag)
            (
                error_output=$(git clone \
                    --quiet \
                    --depth 1 \
                    --single-branch \
                    --branch "${git_tag}" \
                    "${git_url}" \
                    "scryer_libs/packages/${dependency_name}" 2>&1 1>/dev/null
                )

                if [ -z "$error_output" ]; then
                    flock scryer_libs/temp/install_resp.pl.lock \
                        -c "echo \"result(\\\"${dependency_name}\\\", success).\" >> scryer_libs/temp/install_resp.pl"
                else
                    flock scryer_libs/temp/install_resp.pl.lock \
                        -c "echo \"result(\\\"${dependency_name}\\\", error(${error_output})).\" >> scryer_libs/temp/install_resp.pl"
                fi
            ) &
            ;;
        git_hash)
            (
                error_output=$(git clone \
                    --quiet \
                    --depth 1 \
                    --single-branch \
                    "${git_url}" \
                    "scryer_libs/packages/${dependency_name}" 2>&1 1>/dev/null
                )

                if [ -z "$error_output" ]; then
                    fetch_error=$(git -C "scryer_libs/packages/${dependency_name}" fetch \
                        --quiet \
                        --depth 1 \
                        origin "${git_hash}" 2>&1 1>/dev/null
                    )
                    switch_error=$(git -C "scryer_libs/packages/${dependency_name}" switch \
                        --quiet \
                        --detach \
                        "${git_hash}" 2>&1 1>/dev/null
                    )
                    combined_error="${fetch_error}${switch_error}"

                    if [ -z "$combined_error" ]; then
                        flock scryer_libs/temp/install_resp.pl.lock \
                            -c "echo \"result(\\\"${dependency_name}\\\", success).\" >> scryer_libs/temp/install_resp.pl"
                    else
                        flock scryer_libs/temp/install_resp.pl.lock \
                            -c "echo \"result(\\\"${dependency_name}\\\", error(${combined_error})).\" >> scryer_libs/temp/install_resp.pl"
                    fi
                else
                    flock scryer_libs/temp/install_resp.pl.lock \
                        -c "echo \"result(\\\"${dependency_name}\\\", error(${error_output})).\" >> scryer_libs/temp/install_resp.pl"
                fi
            ) &
            ;;
        path)
            (
                error_output=$(ln -rsf "${dependency_path}" "scryer_libs/packages/${dependency_name}" 2>&1 1>/dev/null)

                if [ -z "$error_output" ]; then
                    flock scryer_libs/temp/install_resp.pl.lock \
                        -c "echo \"result(\\\"${dependency_name}\\\", success).\" >> scryer_libs/temp/install_resp.pl"
                else
                    flock scryer_libs/temp/install_resp.pl.lock \
                        -c "echo \"result(\\\"${dependency_name}\\\", error(${error_output})).\" >> scryer_libs/temp/install_resp.pl"
                fi
            ) &
            ;;
        *)
            echo "Unknown dependency kind: ${dependency_kind}"
            lock scryer_libs/temp/install_resp.pl.lock \
                        -c "echo \"result(\\\"${dependency_name}\\\", error(\"Unknown dependency kind: ${dependency_kind}\").\" >> scryer_libs/temp/install_resp.pl"
            ;;
    esac
done

wait

rm -f scryer_libs/temp/install_resp.pl.lock
