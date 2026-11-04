FROM alpine/kubectl:1.37.2

# curl was removed in the latest patches of bitnami/kubectl. Needs install it again.
USER root
RUN apk --no-cache update && apk --no-cache add bash curl 

# set back user used in bitnami/kubectl
USER 1001
WORKDIR /src

COPY add-cluster.sh .

CMD [ "./add-cluster.sh" ]

ENTRYPOINT [ "bash" ]
