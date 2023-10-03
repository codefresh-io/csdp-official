FROM bitnami/minideb:bullseye

ARG VERSION="1.24"

RUN apt-get update && \
    apt-get install -y ca-certificates curl && \
    curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list && \
    apt-get update && \
    apt-get install -y kubectl="${VERSION}.*"

# curl was removed in the latest patches of bitnami/kubectl. Needs install it again.
USER root
RUN apt-get update && apt-get install -y curl 

# set back user used in bitnami/kubectl
USER 1001
WORKDIR /src

COPY add-cluster.sh .

CMD [ "./add-cluster.sh"]
ENTRYPOINT [ "bash" ]
