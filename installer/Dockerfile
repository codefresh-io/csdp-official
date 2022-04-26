FROM alpine:3.15 as base

WORKDIR /go/src/github.com/codefresh-io/cli-v2

RUN apk -U add --no-cache git curl yq jq bash ca-certificates && update-ca-certificates

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
RUN install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install argocd cli
RUN curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
RUN chmod +x /usr/local/bin/argocd

WORKDIR /src

COPY install.sh .

CMD [ "./install.sh" ]

ENTRYPOINT [ "bash" ]
