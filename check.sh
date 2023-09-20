if [ -z $MAKEFILE ]; then
    MAKEFILE=Makefile
fi

if [ -z $VERSION_FILED ]; then
    VERSION_FILED=PKG_VERSION
fi

if [ -z $HASH_FILED ]; then
    HASH_FILED=PKG_HASH
fi

current_version=$(cat $MAKEFILE | grep $VERSION_FILED | head -n 1 | cut -d "=" -f 2)
current_hash=$(cat $MAKEFILE | grep $HASH_FILED | head -n 1 | cut -d "=" -f 2)
echo "Current version: $current_version"

if [ -z $FROM_TAG ]; then
    latest_version=$(date +%Y%m%d%H%M%S)
    latest_version_number=$(date +%Y%m%d%H%M%S)
else
    url="https://api.github.com/repos/$REPO/releases/latest"
    jq_expr='.tag_name'
    if [ ! -z $INCLUDE_PRE_RELEASE ]; then
        url="https://api.github.com/repos/$REPO/releases?per_page=1"
        jq_expr='.[0].tag_name'
    fi
    resp=$(curl -s "$url")
    latest_version=$(echo "$resp" | jq -r $jq_expr)
    if [ $latest_version = "null" ]; then
        echo "No release found"
        exit 0
    fi

    echo "Latest version: $latest_version"
    latest_version_number=$(echo $latest_version | cut -d "v" -f 2)
    echo "Latest version number: $latest_version_number"
fi

SOURCE_URL=$(echo $SOURCE_URL | sed "s/{{version}}/$latest_version_number/g")
SOURCE_URL=$(echo $SOURCE_URL | sed "s#{{repo}}#$REPO#g")
echo $SOURCE_URL

wget $SOURCE_URL -O output
hash=$(sha256sum output | cut -d " " -f 1)
echo "New hash: $hash"
echo "Current hash: $current_hash"
rm output

if [ $current_hash = $hash ]; then
    echo "Hash not changed"
    exit 0
fi

echo "Update to $latest_version"
sed -i "s/$VERSION_FILED:=.*/$VERSION_FILED:=$latest_version_number/g" $MAKEFILE
sed -i "s/PKG_RELEASE:=.*/PKG_RELEASE:=1/g" $MAKEFILE
sed -i "s/$HASH_FILED:=.*/$HASH_FILED:=$hash/g" $MAKEFILE

git config user.name "bot"
git config user.email "bot@github.com"
git add .
if [ -z "$(git status --porcelain)" ]; then
    echo "No changes to commit"
    exit 0
fi

if [ -z $BRANCH ]; then
    BRANCH=main
fi

git commit -m "$(TZ='Asia/Shanghai' date +@%Y%m%d) Bump $REPO to $latest_version"

if [ ! -z $CREATE_PR ]; then
    PR_BRANCH="auto-update/$REPO-$latest_version"
    git push "https://x-access-token:$COMMIT_TOKEN@github.com/$GITHUB_REPOSITORY" HEAD:$PR_BRANCH
    gh pr create --title "Bump $REPO to $latest_version" --body "Bump $REPO to $latest_version" --base $BRANCH --head $PR_BRANCH
else
    git push "https://x-access-token:$COMMIT_TOKEN@github.com/$GITHUB_REPOSITORY" HEAD:$BRANCH
fi