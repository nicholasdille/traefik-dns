#!/bin/bash

if test "$0" == "-bash"; then
    echo
    echo "ATTENTION: You attempted to source this script."
    echo "           Please press Ctrl-C to interrupt."
    echo "           You have 10 seconds."
    echo
    for i in $(seq 1 1 10); do
        echo -ne "\r$((10 - $i))"
        sleep 1
    done
fi

BASE_DIR=$(dirname $(readlink -f "$0"))

for file in "${BASE_DIR}/lib/*"; do
    source "${file}"
done

while test "$#" -gt 0; do
    argument=$1
    shift

    case "${argument}" in
        --context|-c)
            CONTEXT=$1
        ;;
        --namespace|-n)
            NAMESPACE=$1
        ;;
        --selector|-l)
            LABEL_SELECTOR=$1
        ;;
        --dnsendpoint)
            DNSENDPOINT_NAME=$1
        ;;
        --loglevel)
            LOGLEVEL=$1
            # TODO: Implement log levels
            echo "INFO: Argument loglevel is not implemented yet. Will default to debug for now."
        ;;
        --help)
            help
            exit
        ;;
    esac

    shift
done

if test -f .env; then
    source .env
fi

if test -z "${KUBECONFIG}" && ! test -f "${HOME}/.kube/config" && ! test -d /run/secrets/kubernetes.io/serviceaccount/; then
    echo "ERROR: You must provide a connection to a Kubernetes cluster in either of the following ways:"
    echo "       1. The file ${HOME}/.kube/config must exist"
    echo "       2. The environment variable KUBECONFIG is set"
    echo "       3. The parameter --kubeconfig is specified"
    echo "       4. The directory /run/secrets/kubernetes.io/serviceaccount is populated"
    exit 1
fi
if test -z "${NAMESPACE}"; then
    echo "ERROR: You must specify a namespace."
    exit 1
fi
if test -n "${LABEL_SELECTOR}"; then
    echo "ERROR: You must specify a label selector."
    exit 1
fi
if test -n "${DNSENDPOINT_NAME}"; then
    echo "ERROR: You must specify a DNSEndpoint name."
    exit 1
fi

for tool in kubectl curl jq; do
    if ! type ${tool} >/dev/null 2>&1; then
        echo "ERROR: I need ${tool} to work."
        exit 1
    fi
done

# TODO: Create kubeconfig

if ! kubectl get crd dnsendpoints.externaldns.k8s.io >/dev/null 2>&1; then
    echo "ERROR: I need external-dns running in the cluster."
    exit 1
fi

# TODO: Test for specified DNSEndpoint
# TODO: Check if DNSEndpoint managed an A record

function cleanup() {
    echo "INFO: Cleaning up..."
    echo "INFO: Goodbye!"
}
trap cleanup EXIT

current_pod_name=""
current_pod_state=""
candidate_pod_name=""
candidate_pod_state=""
kubectl --context ${CONTEXT} --namespace ${NAMESPACE} get pods --selector ${LABEL_SELECTOR} --watch --output-watch-events --output json | \
    while read EVENT; do
        event_type=$(echo ${EVENT} | jq --raw-output '.type')

        resource_name=$(echo ${EVENT} | jq --raw-output '.object.metadata.name')
        resource_phase=$(echo ${EVENT} | jq --raw-output '.object.status.phase')
        if test "${resource_phase}" == "Running" && test "$(echo ${EVENT} | jq --raw-output '.object.status.containerStatuses[].state | to_entries[].key' | uniq | wc -l)" -eq 1; then
            resource_state=$(echo ${EVENT} | jq --raw-output '.object.status.containerStatuses[].state | to_entries[].key' | uniq)
        fi

        echo "Debug: Got event with type=${event_type}, resource_name=${resource_name}, resource_state=${resource_state}."

        case "${event_type}" in
            ADDED)
                if test -z "${current_pod_name}"; then
                    current_pod_name=${resource_name}
                    current_pod_state=${resource_state}
                    echo "DEBUG: Following pod ${current_pod_name} (${current_pod_state})."

                elif test "${resource_name}" == "${current_pod_name}"; then
                    current_pod_state=${resource_state}
                    echo "DEBUG: New state for current pod ${current_pod_name} (${current_pod_state})."

                elif test -z "${candidate_pod_name}"; then
                    candidate_pod_name=${resource_name}
                    candidate_pod_state=${resource_state}
                    echo "DEBUG: Following candidate pod ${candidate_pod_name} (${candidate_pod_state})."

                elif test "${resource_name}" == "${candidate_pod_name}"; then
                    candidate_pod_state=${resource_state}
                    echo "DEBUG: New state for candidate pod ${candidate_pod_name} (${candidate_pod_state})."
                fi
            ;;
            MODIFIED)
                if test "${resource_name}" == "${current_pod_name}"; then
                    current_pod_state=${resource_state}
                    echo "DEBUG: New state for current pod ${current_pod_name} (${current_pod_state})."

                elif test "${resource_name}" == "${candidate_pod_name}"; then
                    candidate_pod_state=${resource_state}
                    echo "DEBUG: New state for candidate pod ${candidate_pod_name} (${candidate_pod_state})."
                fi
            ;;
            DELETED)
                if test "${resource_name}" == "${current_pod_name}"; then
                    echo "DEBUG: Processing deletion for current pod ${current_pod_name}."
                    if test -n "${candidate_pod_name}"; then
                        current_pod_name=${candidate_pod_name}
                        current_pod_state=${candidate_pod_state}
                        echo "DEBUG: Switching to candidate pod ${candidate_pod_name} (${candidate_pod_state})."

                    else
                        echo "DEBUG: No candidate evailable. Unable to switch."
                    fi
                fi
            ;;
        esac

        echo "DEBUG: Done with event."
    done