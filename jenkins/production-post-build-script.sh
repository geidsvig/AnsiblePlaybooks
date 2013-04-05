#!/bin/bash

#
# This bash file handles all production (release branch) Jenkins post-build actions for SBT dist projects.
#
# To have Jenkins correctly handle this task, use the AnsiblePlaybooks project directory created by the Jenkins job.
#     http://jenkins.serverhost.com:8080/job/AnsiblePlaybooks/
# This creates a most recent workspace of the ansible project at:
#     /ebs1/opt/jenkins/jobs/AnsiblePlaybooks/workspace/
# Then set the Jenkins job that will use the AnsiblePlaybook project to have it's "Post-build Actions" as
#     cd /ebs1/opt/jenkins/jobs/AnsiblePlaybooks/workspace/
#     ./jenkins/production-post-build-script.sh <product> <project> <build-number>
# example:
#     ./jenkins/production-post-build-script.sh hootbomb hermes $buildversion
#
#
# $1 product name
# $2 project name
# $3 version number

PRODUCT="$1"
PROJECT="$2"
VERSION="$3"

DOCS_DIR="/var/www/docs/$PRODUCT/$PROJECT/prod"
ARTIFACT_DIR="/ebs1/www/artifacts/$PRODUCT/$PROJECT/stg"
ARCHIVE_DIR="/ebs1/www/artifacts/$PRODUCT/$PROJECT/prod"

function archive {
  if [ ! -e $ARCHIVE_DIR ]; then
    mkdir -p $ARCHIVE_DIR
  fi
  
  cp "$ARTIFACT_DIR"/$PRODUCT-$PROJECT-*$VERSION.deb $ARCHIVE_DIR/
  
  # retain last 5 versions. remove older versions.
  fileCount=`cd $ARCHIVE_DIR && ls -b | wc -l`
  if [ $fileCount -gt 5 ]; then
    cd $ARCHIVE_DIR && ls -t | sed -e '1,5d' | xargs rm
  fi
  
}

function eco {
  ssh -i $HOME/.ssh/id_rsa user@name.remotehost.com "mkdir -p $ARCHIVE_DIR"
  scp -i $HOME/.ssh/id_rsa $ARCHIVE_DIR/$PRODUCT-$PROJECT-*$VERSION.deb user@name.remotehost.com:$ARCHIVE_DIR/
}

function run {
  archive
  eco
}

if [[ -z "$PRODUCT" || -z "$PROJECT" || -z "$VERSION" ]]; then
  echo "Incorrect usage of Jenkins post-build-script!"
  echo "Expected params: product project version not provided."
  exit 0
else
  #echo "run $PRODUCT $PROJECT $VERSION"
  run
fi

