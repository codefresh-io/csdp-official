export TARGET_VERSION=0.1.30
export PRE_RELEASE_VERSION=$TARGET_VERSION-0
export TAG=$PRE_RELEASE_VERSION
export TEST_BRANCH=test-release-$TARGET_VERSION

git checkout -b $TEST_BRANCH

echo $PRE_RELEASE_VERSION > VERSION
make bump

git add .
git commit -m "testing release $TARGET_VERSION"
git push --set-upstream origin $TEST_BRANCH
git tag "$TAG"
git push origin tags/$TAG
