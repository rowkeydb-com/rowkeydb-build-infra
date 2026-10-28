# Copyright 2026 Chanzo
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# The image every build of the consumers runs in, rebuilt from pinned
# inputs so that two builds give the same image. It reproduces the image
# recipe/Dockerfile.ci built: every package, tool and file at the version
# found in that image, apart from the changes RowKeyDB's
# design/shared_build_architecture.md lists for the rebuild and for the
# later changes: the MSan libraries built from the compiler's own LLVM
# release, gcov and cpp from the same GCC as gcc and g++, and the Go the
# consumers' Bazel builds use. Build it only with scripts/build-image.sh,
# which pins the builder and its settings.

# The versions of the compilers and of the tools the recipe downloads,
# each download beside its SHA-256, and the JDK's exact package versions.
# golangci-lint, which Go builds, is fixed by Go's checksum database
# instead. The compilers' arguments name major versions, whose builds the
# Ubuntu snapshot and recipe/llvm-debs.sha256 fix. The other pins are the
# base image, on the FROM line below; Bazel's version, in .bazelversion;
# the apt.llvm.org packages, whose major versions CLANG_VERSION and
# CLANG_TOOLS_VERSION must name, in recipe/llvm-debs.sha256 and the inputs
# release, with their repository's lists in recipe/files; the Python
# tools, in recipe/requirements.txt; the Maven repository's checksum, at
# its step; and the Java trust store, recipe/files/java-cacerts, which must
# hold the certificates of the snapshot's ca-certificates.
# scripts/build-image.sh takes SOURCE_DATE_EPOCH from UBUNTU_SNAPSHOT.
# trivy reads TRIVY_VERSION as its --version switch, which ignores a value
# that is not true or false; the recipe runs trivy only with --version.
ARG UBUNTU_SNAPSHOT=20261001T055000Z
ARG GCC_VERSION=14
ARG CLANG_VERSION=19
ARG CLANG_TOOLS_VERSION=21
ARG DEFAULT_JDK_VERSION=2:1.21-75+exp1
ARG OPENJDK_VERSION=21.0.12.1+1-1~24.04.4
ARG BAZELISK_VERSION=1.19.0
ARG BAZELISK_SHA256=d28b588ac0916abd6bf02defb5433f6eddf7cba35ffa808eabb65a44aab226f7
ARG BAZEL_SHA256=ca189f994f632c91c275443b8571652e3ea190fc2437a5798121ba7e5a9a2f29
ARG TYPOS_VERSION=1.51.1
ARG TYPOS_SHA256=e5c6beffdd1f46d793b1d035e917724fa8e400efb0cc0bd5c83aa892a72a9ff6
ARG GO_VERSION=1.27.3
ARG GO_SHA256=65efbc80fdc1fa2cd2631cad5b481777a68e8725f34e89f50fc6ac714e379b40
ARG GCLOUD_VERSION=587.0.0
ARG GCLOUD_SHA256=57df2448d259c654796a3703af8e5b53a02d439715b2034d6bb811efc2d6dd7b
ARG GCLOUD_COMPONENTS_SHA256=f852af078eae4c614fb453c703aab46a813818b0df82ab650e95449b284c980d
ARG CBT_PACKAGE=google-cloud-sdk-cbt-linux-x86_64-20260814074256.tar.gz
ARG CBT_SHA256=bf72f5f6f2c8649594e45ea3c0a8578934e1b937d36a8ff89c1677169b4b3f22
ARG TERRAFORM_VERSION=1.7.5
ARG TERRAFORM_SHA256=3ff056b5e8259003f67fd0f0ed7229499cfb0b41f3ff55cc184088589994f7a5
ARG TFLINT_VERSION=0.64.0
ARG TFLINT_SHA256=cca9d13e2e1d7a2c627af60ff899a3c9b74212899416aeb96ec764d2ef954537
ARG TRIVY_VERSION=0.74.0
ARG TRIVY_SHA256=2ae6fe3ee734b7fdf11335663e18c75ea12dccc76062f09f164a3b0f8be4371a
ARG GOLANGCI_LINT_VERSION=2.15.0
ARG MSAN_LLVM_VERSION=19.1.7
ARG MSAN_LLVM_SHA256=82401fea7b79d0078043f7598b835284d6650a75b93e64b6f761ea7b63097501

# ubuntu:noble-20260911, linux/amd64.
FROM ubuntu:24.04@sha256:496754492fb28b4d3049432f2ca787449331e23fb14f0dd3fffea86bf5a93eb4 AS base

# The time the build stands for, given by scripts/build-image.sh: the time
# of the Ubuntu snapshot, on the day of the adopted image's build.
ARG SOURCE_DATE_EPOCH

ENV DEBIAN_FRONTEND=noninteractive

# Every step removes the files it writes whose content depends on the time
# or the machine of the build: logs, caches and machine identifiers, which
# the design lists among the rebuild's intended changes. Removed by a later
# step, they would stay in the layer of the step that wrote them, and two
# builds would give different images. Every file is copied in with a fixed
# mode, since a checkout's modes depend on the machine.
#
# Every apt step installs without SOURCE_DATE_EPOCH: given it, Python
# writes bytecode that records a hash of each source, where the adopted
# image's records the source's time. It takes every phased update, which
# apt would otherwise choose by the machine's identifier.

# The Ubuntu archive as it was at the adopted image's first apt step: every
# package the image holds has its version there, and none a newer one. The
# base image has no CA certificates, so this first step reaches the
# snapshot without checking its certificate; apt checks every package
# against the archive's signed release files all the same. The last apt
# step restores the archive's own addresses. The JDK is named by its exact
# version, and the OpenJDK it brings is checked. The four accounts the
# packages create record the day of the build as that of their last
# password change, so they are given the day the build stands for. The
# Java trust store the packages create records the time it was made, so it
# is replaced by the adopted image's, once the two are seen to hold the
# same certificates.
ARG UBUNTU_SNAPSHOT
ARG GCC_VERSION
ARG DEFAULT_JDK_VERSION
ARG OPENJDK_VERSION
RUN --mount=type=bind,source=recipe/files/java-cacerts,target=/tmp/java-cacerts \
    : "${SOURCE_DATE_EPOCH:?is not set}" \
    && cp -p /etc/apt/sources.list.d/ubuntu.sources /tmp/ubuntu.sources \
    && sed -i \
        -e "s#http://archive.ubuntu.com/ubuntu/#https://snapshot.ubuntu.com/ubuntu/${UBUNTU_SNAPSHOT}/#" \
        -e "s#http://security.ubuntu.com/ubuntu/#https://snapshot.ubuntu.com/ubuntu/${UBUNTU_SNAPSHOT}/#" \
        /etc/apt/sources.list.d/ubuntu.sources \
    && apt-get -o Acquire::https::Verify-Peer=false update \
    && env -u SOURCE_DATE_EPOCH apt-get -o Acquire::https::Verify-Peer=false \
        -o APT::Get::Always-Include-Phased-Updates=true install -y \
    autoconf \
    automake \
    build-essential \
    ca-certificates \
    curl \
    git \
    gnupg \
    lcov \
    "gcc-${GCC_VERSION}" \
    "g++-${GCC_VERSION}" \
    libtool \
    lsb-release \
    maven \
    "default-jdk=${DEFAULT_JDK_VERSION}" \
    pkg-config \
    protobuf-compiler \
    python3 \
    shellcheck \
    wget \
    xz-utils \
    zip \
    unzip \
    zstd \
    cmake \
    ninja-build \
    && { [ "$(dpkg-query -W -f '${Version}' openjdk-21-jdk)" = "${OPENJDK_VERSION}" ] \
        || { echo "openjdk-21-jdk is not ${OPENJDK_VERSION}" >&2; exit 1; }; } \
    && sed -i -E \
        "s/^(messagebus|systemd-network|systemd-resolve|systemd-timesync):([^:]*):[0-9]*:/\1:\2:$((SOURCE_DATE_EPOCH / 86400)):/" \
        /etc/shadow /etc/shadow- \
    && update-alternatives --install /usr/bin/gcc gcc "/usr/bin/gcc-${GCC_VERSION}" 100 \
    && update-alternatives --install /usr/bin/g++ g++ "/usr/bin/g++-${GCC_VERSION}" 100 \
    && ln -sf "gcov-${GCC_VERSION}" /usr/bin/gcov \
    && ln -sf "cpp-${GCC_VERSION}" /usr/bin/cpp \
    && { keytool -J-XX:-UsePerfData -list -keystore /etc/ssl/certs/java/cacerts -storepass changeit \
        > /tmp/made-store || { cat /tmp/made-store >&2; exit 1; }; } \
    && { keytool -J-XX:-UsePerfData -list -keystore /tmp/java-cacerts -storepass changeit \
        > /tmp/kept-store || { cat /tmp/kept-store >&2; exit 1; }; } \
    && grep fingerprint /tmp/made-store | sort > /tmp/made-certificates \
    && grep fingerprint /tmp/kept-store | sort > /tmp/kept-certificates \
    && { [ -s /tmp/made-certificates ] \
        || { echo "keytool listed no certificate in the packages' trust store" >&2; exit 1; }; } \
    && { cmp -s /tmp/made-certificates /tmp/kept-certificates \
        || { echo "recipe/files/java-cacerts holds other certificates than the packages' trust store" >&2; exit 1; }; } \
    && rm /tmp/made-store /tmp/kept-store /tmp/made-certificates /tmp/kept-certificates \
    && cp /tmp/java-cacerts /etc/ssl/certs/java/cacerts \
    && rm -rf /var/lib/apt/lists/* /var/log/apt/* /var/log/dpkg.log \
        /var/log/alternatives.log /var/cache/ldconfig/aux-cache \
        /var/cache/fontconfig/*.cache-* /run/systemd/resolve/stub-resolv.conf \
        /var/lib/dbus/machine-id \
    && : > /etc/machine-id

# This repository's release that holds the inputs no other place is sure
# to keep.
ARG INPUTS=https://github.com/rowkeydb-com/rowkeydb-build-infra/releases/download/image-inputs-20261001

# The Maven repository java-bigtable-hbase 2.18.3 built for the HBase
# conformance tests, taken from the adopted image with its files' contents
# and modes unchanged: built again, its jars and Maven's records would
# carry the date. The archive gives every file the time 1970-01-01. The
# tests run Maven offline, so it reads no time and cannot fetch what the
# archive lacks: the archive must hold java-bigtable-hbase at the version
# rowkeydb's MODULE.bazel fetches.
RUN curl -fsSL -o /tmp/maven_cache.tar.zst "${INPUTS}/maven_cache.tar.zst" \
    && echo "4c7a7f12108eadd1b08397d282057071b66e82114af601e45cdf63b7d6f2abc0  /tmp/maven_cache.tar.zst" | sha256sum -c - \
    && tar --zstd -xf /tmp/maven_cache.tar.zst -C /opt \
    && rm /tmp/maven_cache.tar.zst

# clang 19, and clang-tidy and clang-format 21: the builds of apt.llvm.org
# the adopted image holds. apt.llvm.org keeps only its latest build of a
# version, so the packages are kept with their checksums in the release
# above; their Ubuntu dependencies come from the snapshot. apt marks the
# packages it installs from files as asked for; marked as dependencies
# afterwards, they would be recorded after the others, in an order
# different from the adopted image's. So every package is installed as a
# dependency, and the seven the adopted recipe asked for are then marked
# as asked for.
ARG CLANG_VERSION
ARG CLANG_TOOLS_VERSION
RUN --mount=type=bind,source=recipe/llvm-debs.sha256,target=/tmp/llvm-debs.sha256 \
    mkdir /tmp/llvm-debs \
    && cd /tmp/llvm-debs \
    && awk '{print $2}' /tmp/llvm-debs.sha256 | while read -r f; do curl -fsSL -o "$f" "${INPUTS}/$f"; done \
    && sha256sum -c /tmp/llvm-debs.sha256 \
    && apt-get update \
    && env -u SOURCE_DATE_EPOCH apt-get -o APT::Get::Always-Include-Phased-Updates=true \
        install -y --mark-auto ./*.deb \
    && apt-mark manual "clang-tidy-${CLANG_TOOLS_VERSION}" \
        "clang-format-${CLANG_TOOLS_VERSION}" "clang-${CLANG_VERSION}" \
        "libclang-${CLANG_VERSION}-dev" "llvm-${CLANG_VERSION}-dev" \
        "libc++-${CLANG_VERSION}-dev" "libc++abi-${CLANG_VERSION}-dev" \
    && cd / \
    && rm -rf /var/lib/apt/lists/* /tmp/llvm-debs /var/log/apt/* \
        /var/log/dpkg.log /var/log/alternatives.log /var/cache/ldconfig/aux-cache \
    && ln -sf "/usr/bin/clang-tidy-${CLANG_TOOLS_VERSION}" /usr/bin/clang-tidy \
    && ln -sf "/usr/bin/clang-format-${CLANG_TOOLS_VERSION}" /usr/bin/clang-format \
    && ln -sf "/usr/bin/clang-${CLANG_VERSION}" /usr/bin/clang \
    && ln -sf "/usr/bin/clang++-${CLANG_VERSION}" /usr/bin/clang++

ARG BAZELISK_VERSION
ARG BAZELISK_SHA256
RUN curl -fsSL -o /usr/local/bin/bazel "https://github.com/bazelbuild/bazelisk/releases/download/v${BAZELISK_VERSION}/bazelisk-linux-amd64" \
    && echo "${BAZELISK_SHA256}  /usr/local/bin/bazel" | sha256sum -c - \
    && chmod +x /usr/local/bin/bazel

# Unpacked into / as the adopted recipe did, which left the archive's other
# files there.
ARG TYPOS_VERSION
ARG TYPOS_SHA256
RUN cd / \
    && archive="typos-v${TYPOS_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    && curl -fsSL -o "${archive}" "https://github.com/crate-ci/typos/releases/download/v${TYPOS_VERSION}/${archive}" \
    && echo "${TYPOS_SHA256}  ${archive}" | sha256sum -c - \
    && tar -xzf "${archive}" \
    && mv typos /usr/local/bin/ \
    && rm "${archive}"

WORKDIR /workspace

ARG GO_VERSION
ARG GO_SHA256
RUN curl -fsSL -o /tmp/go.tar.gz "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
    && echo "${GO_SHA256}  /tmp/go.tar.gz" | sha256sum -c - \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm /tmp/go.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"

# google-cloud-cli 587.0.0, the release the adopted image holds, and its
# cbt component from that release's component list. The list and the
# component's package are checked and served to gcloud from a local
# directory, where it looks for a package beside the list. gcloud compiles
# its Python with several worker processes, and some of the bytecode
# depends on how the files are shared among them, which varies from one
# build to the next; nothing but this step runs gcloud, so its bytecode is
# removed, as are its logs, its records of its update check and survey
# prompt, and its answer to whether it runs on Compute Engine.
ARG GCLOUD_VERSION
ARG GCLOUD_SHA256
ARG GCLOUD_COMPONENTS_SHA256
ARG CBT_PACKAGE
ARG CBT_SHA256
RUN curl -fsSL -o /tmp/gcloud.tar.gz "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${GCLOUD_VERSION}-linux-x86_64.tar.gz" \
    && echo "${GCLOUD_SHA256}  /tmp/gcloud.tar.gz" | sha256sum -c - \
    && mkdir -p /tmp/gcloud-components/components \
    && cd /tmp/gcloud-components \
    && curl -fsSL -o "components-v${GCLOUD_VERSION}.json" "https://dl.google.com/dl/cloudsdk/channels/rapid/components-v${GCLOUD_VERSION}.json" \
    && echo "${GCLOUD_COMPONENTS_SHA256}  components-v${GCLOUD_VERSION}.json" | sha256sum -c - \
    && curl -fsSL -o "components/${CBT_PACKAGE}" "https://dl.google.com/dl/cloudsdk/channels/rapid/components/${CBT_PACKAGE}" \
    && echo "${CBT_SHA256}  components/${CBT_PACKAGE}" | sha256sum -c - \
    && cd / \
    && tar -C /usr/local -xzf /tmp/gcloud.tar.gz \
    && /usr/local/google-cloud-sdk/install.sh -q \
    && CLOUDSDK_COMPONENT_MANAGER_SNAPSHOT_URL="file:///tmp/gcloud-components/components-v${GCLOUD_VERSION}.json" \
        /usr/local/google-cloud-sdk/bin/gcloud components install cbt -q \
    && ln -s /usr/local/google-cloud-sdk/bin/cbt /usr/local/bin/cbt \
    && find /usr/local/google-cloud-sdk -name __pycache__ -type d -prune -exec rm -rf {} + \
    && rm -rf /tmp/gcloud.tar.gz /tmp/gcloud-components \
        /root/.config/gcloud/.last_survey_prompt.yaml \
        /root/.config/gcloud/.last_update_check.json /root/.config/gcloud/gce \
        /root/.config/gcloud/logs

ARG TERRAFORM_VERSION
ARG TERRAFORM_SHA256
RUN curl -fsSL -o /tmp/terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    && echo "${TERRAFORM_SHA256}  /tmp/terraform.zip" | sha256sum -c - \
    && unzip -q /tmp/terraform.zip terraform -d /usr/local/bin \
    && rm /tmp/terraform.zip

ARG TFLINT_VERSION
ARG TFLINT_SHA256
RUN curl -fsSL -o /tmp/tflint.zip "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_amd64.zip" \
    && echo "${TFLINT_SHA256}  /tmp/tflint.zip" | sha256sum -c - \
    && unzip -q /tmp/tflint.zip tflint -d /usr/local/bin \
    && rm /tmp/tflint.zip

ARG TRIVY_VERSION
ARG TRIVY_SHA256
RUN curl -fsSL -o /tmp/trivy.tar.gz "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" \
    && echo "${TRIVY_SHA256}  /tmp/trivy.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/trivy.tar.gz -C /usr/local/bin trivy \
    && rm /tmp/trivy.tar.gz

# Go's module proxy and checksum database fix the sources of every module.
# Go's build cache, its usage counters and its copies of the checksum
# database's state at the time of the build are removed.
ARG GOLANGCI_LINT_VERSION
RUN /usr/local/go/bin/go install "github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v${GOLANGCI_LINT_VERSION}" \
    && mv /root/go/bin/golangci-lint /usr/local/bin/ \
    && rm -rf /root/.cache/go-build /root/.config/go/telemetry /root/go/pkg/sumdb \
        /root/go/pkg/mod/cache/download/sumdb

# The Python tools. Every package is downloaded first and checked against
# its hash, then installed from those files alone, naming the packages the
# adopted recipe named, so that pip records the same ones as asked for;
# recipe/requirements.txt fixes their versions. No bytecode is kept: it
# records the times of its sources, which pip writes during the build.
# This is the last apt step, which restores the archive's own addresses.
RUN --mount=type=bind,source=recipe/requirements.txt,target=/tmp/requirements.txt \
    apt-get update \
    && env -u SOURCE_DATE_EPOCH apt-get -o APT::Get::Always-Include-Phased-Updates=true \
        install -y python3-venv \
    && python3 -m venv /opt/ansible-env \
    && /opt/ansible-env/bin/pip download --no-deps --no-cache-dir --require-hashes -r /tmp/requirements.txt -d /tmp/wheels \
    && /opt/ansible-env/bin/pip install --no-compile --no-cache-dir --no-index --find-links /tmp/wheels \
        yamllint ansible-core ansible-lint ruff pytest pyyaml \
    && find /opt/ansible-env -name __pycache__ -type d -prune -exec rm -rf {} + \
    && ln -sf /opt/ansible-env/bin/yamllint /usr/local/bin/yamllint \
    && ln -sf /opt/ansible-env/bin/ansible /usr/local/bin/ansible \
    && ln -sf /opt/ansible-env/bin/ansible-galaxy /usr/local/bin/ansible-galaxy \
    && ln -sf /opt/ansible-env/bin/ansible-lint /usr/local/bin/ansible-lint \
    && ln -sf /opt/ansible-env/bin/ruff /usr/local/bin/ruff \
    && ln -sf /opt/ansible-env/bin/pytest /usr/local/bin/pytest \
    && rm -rf /var/lib/apt/lists/* /tmp/wheels \
        /var/log/apt/* /var/log/dpkg.log /var/log/alternatives.log \
        /var/cache/ldconfig/aux-cache \
    && mv /tmp/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources

# Bazel, at the version .bazelversion names, held by Bazelisk in the image
# so that no run downloads it. Bazelisk reads .bazelversion only in a
# workspace, so the version is read from it here. The tools are then run
# once to check them, without letting Python write bytecode; the records
# of their runs and version checks are removed.
ENV BAZELISK_HOME=/opt/bazelisk
COPY --chmod=644 .bazelversion /workspace/.bazelversion
ARG BAZEL_SHA256
RUN USE_BAZEL_VERSION="$(cat /workspace/.bazelversion)" \
        BAZELISK_VERIFY_SHA256="${BAZEL_SHA256}" \
        bazel --version \
    && chmod -R a+rwX /opt/bazelisk \
    && export PYTHONDONTWRITEBYTECODE=1 \
    && clang --version && clang-format --version && shellcheck --version && typos --version \
    && go version && terraform --version && tflint --version && trivy --version \
    && golangci-lint --version && pytest --version \
    && rm -rf /root/.cache/tflint/version_check_cache.json /root/.config/go/telemetry \
        /root/.terraform.d/checkpoint_cache /root/.terraform.d/checkpoint_signature

# apt.llvm.org's repository as the adopted image lists it, written after
# the last apt step so that no step reads it.
COPY --chmod=644 recipe/files/llvm-archive-keyring.gpg /usr/share/keyrings/llvm-archive-keyring.gpg
COPY --chmod=644 recipe/files/llvm-19.list recipe/files/llvm-21.list /etc/apt/sources.list.d/

# ---------------------------------------------------------
# MSan stage: the base, and libc++, libc++abi and libunwind built for MSan
# ---------------------------------------------------------
FROM base AS msan
# Given to the compiler, which takes __DATE__ and __TIME__ from it.
ARG SOURCE_DATE_EPOCH
ARG BUILD_CPUS=8
ARG CLANG_VERSION
ARG MSAN_LLVM_VERSION
ARG MSAN_LLVM_SHA256

# Built under /workspace, as the adopted recipe did: the libraries record
# the paths of their sources.
RUN source="llvm-project-${MSAN_LLVM_VERSION}.src" \
    && curl -fsSL -o "${source}.tar.xz" "https://github.com/llvm/llvm-project/releases/download/llvmorg-${MSAN_LLVM_VERSION}/${source}.tar.xz" \
    && echo "${MSAN_LLVM_SHA256}  ${source}.tar.xz" | sha256sum -c - \
    && tar -xf "${source}.tar.xz" \
    && cd "${source}/runtimes" \
    && cmake -B build \
        -G Ninja \
        -DCMAKE_C_COMPILER="clang-${CLANG_VERSION}" \
        -DCMAKE_CXX_COMPILER="clang++-${CLANG_VERSION}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_USE_SANITIZER=MemoryWithOrigins \
        -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind" \
        -DLIBCXX_ENABLE_SHARED=OFF \
        -DLIBCXXABI_ENABLE_SHARED=OFF \
        -DLIBUNWIND_ENABLE_SHARED=OFF \
        -DLIBCXX_ENABLE_EXPERIMENTAL_LIBRARY=ON \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    && ninja -j "${BUILD_CPUS}" -C build cxx cxx_experimental cxxabi unwind \
    && mkdir -p "/usr/lib/llvm-${CLANG_VERSION}/lib/msan" \
    && cp build/lib/libc++.a build/lib/libc++abi.a build/lib/libunwind.a build/lib/libc++experimental.a "/usr/lib/llvm-${CLANG_VERSION}/lib/msan/" \
    && cd ../.. \
    && rm -rf "${source}" "${source}.tar.xz"
