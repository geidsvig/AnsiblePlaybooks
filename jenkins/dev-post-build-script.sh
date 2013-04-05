#!/bin/bash

#
# This bash file handles all development branch Jenkins post-build actions for SBT dist projects.
#
# To have Jenkins correctly handle this task, use the AnsiblePlaybooks project directory created by the Jenkins job.
#     http://jenkins.serverhost.com:8080/job/AnsiblePlaybooks/
# This creates a most recent workspace of the ansible project at:
#     /ebs1/opt/jenkins/jobs/AnsiblePlaybooks/workspace/
# Then set the Jenkins job that will use the AnsiblePlaybook project to have it's "Post-build Actions" as
#     cd /ebs1/opt/jenkins/jobs/AnsiblePlaybooks/workspace/
#     ./jenkins/dev-post-build-script.sh <product> <project> <build-number> <job-name>
# example:
#     ./jenkins/dev-post-build-script.sh hootbomb hermes $BUILD_NUMBER "$JOB_NAME"
#
#
# $1 product name
# $2 project name
# $3 build number
# $4 jenkins job name

PRODUCT="$1"
PROJECT="$2"
BUILD_NUMBER="$3"
JENKINS_JOB="$4"

WORKING_DIR="/ebs1/opt/jenkins/jobs/$JENKINS_JOB/workspace"
DOCS_DIR="/var/www/docs/$PRODUCT/$PROJECT/dev"
ARCHIVE_DIR="/ebs1/www/artifacts/$PRODUCT/$PROJECT/dev"

function configure {
  if [ -f "$WORKING_DIR"/target/$PROJECT-dist/config/reference.conf ]; then 
    sed -i -e s/build.version=x/build.version=$BUILD_NUMBER/ "$WORKING_DIR"/target/$PROJECT-dist/config/reference.conf
  fi
}

function docs {
  if [ ! -e "$DOCS_DIR" ]; then
    mkdir -p "$DOCS_DIR"
  fi
  rm -rf "$DOCS_DIR"/*

  if [ -f "$WORKING_DIR"/README ]; then
     cp "$WORKING_DIR"/README "$DOCS_DIR"/README
  fi

  if [ -e "$WORKING_DIR"/target/api ]; then
    cp -r "$WORKING_DIR"/target/api "$DOCS_DIR"/api
  fi

  if [ -e "$WORKING_DIR"/public ]; then
    cp -r "$WORKING_DIR"/public/* "$DOCS_DIR"/
  fi
}

function package {
  bash "$WORKING_DIR"/make-deb.sh $BUILD_NUMBER
}

function archive {
  if [ ! -e $ARCHIVE_DIR ]; then
    mkdir -p $ARCHIVE_DIR
  fi
  
  rm -rf $ARCHIVE_DIR/*
  
  mv "$WORKING_DIR"/$PRODUCT-$PROJECT-*.deb $ARCHIVE_DIR/
}

function cleanup {
  rm -rf "$WORKING_DIR"/*
}

function run {
  cd "$WORKING_DIR"
  configure
  docs
  package
  archive
  cleanup
}

if [[ -z "$PRODUCT" || -z "$PROJECT" || -z "$BUILD_NUMBER" || -z "$JENKINS_JOB" ]]; then
  echo "Incorrect usage of Jenkins post-build-script!"
  echo "Expected params: product project build_number jenkins_job not provided."
  exit 0
else
  #echo "run $PRODUCT $PROJECT $BUILD_NUMBER $JENKINS_JOB"
  run
fi

