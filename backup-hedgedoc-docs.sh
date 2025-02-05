#! /bin/bash

set -eo pipefail

git clone https://gitlab.tiker.net/inducer/hedgedoc-cli.git hedgedoc-cli
CLICMD=$(pwd)/hedgedoc-cli/bin/codimd

git clone "$CI_REPOSITORY_URL" hedgedoc-backup-subrepo
cd hedgedoc-backup-subrepo
git checkout "$CI_DEFAULT_BRANCH"

SECONDS_SINCE_LAST_COMMIT=$((git show HEAD --format=%cI -s && date --iso-8601=seconds) | python3 -c 'import sys; import datetime as dt; fromiso=dt.datetime.fromisoformat; s=fromiso(sys.stdin.readline().strip()); e=fromiso(sys.stdin.readline().strip()); print(int((e-s).total_seconds()))')

if (( SECONDS_SINCE_LAST_COMMIT < 10*60 )); then
    echo "last commit is too recent, aborting."
    exit
fi

# Do not change this env var name! The CLI expects it to be this and nothing else
export CODIMD_SERVER='https://notes.tiker.net'
$CLICMD login --email inform+codibackup@tiker.net "$CODIMD_PASSWORD"

BACKUP_DOC_LIST=.hedgedoc-backup.txt
if ! test -f $BACKUP_DOC_LIST && test -f .codimd-backup.txt; then
    BACKUP_DOC_LIST=.codimd-backup.txt
fi

# read will not return the last line if there isn't a newline :facepalm:
DONE=false
until $DONE; do
    DOCID=""
    read -r DOCID FILEPATH || DONE=true
    if test "$DOCID" != ""; then
        echo "Reading note $DOCID into $FILEPATH"
        {
                echo "**DO NOT EDIT**"
                echo "This file will be automatically overwritten. "
                echo "Instead, edit the file at ${CODIMD_SERVER}/${DOCID} "
                echo "**DO NOT EDIT**"
                echo ""
                $CLICMD export --md "$DOCID" "-"
        } > "$FILEPATH"
        git add "$FILEPATH"
    fi
done < "$BACKUP_DOC_LIST"

if [[ `git status --porcelain --untracked-files=no ` ]]; then
    # There are changes in the index
    eval $(ssh-agent)
    trap "kill $SSH_AGENT_PID" EXIT
    echo "${CODIMD_BACKUP_PUSH_KEY}" > id_hedgedoc_backup_push
    chmod 600 id_hedgedoc_backup_push
    ssh-add id_hedgedoc_backup_push
    git config --global user.name "HedgeDoc backup service"
    git config --global user.email "inform@tiker.net"
    git commit -m "Automatic update from HedgeDoc: $(date)"
    mkdir -p ~/.ssh
    echo -e "Host gitlab.tiker.net\n\tStrictHostKeyChecking no\n" >> ~/.ssh/config
    git push git@gitlab.tiker.net:${CI_PROJECT_PATH}.git "$CI_DEFAULT_BRANCH"
fi

# vim: sw=4
