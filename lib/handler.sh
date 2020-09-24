function followed_pod_updated() {
    local context=$1
    local namespace=$2
    local selector=$3
    local name=$4

    kubectl --context="${context}" --namespace="${namespace}" get pod ${name}
}