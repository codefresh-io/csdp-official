FROM bitnami/minideb:bullseye

ARG VERSION="1.24"

RUN apt-get update && \
    apt-get install -y ca-certificates curl && \
    curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list && \
    apt-get update && \
    apt-get install -y kubectl="${VERSION}.*"

WORKDIR /src

COPY add-cluster.sh .

CMD [ "./add-cluster.sh"]
ENTRYPOINT [ "bash" ]
