#!/bin/bash
set -e

source ./.ci/util.sh

if [[ -z $1 ]]; then
  echo "release number is not set"
  echo "usage: .ci/update-github-page.sh {release number}"
  exit 1
fi
TARGET_VERSION=$1
echo TARGET_VERSION="$TARGET_VERSION"

checkForVariable "GITHUB_TOKEN"
checkForVariable "BUILDER_GITHUB_TOKEN"

checkout_from https://github.com/checkstyle/contribution

cd .ci-temp/contribution/releasenotes-builder
mvn -e --no-transfer-progress clean compile package
cd ../../../

if [ -d .ci-temp/checkstyle ]; then
  cd .ci-temp/checkstyle/
  git reset --hard origin/master
  git pull origin master
  git fetch --tags
  cd ../../
else
  cd .ci-temp/
  git clone https://github.com/checkstyle/checkstyle
  cd ../
fi

cd .ci-temp/checkstyle

curl \
 https://api.github.com/repos/checkstyle/checkstyle/releases \
 -H "Authorization: token $GITHUB_TOKEN" \
 -o /var/tmp/cs-releases.json

TARGET_RELEASE_INDEX=$(jq -r --arg tagname "checkstyle-$TARGET_VERSION" \
               'to_entries[] | select(.value.tag_name == $tagname).key' /var/tmp/cs-releases.json)
echo TARGET_RELEASE_INDEX="$TARGET_RELEASE_INDEX"

PREVIOUS_RELEASE_INDEX=$(($TARGET_RELEASE_INDEX+1))
echo PREVIOUS_RELEASE_INDEX="$PREVIOUS_RELEASE_INDEX"

END_REF=$(cat /var/tmp/cs-releases.json | jq -r ".[$TARGET_RELEASE_INDEX].tag_name")
START_REF=$(cat /var/tmp/cs-releases.json | jq -r ".[$PREVIOUS_RELEASE_INDEX].tag_name")

echo START_REF="$START_REF"
echo END_REF="$END_REF"

cd ../

BUILDER_RESOURCE_DIR="contribution/releasenotes-builder/src/main/resources/com/github/checkstyle"

java -jar contribution/releasenotes-builder/target/releasenotes-builder-1.0-all.jar \
     -localRepoPath checkstyle \
     -remoteRepoPath checkstyle/checkstyle \
     -startRef "$START_REF" \
     -endRef "$END_REF" \
     -releaseNumber "$TARGET_VERSION" \
     -githubAuthToken "$BUILDER_GITHUB_TOKEN" \
     -generateGitHub \
     -gitHubTemplate $BUILDER_RESOURCE_DIR/templates/github_post.template

echo ==============================================
echo "GITHUB PAGE:"
echo ==============================================
CONTENT=$(cat github_post.txt)
echo "$CONTENT"

echo 'Updating content to be be json value friendly'
UPDATED_CONTENT=$(awk '{printf "%s\\n", $0}' github_post.txt |  sed "s/\`/'/g")
echo "$UPDATED_CONTENT"

RELEASE_ID=$(cat /var/tmp/cs-releases.json | jq -r ".[$TARGET_RELEASE_INDEX].id")
echo RELEASE_ID="$RELEASE_ID"

JSON=$(cat <<EOF
{
"tag_name": "checkstyle-${TARGET_VERSION}",
"body": "${UPDATED_CONTENT}"
}
EOF
)
echo "$JSON"

echo "Updating Github tag page"
curl \
  -X PATCH https://api.github.com/repos/checkstyle/checkstyle/releases/"$RELEASE_ID" \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: token $GITHUB_TOKEN" \
  -d "${JSON}"
