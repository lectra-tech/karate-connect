#!/usr/bin/env bash

JAVA_PROPS=""
if [[ "${KARATE_EXTENSIONS}" != "" ]]; then
  JAVA_PROPS="-Dextensions=${KARATE_EXTENSIONS}"
fi
java ${JAVA_PROPS} -jar karate-connect-standalone.jar --format junit:xml,cucumber:json $@