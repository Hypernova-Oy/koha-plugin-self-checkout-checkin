#!/bin/bash

# Copyright 2025 Hypernova Oy
# Copyright 2020 The National Library of Finland

function increment_version {
  VERSION="$1"
  VERSION=`echo "$VERSION" | perl -pe 's/^((\d+\.)*)(\d+)(.*)$/$1.($3+1).$4/e'`
  echo "incremented version VERSION='$VERSION'"
}

function get_latest_version {
  VERSION=`git log --pretty=oneline --decorate | egrep -o "tag: v[0-9.]+" | sed -e "s/tag: v//" | head -n 1`
  if [ -z "$VERSION" ]; then
    VERSION="0.0.0"
  fi
  echo "got latest version VERSION='$VERSION'"
}

function create_new_version_tag {
  get_latest_version
  increment_version "$VERSION"
  git tag "v$VERSION"
  echo "created new version tag 'v$VERSION'"
}

function replace_variable {
  VAR="$1";
  eval VAL="\$$VAR";
  echo "Replacing variable '\$$VAR' with '$VAL' in file 'dist/${PM_FILE}'";
  perl -i -pe "s/^our\s+"'\$'""$VAR".+?#PLACEHOLDER\$/our "'\$'"$VAR = '$VAL'; #PLACEHOLDER/" "dist/${PM_FILE}"
}

function build_release_package {
  echo "Building release package ${RELEASE_FILE}"
  if [ -e ${RELEASE_FILE} ]
  then
    rm ${RELEASE_FILE}
  fi
  mkdir -p "dist/$BASEPATH"
  cp -r $BASEPATH/* dist/$BASEPATH/
  cp $PM_FILE dist/$PM_FILE
  replace_variable VERSION
  replace_variable DATE_UPDATED
  cd dist
  zip -r ../${RELEASE_FILE} ./Koha
  cd ..
  #rm -rf dist
}

VERSION=`git log -1 --pretty=oneline --decorate | egrep -o "tag: v[0-9.]+" | sed -e "s/tag: v//"`
if [ -z "$VERSION" ]; then
  create_new_version_tag
fi

BASEPATH='Koha/Plugin/Fi/Hypernova/SelfCheckoutCheckin'
PM_FILE="$BASEPATH.pm"
DATE_UPDATED=`date +"%Y-%m-%d"`
RELEASE_FILE="koha-plugin-self-checkout-checkin-${VERSION}.kpz"

build_release_package
