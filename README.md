# csdp-official-poc

# publish new chart using https://github.com/helm/chart-releaser

1. merge from main branch
2. make sure chart version is updated
3. export these vars:
```
  export CR_PACKAGE_PATH=.
  export CR_OWNER=codefresh-io
  export CR_GIT_REPO=csdp-official-poc
  export CR_TOKEN=<GIT_TOKEN>
```
4. run:
```bash
  cr package ./helm

  cr upload --skip-existing

  cr index -i ./index.yaml

  git add . && git commit -am "updated index" && git push
```
