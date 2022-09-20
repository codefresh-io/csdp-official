# required env variables:
# SERVICE_ACCOUNT_NAME (fieldRef)
# CSDP_TOKEN (secret)
# INGRESS_URL (cm)
# CONTEXT_NAME (cm)
# SERVER (cm)
# LABELS (cm - optional)
# ANNOTATIONS (cm - optional)
# CSDP_TOKEN_SECRET

SECRET_NAME=""

function get_service_account_secret_name() {
  SECRET_NAME=$(kubectl get ServiceAccount ${SERVICE_ACCOUNT_NAME} -n ${NAMESPACE} -o jsonpath='{.secrets[0].name}') || exit 1
  if [[ -z ${SECRET_NAME} ]]; then
    echo "Creating new ServiceAccount token"
    # create secret for service account
    SECRET_NAME=$(kubectl create -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  generateName: ${SERVICE_ACCOUNT_NAME}-token-
  annotations:
    kubernetes.io/service-account.name: ${SERVICE_ACCOUNT_NAME}
type: kubernetes.io/service-account-token
EOF
)
    SECRET_NAME=$(echo ${SECRET_NAME} | sed s@secret/@@g | sed s/\ created//g)
    kubectl patch ServiceAccount ${SERVICE_ACCOUNT_NAME} -n ${NAMESPACE} --patch "{\"secrets\": [{\"name\": \"${SECRET_NAME}\"}]}" || exit 1
    echo "Created ServiceAccount sercret ${SECRET_NAME}"
  else
    echo "Found ServiceAccount secret ${SECRET_NAME}"
  fi
}

echo "ServiceAccount: ${SERVICE_ACCOUNT_NAME}"
echo "Ingress URL: ${INGRESS_URL}"
echo "Context Name: ${CONTEXT_NAME}"
echo "Server: ${SERVER}"

# Path to ServiceAccount token
SERVICEACCOUNT=/var/run/secrets/kubernetes.io/serviceaccount

# Read this Pod's namespace
NAMESPACE=$(cat ${SERVICEACCOUNT}/namespace)

# Reference the internal certificate authority (CA)
CACERT=${SERVICEACCOUNT}/ca.crt

# get ServiceAccount token
get_service_account_secret_name || exit 1
BEARER_TOKEN=$(kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o jsonpath='{.data.token}' | base64 -d)

# write KUBE_COPNFIG_DATA to local file
CLUSTER_NAME=$(echo ${SERVER} | sed s/'http[s]\?:\/\/'//)
kubectl config set-cluster "${CLUSTER_NAME}" --server="${SERVER}" --certificate-authority="${CACERT}" || exit 1
kubectl config set-credentials "${SERVICE_ACCOUNT_NAME}" --token "${BEARER_TOKEN}" || exit 1
kubectl config set-context "${CONTEXT_NAME}" --cluster="${CLUSTER_NAME}" --user="${SERVICE_ACCOUNT_NAME}" || exit 1

KUBE_CONFIG=$(kubectl config view --minify --flatten --output json --context="${CONTEXT_NAME}") || exit 1
KUBE_CONFIG_B64=`echo -n $KUBE_CONFIG | base64 -w 0`

ANNOTATIONS_B64=$(cat /etc/config/annotations.yaml | base64 -w 0)
LABELS_B64=$(cat /etc/config/labels.yaml | base64 -w 0)

STATUS_CODE=$(curl -X POST ${INGRESS_URL%/}/app-proxy/api/clusters \
  -H 'Content-Type: application/json' \
  -H 'Authorization: '${CSDP_TOKEN}'' \
  -d '{ "name": "'${CONTEXT_NAME}'", "kubeConfig": "'${KUBE_CONFIG_B64}'", "annotations": "'${ANNOTATIONS_B64}'", "labels": "'${LABELS_B64}'" }' \
  -o response)
echo "STATUS_CODE: ${STATUS_CODE}"
cat response
echo

if [[ $STATUS_CODE == 000 ]]; then
  echo "error sending request to runtime"
  exit 1
fi

if [[ $STATUS_CODE -ge 300 ]]; then
  echo "error creating cluster in runtime"
  exit $STATUS_CODE
fi

echo "deleting token secret ${CSDP_TOKEN_SECRET}"
kubectl delete secret ${CSDP_TOKEN_SECRET} -n ${NAMESPACE} || echo "warning: failed deleting secret ${CSDP_TOKEN_SECRET}. you can safely delete this secret manually later with: kubectl delete secret ${CSDP_TOKEN_SECRET} -n ${NAMESPACE}"