FROM bitnami/kubectl:1.24

# curl was removed in the latest patches of bitnami/kubectl. Needs install it again.
USER root
RUN apt-get update && apt-get install -y curl 

# set back user used in bitnami/kubectl
USER 1001
WORKDIR /src

COPY add-cluster.sh .

CMD [ "./add-cluster.sh" ]

ENTRYPOINT [ "bash" ]
