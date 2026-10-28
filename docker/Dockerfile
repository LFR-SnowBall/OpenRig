# ==============================================================================
# OpenRig — Modular Portable Workstation Dockerfile
# Supports: ARM64 (Apple Silicon M1/M2/M3/M4) & AMD64 (Windows/Linux Intel/Ryzen)
# ==============================================================================
FROM ubuntu:24.04

LABEL org.opencontainers.image.title="OpenRig Portable Workstation"
LABEL org.opencontainers.image.description="Modular, zero-host-pollution developer & security rig in a container"
LABEL org.opencontainers.image.vendor="LFR-SnowBall"
LABEL org.opencontainers.image.authors="Luis Fernando Real <luisitoreal01@gmail.com>"

# Module toggles (set via .env / './rig setup')
ARG INSTALL_PYTHON=true
ARG INSTALL_JVM=true
ARG INSTALL_NODE=true
ARG INSTALL_MOBILE=false
ARG INSTALL_SWIFT=false
ARG INSTALL_CLOUD=true
ARG INSTALL_SEC=true
ARG INSTALL_AI=true

# Default toolchain versions
ARG PYTHON_DEFAULT_VERSION=3.12
ARG NODE_DEFAULT_VERSION=22
ARG JAVA_DEFAULT_VERSION=21.0.5-tem

# 1. Always install Base Workstation + Docker CLI (Sibling Container support)
COPY docker/scripts/install-base.sh /tmp/rig-scripts/install-base.sh
RUN chmod +x /tmp/rig-scripts/install-base.sh && /tmp/rig-scripts/install-base.sh

# Copy remaining modular installation scripts
COPY docker/scripts /tmp/rig-scripts
RUN chmod +x /tmp/rig-scripts/*.sh

# 2. Optional Module: Python (uv, pyenv, Django, Flask, FastAPI, Ruff, Pytest, Debugpy)
RUN if [ "$INSTALL_PYTHON" = "true" ]; then \
        /tmp/rig-scripts/install-python.sh "$PYTHON_DEFAULT_VERSION"; \
    fi

# 3. Optional Module: JVM (SDKMAN!, Java, Kotlin, Spring Boot, Maven, Gradle)
RUN if [ "$INSTALL_JVM" = "true" ]; then \
        /tmp/rig-scripts/install-jvm.sh "$JAVA_DEFAULT_VERSION"; \
    fi

# 4. Optional Module: Node & Frontend (nvm, Node, Vue.js, React, Vite, pnpm, Yarn, Bun)
RUN if [ "$INSTALL_NODE" = "true" ]; then \
        /tmp/rig-scripts/install-node.sh "$NODE_DEFAULT_VERSION"; \
    fi

# 5. Optional Module: Mobile (Flutter, FVM, Dart, Android SDK CLI, ADB)
RUN if [ "$INSTALL_MOBILE" = "true" ]; then \
        /tmp/rig-scripts/install-mobile.sh; \
    fi

# 6. Optional Module: Swift (Official Swift Linux SDK)
RUN if [ "$INSTALL_SWIFT" = "true" ]; then \
        /tmp/rig-scripts/install-swift.sh; \
    fi

# 7. Optional Module: Cloud & DevOps (AWS CLI v2, kubectl, Postgres/Redis CLI, gh)
RUN if [ "$INSTALL_CLOUD" = "true" ]; then \
        /tmp/rig-scripts/install-cloud.sh; \
    fi

# 8. Optional Module: Security, AppSec & Pentesting (nmap, nuclei, trivy, gitleaks, semgrep, sqlmap)
RUN if [ "$INSTALL_SEC" = "true" ]; then \
        /tmp/rig-scripts/install-sec.sh; \
    fi

# 9. Optional Module: AI Coding CLIs (Claude Code, Gemini CLI, Codex, Aider)
RUN if [ "$INSTALL_AI" = "true" ]; then \
        /tmp/rig-scripts/install-ai.sh; \
    fi

# Clean up installer scripts
RUN rm -rf /tmp/rig-scripts

# Copy entrypoint
COPY docker/entrypoint.sh /usr/local/bin/openrig-entrypoint.sh
RUN chmod +x /usr/local/bin/openrig-entrypoint.sh

USER rig
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/openrig-entrypoint.sh"]
CMD ["sleep", "infinity"]
