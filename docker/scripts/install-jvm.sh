#!/usr/bin/env bash
# ==============================================================================
# OpenRig Module: JVM (SDKMAN! + Java + Kotlin + Spring Boot CLI + Maven + Gradle)
# ==============================================================================
set -euo pipefail

JAVA_DEFAULT_VERSION="${1:-21.0.5-tem}"
echo "☕ [OpenRig] Installing JVM Module via SDKMAN! (Java, Kotlin, Spring Boot, Maven, Gradle)..."

su - rig -c "
    set -eo pipefail
    export SDKMAN_DIR=\"\$HOME/.sdkman\"
    if [ ! -d \"\$SDKMAN_DIR\" ]; then
        curl -s \"https://get.sdkman.io?rcupdate=false\" | bash
    fi
    source \"\$SDKMAN_DIR/bin/sdkman-init.sh\"

    # Resolve latest Temurin 21 if exact version not found
    JAVA_VER=\$(sdk list java | grep -oE '21\\.[0-9]+\\.[0-9]+-tem' | head -n 1 || echo '${JAVA_DEFAULT_VERSION}')
    sdk install java \"\$JAVA_VER\" || sdk install java
    sdk install kotlin
    sdk install springboot
    sdk install maven
    sdk install gradle
    sdk flush archives
    sdk flush temp
"

echo "✅ [OpenRig] JVM module installed."
