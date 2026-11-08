ARG BASE_IMAGE=debian:12
FROM ${BASE_IMAGE}
SHELL ["/bin/bash", "-e", "-c"]
COPY container/checkout.sh /usr/local/bin/checkout-source
RUN chmod +x /usr/local/bin/checkout-source

# ======================================================================
# Build dependencies
# ======================================================================

RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    wget \
    curl \
    ca-certificates \
    perl \
    python3 \
    python3-pip \
    cmake \
    autoconf \
    automake \
    libtool \
    pkg-config \
    libreadline-dev \
    libncurses-dev \
    libxml2-dev \
    libpcre2-dev \
    libtirpc-dev \
    python3 \
    python3-venv \
    python3-pip \
    nano \
    && rm -rf /var/lib/apt/lists/*


# ======================================================================
# EPICS Base
# ======================================================================

ARG EPICS_VERSION=7.0.10

WORKDIR /usr/local/epics

RUN wget https://epics-controls.org/download/base/base-${EPICS_VERSION}.tar.gz \
    && tar xzf base-${EPICS_VERSION}.tar.gz \
    && rm base-${EPICS_VERSION}.tar.gz \
    && cd base-${EPICS_VERSION} \
    && make -j$(nproc)

ENV EPICS_BASE=/usr/local/epics/base-${EPICS_VERSION}
ENV REQUIRE_VERSION=PSI_default
COPY container/ecmc-env.sh /opt/ecmc-env.sh
COPY container/build-shell.sh /usr/local/bin/ecmc-build-shell
RUN chmod +x /usr/local/bin/ecmc-build-shell
SHELL ["/usr/local/bin/ecmc-build-shell", "-c"]


# ======================================================================
# Classic EPICS support area
# ======================================================================

ENV SUPPORT=/opt/epics-support

RUN mkdir -p ${SUPPORT}

# ======================================================================
# PSI module environment
# ======================================================================

# The support modules use the fixed PSI_default installation namespace.
ARG PSI_VERSION=PSI_default
RUN test "$PSI_VERSION" = PSI_default

RUN mkdir -p \
    /ioc/tools \
    /ioc/modules


# ======================================================================
# PSI require
# ======================================================================

WORKDIR /opt

ARG REQUIRE_REF=0f22ca91ec6f55f13a644ae97262ced1184fe6f9
RUN checkout-source https://gitea.psi.ch/lin-epics-modules/require.git "$REQUIRE_REF" /opt/require \
    && cp /opt/require/App/tools/* /ioc/tools/

WORKDIR /opt/require

RUN make \
       EPICS_VERSIONS=${EPICS_VERSION} \
       LIBVERSION=${PSI_VERSION} \
    && make install \
       EPICS_VERSIONS=${EPICS_VERSION} \
       LIBVERSION=${PSI_VERSION}

RUN test -f /ioc/tools/driver.makefile \
    && test -f /ioc/modules/require/${PSI_VERSION}/R${EPICS_VERSION}/lib/${EPICS_HOST_ARCH}/librequire.so \
    && echo "PSI require successfully installed"

# ======================================================================
# PSI asyn
# ======================================================================

WORKDIR /opt

ARG ASYN_REF=7edd76a47fc2e34ad0d6bac523f3e9aa932f51b1
RUN checkout-source https://github.com/anderssandstrom/asyn_Makefile.git "$ASYN_REF" /opt/asyn_Makefile

WORKDIR /opt/asyn_Makefile

RUN sed -i '1a MODULE = asyn' GNUmakefile \
    && sed -i 's/-DHAVE_CALCMOD//g' GNUmakefile \
    && sed -i 's|^\(EXCLUDE =.*\)$|\1 asynCalc.dbd|' GNUmakefile \
    && grep -n -E '^(MODULE|EXCLUDE|USR_CPPFLAGS)' GNUmakefile

RUN make \
       EPICS_VERSIONS=${EPICS_VERSION} \
       LIBVERSION=${PSI_VERSION} \
    && make install \
       EPICS_VERSIONS=${EPICS_VERSION} \
       LIBVERSION=${PSI_VERSION}

RUN test -f \
       /ioc/modules/asyn/${PSI_VERSION}/R${EPICS_VERSION}/include/asynPortDriver.h \
    && echo "PSI asyn ${PSI_VERSION} successfully installed"

# ======================================================================
# PSI motorECMC
# ======================================================================

WORKDIR /opt

ARG MOTOR_REF=b6c56b46809d9a5be0014741158295c52c89b21a
RUN checkout-source https://github.com/anderssandstrom/motorECMC.git "$MOTOR_REF" /opt/motorECMC

WORKDIR /opt/motorECMC

RUN echo "=== ASYN INSTALL ===" \
    && find /ioc/modules/asyn -maxdepth 5 -type f -name asynPortDriver.h -print \
    && echo "=== MOTOR GNUmakefile ===" \
    && grep -n -E 'asyn|ASYN|VERSION|MODULE' GNUmakefile \
    && echo "=== DRIVER dependency logic ===" \
    && grep -n -E 'REQUIRED|_VERSION|OTHER_MODULES' /ioc/tools/driver.makefile | head -80

# Vanilla EPICS uses linux-aarch64 or linux-x86_64,
# while the PSI wrapper normally filters for deb10/deb12.
RUN sed -i \
       's/^ARCH_FILTER[[:space:]]*=.*/ARCH_FILTER = linux-%/' \
       GNUmakefile \
    && sed -i '/^MODULE = motorECMC/a REQUIRED += asyn\nasyn_VERSION = PSI_default' GNUmakefile \
    && grep -n -E 'MODULE|REQUIRED|asyn_VERSION' GNUmakefile

RUN make \
       EPICS_VERSIONS=${EPICS_VERSION} \
       LIBVERSION=${PSI_VERSION} \
    && make install \
       EPICS_VERSIONS=${EPICS_VERSION} \
       LIBVERSION=${PSI_VERSION}

# ======================================================================
# ECMC Ruckig
#
# Install as PSI_default.
# ECMC_makefile will be patched to use:
#
#   ruckig_VERSION = PSI_default
#
# ======================================================================

WORKDIR /opt

ARG RUCKIG_REF=b4ab23a198c4d0a73edc42253ae27e284a744ff5
RUN checkout-source https://github.com/paulscherrerinstitute/ecmc_ruckig.git "$RUCKIG_REF" /opt/ecmc_ruckig

RUN cd /opt/ecmc_ruckig \
    && sed -i \
       's/^ARCH_FILTER[[:space:]]*=.*/ARCH_FILTER = linux-%/' \
       GNUmakefile \
    && grep '^ARCH_FILTER' GNUmakefile

WORKDIR /opt/ecmc_ruckig

RUN make \
       EPICS_VERSIONS=${EPICS_VERSION} \
       LIBVERSION=${PSI_VERSION} \
    && make install \
       EPICS_VERSIONS=${EPICS_VERSION} \
       LIBVERSION=${PSI_VERSION}

RUN test -f /ioc/modules/ruckig/${PSI_VERSION}/R${EPICS_VERSION}/lib/${EPICS_HOST_ARCH}/libruckig.so \
    && echo "Ruckig ${PSI_VERSION} successfully installed"


# ======================================================================
# EtherLab userspace
# ======================================================================

ARG ETHERLAB_REF=2543cc55bd13833ddefb6cd9ec24a064cde68959
WORKDIR /opt
RUN checkout-source https://gitlab.com/etherlab.org/ethercat.git "$ETHERLAB_REF" /opt/etherlab

WORKDIR /opt/etherlab

RUN ./bootstrap \
    && ./configure \
       --prefix=/opt/etherlab-install \
       --disable-kernel \
    && make -j$(nproc) \
    && make install

WORKDIR /opt

RUN rm -rf /opt/etherlab \
    && mv /opt/etherlab-install /opt/etherlab

ENV ETHERLAB=/opt/etherlab
ENV LD_LIBRARY_PATH=/opt/etherlab/lib

RUN test -f /opt/etherlab/include/ecrt.h \
    && test -f /opt/etherlab/lib/libethercat.so \
    && echo "EtherLab userspace successfully installed"

# ======================================================================
# ECMC
# ======================================================================

ARG ECMC_VERSION=v11.2.0_RC1

WORKDIR /opt

ARG ECMC_WRAPPER_REF=11f955d11cf6a27e1851023641462f8ba04f7387
RUN checkout-source https://github.com/anderssandstrom/ECMC_makefile.git "$ECMC_WRAPPER_REF" /opt/ECMC_makefile


# ======================================================================
# Switch ECMC source to requested version
# ======================================================================

WORKDIR /opt/ECMC_makefile/ecmc

ARG ECMC_REPOSITORY=https://github.com/anderssandstrom/ecmc.git
ARG ECMC_REF=fc414a250c5bc720e81c47d66db3dc043a47e0dd
RUN checkout-source "$ECMC_REPOSITORY" "$ECMC_REF" /opt/ECMC_makefile/ecmc


# ======================================================================
# Patch PSI ECMC wrapper
# ======================================================================

WORKDIR /opt/ECMC_makefile

# Build for the architecture reported by EPICS Base.
#
# asyn, motorECMC and ruckig are installed as PSI_default.
# Explicit REQUIRED entries are needed because PSI_default is not
# automatically discovered as a normal numeric module version.
#
# EtherLab userspace is installed under /opt/etherlab.

RUN sed -i \
       's/^ARCH_FILTER[[:space:]]*=.*/ARCH_FILTER = linux-%/' \
       GNUmakefile \
    && sed -i \
       '/^MODULE = ecmc/a REQUIRED += asyn\nasyn_VERSION = PSI_default\nREQUIRED += motorECMC\nREQUIRED += ruckig' \
       GNUmakefile \
    && sed -i \
       's/^motorECMC_VERSION = .*/motorECMC_VERSION = PSI_default/' \
       GNUmakefile \
    && sed -i \
       's/^ruckig_VERSION = .*/ruckig_VERSION = PSI_default/' \
       GNUmakefile \
    && printf '\nUSR_CXXFLAGS_%s += -I/opt/etherlab/include\nUSR_LDFLAGS_%s += -L/opt/etherlab/lib\nUSR_LDFLAGS_%s += -Wl,-rpath=/opt/etherlab/lib\n' \
       "$EPICS_HOST_ARCH" "$EPICS_HOST_ARCH" "$EPICS_HOST_ARCH" \
       >> GNUmakefile


# ======================================================================
# Display relevant ECMC build configuration
# ======================================================================

RUN echo "=== ECMC build configuration ===" \
    && echo "ECMC_VERSION=${ECMC_VERSION}" \
    && grep -E \
       '^(MODULE|REQUIRED|asyn_VERSION|ARCH_FILTER|motorECMC_VERSION|ruckig_VERSION|LIB_SYS_LIBS|USR_CXXFLAGS_linux-|USR_LDFLAGS_linux-)' \
       GNUmakefile


# ======================================================================
# Build/install ECMC
#
# ECMC_REF selects source; ECMC_VERSION is the installed module name.
# ======================================================================

COPY container/patch-psi-install.py /tmp/patch-psi-install.py
RUN python3 /tmp/patch-psi-install.py
RUN make build \
       EPICS_VERSIONS=${EPICS_VERSION} \
       LIBVERSION=${ECMC_VERSION} \
    && make install \
       EPICS_VERSIONS=${EPICS_VERSION} \
       LIBVERSION=${ECMC_VERSION}


# ======================================================================
# Verify ECMC installation
# ======================================================================

RUN echo "=== Installed ECMC files ===" \
    && find \
       /ioc/modules/ecmc/${ECMC_VERSION}/R${EPICS_VERSION} \
       -maxdepth 4 \
       -type f \
       -print | sort \
    && test -f \
       /ioc/modules/ecmc/${ECMC_VERSION}/R${EPICS_VERSION}/lib/${EPICS_HOST_ARCH}/libecmc.so \
    && echo "ECMC ${ECMC_VERSION} successfully installed"

# ======================================================================
# ecmccomp
# ======================================================================

WORKDIR /opt

ARG ECMCCOMP_REPOSITORY=https://github.com/paulscherrerinstitute/ecmccomp.git
ARG ECMCCOMP_REF=a90964dea22323fcf797a9286044c0d0f68a9fce
ARG ECMCCOMP_VERSION=PSI_default
RUN checkout-source "$ECMCCOMP_REPOSITORY" "$ECMCCOMP_REF" /opt/ecmccomp

WORKDIR /opt/ecmccomp

RUN sed -i \
       's/^ARCH_FILTER[[:space:]]*=.*/ARCH_FILTER = linux-%/' \
       GNUmakefile \
    && grep -E '^(MODULE|ARCH_FILTER|EXCLUDE_VERSIONS)' GNUmakefile

RUN make build \
       EPICS_VERSIONS=${EPICS_VERSION} \
       LIBVERSION=${ECMCCOMP_VERSION} \
    && make install \
       EPICS_VERSIONS=${EPICS_VERSION} \
       LIBVERSION=${ECMCCOMP_VERSION}

RUN echo "=== Installed ecmccomp files ===" \
    && find \
       /ioc/modules/ecmccomp/${ECMCCOMP_VERSION}/R${EPICS_VERSION} \
       -maxdepth 3 \
       -type f \
       -print | sort | head -100 \
    && test -d \
       /ioc/modules/ecmccomp/${ECMCCOMP_VERSION}/R${EPICS_VERSION} \
    && echo "ecmccomp ${ECMCCOMP_VERSION} successfully installed"

# ======================================================================
# ecmccfg
# ======================================================================

WORKDIR /opt

ARG ECMCCFG_REPOSITORY=https://github.com/anderssandstrom/ecmccfg.git
ARG ECMCCFG_REF=aecae59837063ffe892b7e610430d42ca4e7243f
ARG ECMCCFG_VERSION=v11.2.0_RC1
RUN checkout-source "$ECMCCFG_REPOSITORY" "$ECMCCFG_REF" /opt/ecmccfg

WORKDIR /opt/ecmccfg


# ======================================================================
# Patch ecmccfg PSI wrapper for vanilla EPICS Linux
# ======================================================================

RUN sed -i \
       's/^ARCH_FILTER[[:space:]]*=.*/ARCH_FILTER = linux-%/' \
       GNUmakefile


# ======================================================================
# Display relevant ecmccfg build configuration
# ======================================================================

RUN echo "=== ecmccfg build configuration ===" \
    && echo "ECMC_VERSION=${ECMCCFG_VERSION}" \
    && grep -E \
       '^(MODULE|ARCH_FILTER|REQUIRED|.*_VERSION)' \
       GNUmakefile || true


# ======================================================================
# Build/install ecmccfg
#
# ecmccfg is installed using its own module version.
# ======================================================================

RUN make build \
       EPICS_VERSIONS=${EPICS_VERSION} \
       LIBVERSION=${ECMCCFG_VERSION} \
    && make install \
       EPICS_VERSIONS=${EPICS_VERSION} \
       LIBVERSION=${ECMCCFG_VERSION}


# ======================================================================
# Verify ecmccfg installation
# ======================================================================

RUN echo "=== Installed ecmccfg files ===" \
    && find \
       /ioc/modules/ecmccfg/${ECMCCFG_VERSION}/R${EPICS_VERSION} \
       -maxdepth 4 \
       -type f \
       -print | sort \
    && test -d \
       /ioc/modules/ecmccfg/${ECMCCFG_VERSION}/R${EPICS_VERSION} \
    && echo "ecmccfg ${ECMCCFG_VERSION} successfully installed"

# ======================================================================
# Start ecmc env
# ======================================================================

# Package Python once; ecmccfg must not pip-install dependencies at IOC startup.
COPY container/requirements.txt /opt/ecmc-python-requirements.txt
RUN python3 -m venv /opt/ecmc-python \
    && /opt/ecmc-python/bin/pip install --no-cache-dir -r /opt/ecmc-python-requirements.txt
COPY container/pythonVenv.sh /tmp/pythonVenv.sh
RUN install -m 644 /tmp/pythonVenv.sh /opt/ecmccfg/scripts/jinja2/pythonVenv.sh \
    && install -m 644 /tmp/pythonVenv.sh /ioc/modules/ecmccfg/${ECMCCFG_VERSION}/R${EPICS_VERSION}/pythonVenv.sh

# New sources keep the models in ecmccfg; older releases keep them in ecmc.
# Optional independent simulator ref for releases without either location.
ARG SIM_REPOSITORY=https://github.com/anderssandstrom/ecmccfg.git
ARG SIM_REF=
RUN if [[ -n "$SIM_REF" ]]; then \
        checkout-source "$SIM_REPOSITORY" "$SIM_REF" /opt/simulation-source; \
        cp -a /opt/simulation-source/tools/simulation /opt/ecmc-simulation; \
    elif [[ -f /opt/ecmccfg/tools/simulation/ioc.py ]]; then \
        cp -a /opt/ecmccfg/tools/simulation /opt/ecmc-simulation; \
    elif [[ -f /opt/ECMC_makefile/ecmc/tools/simulation/ioc.py ]]; then \
        cp -a /opt/ECMC_makefile/ecmc/tools/simulation /opt/ecmc-simulation; \
    else echo 'No hardware simulator available. Set SIM_REF to a compatible revision.' >&2; exit 1; fi \
    && python3 /opt/ecmc-simulation/ioc.py --help

RUN echo 'source /opt/ecmc-env.sh' >> /root/.bashrc
# iocsh loads misc automatically; ecmccfg uses its atInit hook.
ARG MISC_REF=cb1a0c758f7df59b7483c3c57e5946ae9a8117b2
RUN checkout-source https://github.com/paulscherrerinstitute/misc.git "$MISC_REF" /opt/misc \
    && printf '\nUSR_INCLUDES += -I%s/modules/database/src/ioc/rsrv\n' "$EPICS_BASE" >> /opt/misc/Makefile \
    && make -C /opt/misc build MODULE=misc EPICS_VERSIONS=${EPICS_VERSION} LIBVERSION=1.0.0 \
    && make -C /opt/misc install MODULE=misc EPICS_VERSIONS=${EPICS_VERSION} LIBVERSION=1.0.0 \
    && test -f /ioc/modules/misc/1.0.0/R${EPICS_VERSION}/lib/${EPICS_HOST_ARCH}/libmisc.so
COPY prepare-startup.py container/run-ioc.sh container/supervise.py /opt/ecmc-runner/
RUN chmod +x /opt/ecmc-runner/run-ioc.sh
RUN printf 'ecmc=%s\necmccfg=%s\necmccomp=%s\n' \
    "$ECMC_VERSION" "$ECMCCFG_VERSION" "$ECMCCOMP_VERSION" > /opt/module-versions.txt
WORKDIR /opt
CMD ["/bin/bash"]
