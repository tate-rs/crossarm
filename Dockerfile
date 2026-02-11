# syntax=docker/dockerfile:1
ARG IMAGE="ubuntu"
ARG IMAGE_VERSION="20.04"
ARG TOOLCHAIN_DIR="/toolchain"
ARG CROSS_DIR="/crossarm"
ARG CROSS_ARCH="arm-linux-gnueabihf"

ARG USER_NAME=crossarm
ARG HOST_UID=1000
ARG HOST_GID=1000

# FINAL
FROM ${IMAGE}:${IMAGE_VERSION} AS final 
LABEL maintainer="burnek.matyas@gmail.com" \
      version="1.0.1" \
      description="Image for ARM & AARCH64 crosscompiling"

ARG USER_NAME
ARG HOST_UID
ARG HOST_GID
ARG TOOLCHAIN_DIR
ARG CROSS_DIR
ARG CROSS_ARCH
ARG CROSS_PREFIX="${CROSS_ARCH}-"

# Copy required files to the final image
COPY toolchain.cmake ${CROSS_DIR}/toolchain.cmake
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Set timezone cuz cmake needs it, dunno why tho
ENV TZ=UTC
RUN ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
RUN echo "$TZ" > /etc/timezone

# Update and install necessary packages
RUN DEBIAN_FRONTEND=noninteractive apt update && apt install -y \
	tzdata \
	rsync \
	pkg-config \
	git \
	make \
	build-essential \
	libssl-dev \
	cmake \
	python3 \
	libclang-dev \
	clang \
	vim \
	wget \
	sshpass \
	ninja-build

# Alias python3 to python
RUN cp /usr/bin/python3 /usr/bin/python

# Set root password
RUN echo 'root:toor' | chpasswd
# Create nonroot user
RUN groupadd -g ${HOST_GID} ${USER_NAME} && useradd -g ${HOST_GID} -m -s /bin/bash -u ${HOST_UID} ${USER_NAME}

RUN mkdir -p ${CROSS_DIR}
# Own the sysroot
RUN chown -R ${HOST_UID}:${HOST_GID} ${CROSS_DIR}

# Determine the cross-compiler prefix at build time and generate profile script
RUN cat <<EOF > /etc/profile.d/cross.sh
export CROSS_DIR=${CROSS_DIR}
export CROSS_COMPILE=${CROSS_PREFIX}
export SYSROOT=${CROSS_DIR}/${CROSS_ARCH}
export PATH=\${PATH:-}:${CROSS_DIR}/bin:${CROSS_DIR}/${CROSS_ARCH}/bin
export CMAKE_TOOLCHAIN=${CROSS_DIR}/toolchain.cmake
export LD_LIBRARY_PATH=\$SYSROOT:\${LD_LIBRARY_PATH:-}
EOF

RUN chown -R ${HOST_UID}:${HOST_GID} /etc/profile.d/cross.sh

# Swap to nonroot user
USER ${HOST_UID}:${HOST_GID}
WORKDIR /project

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash", "-i"]
