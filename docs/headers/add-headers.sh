#!/usr/bin/env bash

export SH_DIR=$(dirname $0)
export PROJECT_SH_DIR=$(dirname $(dirname ${SH_DIR}))

addHeader() {
  local file=$1
  local mode=$2
  local commentChar=$([[ ${mode} == "sharp" ]] && echo "#" || echo "\*")
  local firstLineWithoutComment=$(grep -n -v "${commentChar}" "${file}"  | head -1 | cut -d : -f1)
  # drop old header
  if [[ ${firstLineWithoutComment} -ge 2 ]]; then
    sed -i "1,$((firstLineWithoutComment-1))d" "${file}"
  fi
  # add new header
  mv ${file} ${file}_bck
  cat "${SH_DIR}/${mode}-header-comment.txt" ${file}_bck > ${file}
  # clean
  rm ${file}_bck
}
export -f addHeader

find ${PROJECT_SH_DIR} -type f -name "*.js" -exec bash -c "addHeader '{}' 'star'" \;
find ${PROJECT_SH_DIR} -type f -name "*.kt" -exec bash -c "addHeader '{}' 'star'" \;
find ${PROJECT_SH_DIR} -type f -name "*.feature" -exec bash -c "addHeader '{}' 'sharp'" \;
