#!/bin/bash

set -o pipefail
set -e

if [ $# -ne 2 ]; then
  echo "Please provide exactly two arguments."
  echo "Usage: ./checkout-test-branch.sh \$target_version \$prerelease_version_suffix"
  echo "Example: ./checkout-test-branch.sh 0.2.5 rc1"
  exit 1
fi

export TARGET_VERSION=$1
export PRE_RELEASE_VERSION_SUFFIX=$2
export PRE_RELEASE_VERSION=$TARGET_VERSION-$PRE_RELEASE_VERSION_SUFFIX
export TAG=$PRE_RELEASE_VERSION
export TEST_BRANCH=test-release-$TARGET_VERSION

git checkout main
git pull
git checkout -b "$TEST_BRANCH"

echo "$PRE_RELEASE_VERSION" > VERSION
make bump

git add .
git commit -m "testing release $TARGET_VERSION"
git push --set-upstream origin "$TEST_BRANCH"
git tag "$TAG"
git push origin tags/"$TAG"
