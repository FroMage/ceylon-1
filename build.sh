#!/bin/bash

set -e

# Define all the versions that should be generated
VERSIONS=(1.3.0 1.2.2 1.2.1 1.2.0 1.1.0 1.0.0)

# Define the "latest" version
LATEST=1.3.0

# Define which JRE versions to generate for
JRES=(7 8)

# Define the default JRE
DEFAULT_JRE=8

# Define default platform
DEFAULT_PLATFORM="debian"

IMAGE=docker.io/ceylon/ceylon

BUILD=0
PUSH=0
QUIET=-q
for arg in "$@"; do
    case "$arg" in
        --help)
            echo "Usage: $0 [--help] [--build] [--push]"
            echo ""
            echo "   --help   : shows this help text"
            echo "   --build  : runs 'docker build' for each image"
            echo "   --push   : pushes each image to Docker Hub"
            echo ""
            exit
            ;;
        --build)
            BUILD=1
            ;;
        --push)
            PUSH=1
            ;;
        --verbose)
            QUIET=
            ;;
    esac
done

function error() {
    local MSG=$1
    [[ ! -z $MSG ]] && echo $MSG
    exit 1
}

function build_dir() {
    local VERSION=$1
    [[ -z $VERSION ]] && error "Missing 'version' parameter for build_dir()"
    local FROM=$2
    [[ -z $FROM ]] && error "Missing 'from' parameter for build_dir()"
    local NAME=$3
    [[ -z $NAME ]] && error "Missing 'name' parameter for build_dir()"
    local DOCKERFILE=$4
    [[ -z $DOCKERFILE ]] && error "Missing 'dockerfile' parameter for build_dir()"
    local INCLUDE_BOOTSTRAP=$5
    [[ -z $INCLUDE_BOOTSTRAP ]] && error "Missing 'include_bootstrap' parameter for build_dir()"
    shift 5
    local TAGS=("$@")

    echo "Building image $NAME with tags ${TAGS[@]} ..."
    rm -rf /tmp/docker-ceylon-build-templates
    mkdir /tmp/docker-ceylon-build-templates
    [[ $INCLUDE_BOOTSTRAP -eq 1 ]] && cp templates/bootstrap.sh /tmp/docker-ceylon-build-templates/
    cp templates/$DOCKERFILE /tmp/docker-ceylon-build-templates/Dockerfile
    sed -i "s/@@FROM@@/$FROM/g" /tmp/docker-ceylon-build-templates/Dockerfile
    sed -i "s/@@VERSION@@/$VERSION/g" /tmp/docker-ceylon-build-templates/Dockerfile
    mkdir -p "$NAME"
    pushd "$NAME" > /dev/null
    cp /tmp/docker-ceylon-build-templates/* .
    rm -rf /tmp/docker-ceylon-build-templates
    if [[ $BUILD -eq 1 ]]; then
        echo "Pulling existing image from Docker Hub (if any)..."
        docker pull "${IMAGE}:$NAME" > /dev/null || true
        echo "Building image..."
        docker build -t "${IMAGE}:$NAME" $QUIET .
    fi
    [[ $PUSH -eq 1 ]] && echo "Pushing image to Docker Hub..." && docker push "${IMAGE}:$NAME"
    for t in ${TAGS[@]}; do
        [[ $BUILD -eq 1 ]] && docker tag "${IMAGE}:$NAME" "${IMAGE}:$t"
        [[ $PUSH -eq 1 ]] && docker push "${IMAGE}:$t"
    done
    popd > /dev/null
}

function build_normal_onbuild() {
    local VERSION=$1
    [[ -z $VERSION ]] && error "Missing 'version' parameter for build_normal_onbuild()"
    local FROM=$2
    [[ -z $FROM ]] && error "Missing 'from' parameter for build_normal_onbuild()"
    local JRE=$3
    [[ -z $JRE ]] && error "Missing 'jre' parameter for build_normal_onbuild()"
    local PLATFORM=$4
    [[ -z $PLATFORM ]] && error "Missing 'platform' parameter for build_normal_onbuild()"
    shift 4
    local TAGS=("$@")

    echo "Building for JRE $JRE with tags ${TAGS[@]} ..."

    local OBTAGS=()
    for t in ${TAGS[@]}; do
        OBTAGS+=("$t-onbuild")
    done

    local NAME="$VERSION-$JRE-$PLATFORM"
    build_dir $VERSION $FROM $NAME "Dockerfile.$PLATFORM" 1 "${TAGS[@]}"
    build_dir $VERSION "ceylon\\/ceylon:$NAME" "$NAME-onbuild" "Dockerfile.onbuild" 0 "${OBTAGS[@]}"
}

function build_jres() {
    local VERSION=$1
    [[ -z $VERSION ]] && error "Missing 'version' parameter for build_jres()"
    local FROM_TEMPLATE=$2
    [[ -z $FROM_TEMPLATE ]] && error "Missing 'from_template' parameter for build_jres()"
    local JRE_TEMPLATE=$3
    [[ -z $JRE_TEMPLATE ]] && error "Missing 'jre_template' parameter for build_jres()"
    local PLATFORM=$4
    [[ -z $PLATFORM ]] && error "Missing 'platform' parameter for build_jres()"

    echo "Building for platform $PLATFORM ..."

    for t in ${JRES[@]}; do
        local FROM=${FROM_TEMPLATE/@/$t}
        local JRE=${JRE_TEMPLATE/@/$t}
        local TAGS=()
        if [[ "$PLATFORM" == "$DEFAULT_PLATFORM" ]]; then
            TAGS+=("$VERSION-$JRE")
            if [[ "$t" == "$DEFAULT_JRE" ]]; then
                TAGS+=("$VERSION")
                if [[ "$VERSION" == "$LATEST" ]]; then
                    TAGS+=("latest")
                fi
            fi
        fi
        build_normal_onbuild $VERSION $FROM $JRE $PLATFORM "${TAGS[@]}"
    done
}

function build() {
    local VERSION=$1
    [[ -z $VERSION ]] && error "Missing 'version' parameter for build()"

    echo "Building version $VERSION ..."

    build_jres $VERSION "ceylon\\/ceylon-base:jre@-debian" "jre@" "debian"
    build_jres $VERSION "ceylon\\/ceylon-base:jre@-redhat" "jre@" "redhat"
}

for v in ${VERSIONS[@]}; do
    build $v
done

