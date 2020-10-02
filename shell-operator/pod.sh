#!/usr/bin/env bash

if test -z "${NAMESPACE}"; then
    echo "ERROR: Must provide environment variable NAMESPACE."
    exit 1
fi
if test -z "${SELECTOR}"; then
    echo "ERROR: Must provide environment variable SELECTOR."
    exit 1
fi

if [[ $1 == "--config" ]] ; then
    cat <<EOF
configVersion: v1
kubernetes:
- apiVersion: v1
  kind: Pod
  executeHookOnEvent:
  - Added
  - Modified
  - Deleted
  labelSelector:
    matchLabels: {${SELECTOR}}
  namespace:
    nameSelector:
      matchNames:
      - ${NAMESPACE}
EOF

else
    tmpfile=$(mktemp)
    cp ${BINDING_CONTEXT_PATH} ${tmpfile}
    echo "### file=${tmpfile}."

    printenv

    object_count=$(jq --raw-output --compact-output 'length' ${BINDING_CONTEXT_PATH})
    if test -z "${object_count}"; then
        echo "ERROR: Failed to retrieve object count."
        exit 1
    fi
    echo "### object_count=${object_count}."
    for object_index in $(seq 0 1 $((${object_count}-1))); do
        echo "### object_index=${object_index}."

        type=$(jq --raw-output --compact-output --arg i ${object_index} '.[$i | tonumber].type' ${BINDING_CONTEXT_PATH})
        echo "### type=${type}."

        case "${type}" in
            Synchronization)
                sync_object_count=$(jq --raw-output --compact-output --arg i ${object_index} '.[$i | tonumber].objects | length' ${BINDING_CONTEXT_PATH})
                if test -z "${sync_object_count}"; then
                    echo "ERROR: Failed to retrieve sync object count."
                    exit 1
                fi
                echo "### sync_object_count=${sync_object_count}."
                for sync_object_index in $(seq 0 1 $((${sync_object_count}-1))); do
                    name=$(jq --raw-output --compact-output --arg i ${object_index} --arg j ${sync_object_index} '.[$i | tonumber].objects[$j | tonumber].object.metadata.name' ${BINDING_CONTEXT_PATH})
                    echo "### name=${name}."
                done
            ;;
            Event)
                watchEvent=$(jq --raw-output --compact-output --arg i ${object_index} '.[$i | tonumber].watchEvent' ${BINDING_CONTEXT_PATH})
                echo "### watchEvent=${watchEvent}."

                name=$(jq --raw-output --compact-output --arg i ${object_index} '.[$i | tonumber].object.metadata.name' ${BINDING_CONTEXT_PATH})
                echo "### name=${name}."
            ;;
            *)
                echo "ERROR: Unknown type <${type}>."
                exit 1
            ;;
        esac
        echo "### done with object"
    done
    echo "### done with call"

fi