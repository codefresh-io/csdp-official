#!/bin/bash

set -e
set -o pipefail

check_required_param() {
    PARAM_NAME="$1"
    PARAM_VAL="$2"
    if [[ -z "${PARAM_VAL}" ]]; then
        echo "missing parameter: '${PARAM_NAME}'"
        exit 1
    fi
}

# Constants:
CODEFRESH_SECRET_NAME="codefresh-token"
CODEFRESH_CM_NAME="codefresh-cm"
REPO_CREDS_SECRET_NAME="autopilot-secret"
ARGOCD_TOKEN_SECRET_NAME="argocd-token"
ARGOCD_INITIAL_TOKEN_SECRET_NAME="argocd-initial-admin-secret"
BOOTSTRAP_APP_NAME="csdp-bootstrap"
ADDITIONAL_COMPONENTS_MANAGED="\nevents-reporter"
ADDITIONAL_COMPONENTS="\nevents-reporter\nrollout-reporter\nworkflow-reporter"
RUNTIME_DEF_URL="https://github.com/codefresh-io/csdp-official-poc/releases/VERSION/download/runtime.yaml"

# Params:
check_required_param "namespace" "${NAMESPACE}"
check_required_param "csdp token" "${CSDP_TOKEN}"
check_required_param "runtime repo" "${CSDP_RUNTIME_REPO}"
check_required_param "git token" "${CSDP_RUNTIME_GIT_TOKEN}"
check_required_param "runtime cluster" "${CSDP_RUNTIME_CLUSTER}"
check_required_param "runtime ingress url" "${CSDP_RUNTIME_INGRESS_URL}"
check_required_param "runtime name" "${CSDP_RUNTIME_NAME}"

# Defaults:
CSDP_URL="${CSDP_URL:-https://g.codefresh.io}"
CSDP_RUNTIME_VERSION="${CSDP_RUNTIME_VERSION:-latest}"
CSDP_GIT_INTEGRATION_PROVIDER="${CSDP_GIT_INTEGRATION_PROVIDER:-GITHUB}"
CSDP_GIT_INTEGRATION_API_URL="${CSDP_GIT_INTEGRATION_API_URL:-https://api.github.com}"
CSDP_GIT_INTEGRATION_TOKEN="${CSDP_GIT_INTEGRATION_TOKEN:-${CSDP_RUNTIME_GIT_TOKEN}}"
CSDP_RUNTIME_REPO_PATH="${CSDP_RUNTIME_REPO_PATH:-runtimes/${CSDP_RUNTIME_NAME}/bootstrap}"
CSDP_RUNTIME_REPO_CREDS_PATTERN=`echo ${CSDP_RUNTIME_REPO} | grep --color=never -E -o '^http[s]?:\/\/([a-zA-Z0-9\.]*)'`
CSDP_MANAGED_RUNTIME="${CSDP_MANAGED_RUNTIME:-false}"

create_codefresh_secret() {
    # Download runtime definition
    RUNTIME_DEF_URL=`echo "${RUNTIME_DEF_URL}" | sed s/VERSION/${CSDP_RUNTIME_VERSION}/g`

    echo "  --> Downloading runtime definition..."
    echo "  --> curl -f -L ${RUNTIME_DEF_URL}"
    RUNTIME_DEF=$(curl -SsfL "$RUNTIME_DEF_URL")
    RESOLVED_RUNTIME_VERSION=`echo "$RUNTIME_DEF" | yq e '.spec.version' -`
    echo "  --> Resolved runtime version: ${RESOLVED_RUNTIME_VERSION}"
    echo ""

    # Prepare components for request

    if [[ "$CSDP_MANAGED_RUNTIME" == "true" ]] ; then
        ADDITIONAL_COMPONENTS=${ADDITIONAL_COMPONENTS_MANAGED}
    fi
    COMPONENT_NAMES=`echo "$RUNTIME_DEF" | yq e '.spec.components.[].name' -`
    COMPONENT_NAMES=`printf "${COMPONENT_NAMES}${ADDITIONAL_COMPONENTS}" | tr '\n' ' '`
    COMPONENTS="[\"csdp-argo-cd\""
    for COMPONENT in $COMPONENT_NAMES
    do
        CUR_COMPONENT=`echo -n "\"csdp-${COMPONENT}\""`
        COMPONENTS="${COMPONENTS},${CUR_COMPONENT}"
    done
    COMPONENTS="${COMPONENTS}]"

    RUNTIME_CREATE_ARGS="{
        \"repo\": \"${CSDP_RUNTIME_REPO}\",
        \"runtimeName\":\"${CSDP_RUNTIME_NAME}\",
        \"cluster\":\"${CSDP_RUNTIME_CLUSTER}\",
        \"ingressHost\":\"${CSDP_RUNTIME_INGRESS_URL}\",
        \"ingressClass\":\"${CSDP_INGRESS_CLASS_NAME}\",
        \"ingressController\":\"${CSDP_INGRESS_CONTROLLER}\",
        \"componentNames\":${COMPONENTS},
        \"runtimeVersion\":\"${RESOLVED_RUNTIME_VERSION}\"
    }"

    RUNTIME_CREATE_DATA="{\"operationName\":\"CreateRuntime\",\"variables\":{\"args\":$RUNTIME_CREATE_ARGS}"
    RUNTIME_CREATE_DATA+=$',"query":"mutation CreateRuntime($args: RuntimeInstallationArgs\u0021) {\\n  createRuntime(installationArgs: $args) {\\n    name\\n    newAccessToken\\n  }\\n}\\n"}'
    echo "  --> Creating runtime with args:"
    echo "$RUNTIME_CREATE_ARGS"

    RUNTIME_CREATE_RESPONSE=`curl "${CSDP_URL}/2.0/api/graphql" \
    -SsfL \
    -H "Authorization: ${CSDP_TOKEN}" \
    -H 'content-type: application/json' \
    --compressed \
    --insecure \
    --data-raw "$RUNTIME_CREATE_DATA"`

    if `echo "$RUNTIME_CREATE_RESPONSE" | jq -e 'has("errors")'`; then
        echo "Failed to create runtime"
        echo ${RUNTIME_CREATE_RESPONSE}
        exit 1
    fi

    RUNTIME_ACCESS_TOKEN=`echo $RUNTIME_CREATE_RESPONSE | jq '.data.createRuntime.newAccessToken'`
    RUNTIME_ENCRYPTION_IV=`hexdump -n 16 -e '4/4 "%08x" 1 "\n"' /dev/urandom`
    echo "  --> Runtime created!"
    echo ""

    echo "  --> Creating $CODEFRESH_SECRET_NAME secret..."
    echo "
    apiVersion: v1
    kind: Secret
    metadata:
        name: $CODEFRESH_SECRET_NAME
        namespace: $NAMESPACE
    stringData:
        token: $RUNTIME_ACCESS_TOKEN
        encryptionIV: $RUNTIME_ENCRYPTION_IV
    " | kubectl apply -f -

    if kubectl -n "$NAMESPACE" get secret -l io.codefresh.integration-type=git -l io.codefresh.integration-name=default 2>&1 | grep "No resources found"; then
        echo ""
    else
        echo "  --> Found old git integration, deleteing because the data inside cannot be decrypted anymore..."
        kubectl -n "$NAMESPACE" delete secret -l io.codefresh.integration-type=git -l io.codefresh.integration-name=default
    fi
}

create_bootstrap_application() {
    echo "  --> Creating $BOOTSTRAP_APP_NAME application..."
    echo "
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
        labels:
            app.kubernetes.io/name: ${BOOTSTRAP_APP_NAME}
            codefresh.io/internal: \"true\"
        name: ${BOOTSTRAP_APP_NAME}
        namespace: ${NAMESPACE}
        finalizers:
          - 'resources-finalizer.argocd.argoproj.io'
    spec:
        project: default
        destination:
            namespace: ${NAMESPACE}
            server: https://kubernetes.default.svc
        ignoreDifferences:
            - group: argoproj.io
              kind: Application
              jsonPointers:
                - /status
        source:
            path: ${CSDP_RUNTIME_REPO_PATH}
            repoURL: ${CSDP_RUNTIME_REPO}
            targetRevision: HEAD
        syncPolicy:
            automated:
                allowEmpty: true
                prune: true
                selfHeal: true
            syncOptions:
              - allowEmpty=true
    " | kubectl apply -f -
}

create_repo_creds_secret() {
    echo "  --> Creating $REPO_CREDS_SECRET_NAME secret..."
    echo "
    apiVersion: v1
    kind: Secret
    metadata:
        labels:
            argocd.argoproj.io/secret-type: repo-creds
        name: $REPO_CREDS_SECRET_NAME
        namespace: $NAMESPACE
    stringData:
        type: git
        url: $CSDP_RUNTIME_REPO_CREDS_PATTERN
        password: $CSDP_RUNTIME_GIT_TOKEN
        username: username
    " | kubectl apply -f -
}

create_managed_repo_creds_secret() {
    echo " --> Creating managed repo credentials secret"
    echo "
    apiVersion: v1
    kind: Secret
    metadata:
        labels:
            argocd.argoproj.io/secret-type: repository
        name: $REPO_CREDS_SECRET_NAME
        namespace: $NAMESPACE
    stringData:
        type: git
        url: $CSDP_RUNTIME_REPO
        password: $CSDP_RUNTIME_GIT_TOKEN
        username: username
    " | kubectl apply -f -
}

create_argocd_token_secret() {
    echo "  --> Reading ArgoCD intial admin token..."
    INITIAL_PASSWORD=`kubectl -n ${NAMESPACE} get secret ${ARGOCD_INITIAL_TOKEN_SECRET_NAME} -o=jsonpath="{.data.password}" | base64 -d`
    echo ""

    echo "  --> Running ArgoCD login..."
    argocd login argocd-server --plaintext --username admin --password $INITIAL_PASSWORD
    echo ""

    echo "  --> Generating ArgoCD API Key..."
    ARGOCD_API_KEY=`argocd account generate-token -a admin --server argocd-server --plaintext`
    echo ""

    echo "  --> Creating $REPO_CREDS_SECRET_NAME secret..."
    echo "
    apiVersion: v1
    kind: Secret
    metadata:
        name: $ARGOCD_TOKEN_SECRET_NAME
        namespace: $NAMESPACE
    stringData:
        token: $ARGOCD_API_KEY
    " | kubectl apply -f -
    echo ""
}

create_git_integration() {
    GIT_INTEGRATION_CREATE_ARGS="{
        \"name\": \"default\",
        \"provider\":\"${CSDP_GIT_INTEGRATION_PROVIDER}\",
        \"apiUrl\":\"${CSDP_GIT_INTEGRATION_API_URL}\",
        \"sharingPolicy\":\"ALL_USERS_IN_ACCOUNT\"
    }"

    GIT_INTEGRATION_CREATE_DATA="{\"operationName\":\"AddGitIntegration\",\"variables\":{\"args\":$GIT_INTEGRATION_CREATE_ARGS}"
    GIT_INTEGRATION_CREATE_DATA+=$',"query":"mutation AddGitIntegration($args: AddGitIntegrationArgs\u0021) {\\n  addGitIntegration(args: $args) {\\n    name\\n   }\\n}\\n"}'
    
    echo "  --> Creating default git integration with args:"
    echo "$GIT_INTEGRATION_CREATE_ARGS"

    GIT_INTEGRATION_CREATE_RESPONSE=`curl "${CSDP_RUNTIME_INGRESS_URL}/app-proxy/api/graphql" \
    -SsfL \
    -H "Authorization: ${CSDP_TOKEN}" \
    -H 'content-type: application/json' \
    --compressed \
    --insecure \
    --data-raw "$GIT_INTEGRATION_CREATE_DATA"`

    echo "  --> Created git integration:"
    echo "${GIT_INTEGRATION_CREATE_RESPONSE}"
    echo ""
}

register_to_git_integration() {
    echo "  --> Registering user to default git integration"

    GIT_INTEGRATION_REGISTER_ARGS="{
        \"name\": \"default\",
        \"token\":\"${CSDP_GIT_INTEGRATION_TOKEN}\"
    }"

    GIT_INTEGRATION_REGISTER_DATA="{\"operationName\":\"RegisterToGitIntegration\",\"variables\":{\"args\":$GIT_INTEGRATION_REGISTER_ARGS}"
    GIT_INTEGRATION_REGISTER_DATA+=$',"query":"mutation RegisterToGitIntegration($args: RegisterToGitIntegrationArgs\u0021) {\\n  registerToGitIntegration(args: $args) {\\n    name\\n   }\\n}\\n"}'
    
    GIT_INTEGRATION_REGISTER_RESPONSE=`curl "${CSDP_RUNTIME_INGRESS_URL}/app-proxy/api/graphql" \
    -SsfL \
    -H "Authorization: ${CSDP_TOKEN}" \
    -H 'content-type: application/json' \
    --compressed \
    --insecure \
    --data-raw "$GIT_INTEGRATION_REGISTER_DATA"`

    if `echo "$GIT_INTEGRATION_REGISTER_RESPONSE" | jq -e 'has("errors")'`; then
        echo "Failed to register git integration"
        echo ${GIT_INTEGRATION_REGISTER_RESPONSE}
        exit 1
    fi

    echo "  --> Registered to default git integration:"
    echo "${GIT_INTEGRATION_REGISTER_RESPONSE}"
    echo "" 
}

#
# Start here:
#

# Print param values
echo "#######################################"
echo "#        Starting with options:       #"
echo "#######################################"
echo "  namespace: ${NAMESPACE}"
echo "  csdp url: ${CSDP_URL}"
echo "  csdp token: ****"
echo "  runtime repo: ${CSDP_RUNTIME_REPO}"
echo "  runtime repo path: ${CSDP_RUNTIME_REPO_PATH}"
echo "  runtime repo creds pattern: ${CSDP_RUNTIME_REPO_CREDS_PATTERN}"
echo "  runtime git-token: ****"
echo "  runtime cluster: ${CSDP_RUNTIME_CLUSTER}"
echo "  runtime name: ${CSDP_RUNTIME_NAME}"
echo "  runtime version: ${CSDP_RUNTIME_VERSION}"
echo "  managed runtime: ${CSDP_MANAGED_RUNTIME}"
echo "  runtime ingress: ${CSDP_RUNTIME_INGRESS_URL}"
echo "  ingress class name: ${CSDP_INGRESS_CLASS_NAME}"
echo "  ingress controller: ${CSDP_INGRESS_CONTROLLER}"
echo "#######################################"
echo ""

# 1. Check codefresh secret
echo "Checking secret $CODEFRESH_SECRET_NAME..."
if kubectl -n "$NAMESPACE" get secret "$CODEFRESH_SECRET_NAME"; then
    echo "  --> Secret $CODEFRESH_SECRET_NAME exists"
else
    echo "  --> Secret $CODEFRESH_SECRET_NAME doesn't exists."
    echo ""
    create_codefresh_secret
fi
echo ""
echo ""

# 2. Check repo creds secret
echo "Checking secret $REPO_CREDS_SECRET_NAME..."
if kubectl -n "$NAMESPACE" get secret "$REPO_CREDS_SECRET_NAME"; then
    echo "  --> Secret $REPO_CREDS_SECRET_NAME exists"
else
    echo "  --> Secret $REPO_CREDS_SECRET_NAME doesn't exists."
    echo ""

    if [[ "$CSDP_MANAGED_RUNTIME" == "true" ]] ; then
        create_managed_repo_creds_secret
    else
        create_repo_creds_secret
    fi
fi
echo ""
echo ""

create_argocd_token_secret
echo ""
echo ""

# 4. Check bootstrap application
echo "Checking application $BOOTSTRAP_APP_NAME..."
if kubectl -n "$NAMESPACE" get application "$BOOTSTRAP_APP_NAME"; then
    echo "  --> Application $BOOTSTRAP_APP_NAME exists"
else
    echo "  --> Application $BOOTSTRAP_APP_NAME doesn't exists."
    echo ""
    create_bootstrap_application
fi
echo ""

# 5. Check git integration
echo "Checking default git integration..."
echo "Checking application $BOOTSTRAP_APP_NAME..."
if kubectl -n "$NAMESPACE" get secret -l io.codefresh.integration-type=git -l io.codefresh.integration-name=default 2>&1 | grep "No resources found"; then
    echo "  --> Default git integration doesn't exists."
    echo ""
    create_git_integration
else
    echo "  --> Default git integration exists"
fi

# 6. Register to git integration
if [[ "$CSDP_MANAGED_RUNTIME" == "true" ]] ; then
    register_to_git_integration
fi
echo ""

echo "Done!"
