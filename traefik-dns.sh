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
for file in ${BASE_DIR}/lib/*.sh; do
    source "${file}"
done

LOG_LEVEL=info
while test "$#" -gt 0; do
    argument=$1
    shift

    case "${argument}" in
        --selector|-l)
            LABEL_SELECTOR=$1
        ;;
        --dnsendpoint)
            DNSENDPOINT_NAME=$1
        ;;
        --loglevel)
            LOG_LEVEL=$1
        ;;
        --help)
            help
            exit
        ;;
    esac

    shift
done
info "Log level is <${LOG_LEVEL^^}>."
LOG_LEVEL_ID=$(get_log_level_id ${LOG_LEVEL})

if ! test -d /run/secrets/kubernetes.io/serviceaccount; then
    error "Missing service account information in /run/secrets/kubernetes.io/serviceaccount."
    exit 1
fi
if test -z "${LABEL_SELECTOR}"; then
    error "You must specify a label selector."
    exit 1
fi
if test -z "${DNSENDPOINT_NAME}"; then
    error "You must specify a DNSEndpoint name."
    exit 1
fi

for tool in kubectl curl jq; do
    if ! type ${tool} >/dev/null 2>&1; then
        error "I need ${tool} to work."
        exit 1
    fi
done

kubectl config set-cluster local --server=https://kubernetes --certificate-authority=/run/secrets/kubernetes.io/serviceaccount/ca.crt
kubectl config set-credentials local --token=$(cat /run/secrets/kubernetes.io/serviceaccount/token)
kubectl config set-context local --cluster=local --user=local --namespace=$(cat /run/secrets/kubernetes.io/serviceaccount/namespace)

if ! kubectl get pods >/dev/null 2>&1; then
    error "Failed to establish cluster connection."
    exit 1
fi

if ! kubectl get dnsendpoints >/dev/null 2>&1; then
    error "I need external-dns running in the cluster."
    exit 1
fi
if ! kubectl get DNSEndpoint ${DNSENDPOINT_NAME} >/dev/null 2>&1; then
    error "Specified DNSEndpoint <${DNSENDPOINT_NAME}> does not exist."
    exit 1
fi
if test "$(kubectl get DNSEndpoint ${DNSENDPOINT_NAME} -o json | jq -r '.spec.endpoints[].recordType')" != "A"; then
    error "Specified DNSEndpoint <${DNSENDPOINT_NAME}> does not manage an A record."
    exit 1
fi

function cleanup() {
    info "Cleaning up..."
    info "Goodbye!"
}
trap cleanup EXIT

event_index=0
current_pod_name=""
current_pod_state=""
candidate_pod_name=""
candidate_pod_state=""
kubectl get pods --selector ${LABEL_SELECTOR} --watch --output-watch-events --output json | \
    jq --compact-output --monochrome-output --unbuffered 'del(.object.metadata.managedFields)' | \
    while read EVENT; do
        event_type=$(echo ${EVENT} | jq --raw-output '.type')

        resource_name=$(echo ${EVENT} | k8s_event_get_type)
        resource_phase=$(echo ${EVENT} | k8s_event_get_object_name)
        if test "${resource_phase}" == "Running" && test "$(echo ${EVENT} | k8s_event_get_pod_states | wc -l)" -eq 1; then
            resource_state=$(echo ${EVENT} | k8s_event_get_pod_states)
        fi

        debug "Got event ${event_index} with type=${event_type}, resource_name=${resource_name}, resource_state=${resource_state}."

        case "${event_type}" in
            ADDED)
                if test -z "${current_pod_name}"; then
                    current_pod_name=${resource_name}
                    current_pod_state=${resource_state}
                    info "Following pod ${current_pod_name} (${current_pod_state})."
                    followed_pod_updated "${LABEL_SELECTOR}" "${current_pod_name}"

                elif test "${resource_name}" == "${current_pod_name}"; then
                    current_pod_state=${resource_state}
                    debug "New state for current pod ${current_pod_name} (${current_pod_state})."

                elif test -z "${candidate_pod_name}"; then
                    candidate_pod_name=${resource_name}
                    candidate_pod_state=${resource_state}
                    info "Following candidate pod ${candidate_pod_name} (${candidate_pod_state})."

                elif test "${resource_name}" == "${candidate_pod_name}"; then
                    candidate_pod_state=${resource_state}
                    debug "New state for candidate pod ${candidate_pod_name} (${candidate_pod_state})."

                else
                    error "Ignoring unhandled event."
                fi
            ;;
            MODIFIED)
                if test "${resource_name}" == "${current_pod_name}"; then
                    current_pod_state=${resource_state}
                    debug "New state for current pod ${current_pod_name} (${current_pod_state})."

                elif test "${resource_name}" == "${candidate_pod_name}"; then
                    candidate_pod_state=${resource_state}
                    debug "New state for candidate pod ${candidate_pod_name} (${candidate_pod_state})."

                else
                    error "Ignoring unhandled event."
                fi
            ;;
            DELETED)
                if test "${resource_name}" == "${current_pod_name}"; then
                    debug "Processing deletion for current pod ${current_pod_name}."
                    if test -n "${candidate_pod_name}"; then
                        current_pod_name=${candidate_pod_name}
                        current_pod_state=${candidate_pod_state}
                        info "Switching to candidate pod ${candidate_pod_name} (${candidate_pod_state})."
                        followed_pod_updated "${LABEL_SELECTOR}" "${current_pod_name}"

                    else
                        debug "No candidate evailable. Unable to switch."
                    fi
                fi
            ;;
        esac

        debug "Done with event."

        event_index=$((event_index + 1))
    done