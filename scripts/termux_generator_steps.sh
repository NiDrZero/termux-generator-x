# Funktion, um den Paketnamen zu überprüfen
check_names() {
    if [[ $TERMUX_APP__PACKAGE_NAME =~ '_' ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME =~ '-' ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == package ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == package.* ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == *.package ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == *.package.* ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == in ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == in.* ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == *.in ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == *.in.* ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == is ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == is.* ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == *.is ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == *.is.* ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == as ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == as.* ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == *.as ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == *.as.* ]]
    then
        echo "[!] Package name must not contain underscores, dashes, or invalid patterns!"
        exit 2
    fi

    if [[ $TERMUX_APP__PACKAGE_NAME == *"com.termux"* ]] && \
        [[ "$TERMUX_APP__PACKAGE_NAME" != "com.termux" ]]; then
        echo "[!] Sorry, please choose a unique custom name that does not contain 'com.termux'"
        echo "(and is not an exact substring of it either) to avoid side effects."
        echo "Examples: 'com.test.termux' is OK, but 'com.termux.test' or 'com.ter' could have side effects."
        exit 2
    fi

    if [[ $ADDITIONAL_PACKAGES == *"termux-x11-nightly"* ]]; then
        echo "[!] That version of termux-x11-nightly is precompiled and"
        echo "cannot be compiled by termux-generator with any custom name inserted!"
        echo "To use termux-x11-nightly with termux-generator, just set"
        echo "'--type f-droid', then install the .apk files termux-generator builds."
        echo "A source-built and patched 'termux-x11-nightly' package is"
        echo "automatically preinstalled."
        exit 2
    fi
}

clean_docker() {
    docker container kill "$TERMUX_GENERATOR_CONTAINER_NAME" 2> /dev/null || true
    docker container rm -f "$TERMUX_GENERATOR_CONTAINER_NAME" 2>/dev/null || true
    if ! docker image rm ghcr.io/termux/package-builder 2>/dev/null; then
        echo "[*] Warning: not removing Docker package builder image for \"F-Droid\" Termux, likely because it is either not downloaded yet, or in use by other containers."
    fi
    if ! docker image rm ghcr.io/termux-play-store/package-builder 2>/dev/null; then
        echo "[*] Warning: not removing Docker package builder image for \"Google Play\" Termux, likely because it is either not downloaded yet, or in use by other containers."
    fi
}

clean_artifacts() {
    rm -rf termux* *.apk *.deb *.xz *.zip 2>/dev/null
}

# Funktion, um Repositories herunterzuladen
download() {
    if [[ "$TERMUX_APP_TYPE" == "f-droid" ]]; then
        git_clone_retry --depth 1 https://github.com/termux/termux-packages.git               termux-packages-main
        
        if [ -z "${DISABLE_TASKER}" ]; then
            git_clone_retry --depth 1 https://github.com/termux/termux-tasker.git termux-apps-main/termux-tasker
        fi
        if [ -z "${DISABLE_FLOAT}" ]; then
            git_clone_retry --depth 1 https://github.com/termux/termux-float.git termux-apps-main/termux-float
        fi
        if [ -z "${DISABLE_WIDGET}" ]; then
            git_clone_retry --depth 1 https://github.com/termux/termux-widget.git termux-apps-main/termux-widget
        fi
        if [ -z "${DISABLE_API}" ]; then
            git_clone_retry --depth 1 https://github.com/termux/termux-api.git termux-apps-main/termux-api
        fi
        if [ -z "${DISABLE_BOOT}" ]; then
            git_clone_retry --depth 1 https://github.com/termux/termux-boot.git termux-apps-main/termux-boot
        fi
        if [ -z "${DISABLE_STYLING}" ]; then
            git_clone_retry --depth 1 https://github.com/termux/termux-styling.git termux-apps-main/termux-styling
        fi
        if [ -z "${DISABLE_TERMINAL}" ]; then
            git_clone_retry --depth 1 https://github.com/termux/termux-app.git termux-apps-main/termux-app
        fi
        if [ -z "${DISABLE_GUI}" ]; then
            git_clone_retry --depth 1 https://github.com/termux/termux-gui.git termux-apps-main/termux-gui
        fi
        
        if [ -z "${DISABLE_TERMINAL}" ]; then
            # special case - for "F-Droid" Termux, it is necessary to move the termux-am-library subfolder of
            # the termux-am-library repository, which contains its actual code, into the termux-app folder,
            # where its code needs to be patched and compiled into the main "F-Droid" Termux APK
            git_clone_retry --depth 1 https://github.com/termux/termux-am-library.git             termux-apps-main/termux-am-library
            mv termux-apps-main/termux-am-library/termux-am-library/                        termux-apps-main/termux-app/termux-am-library
            rm -rf                                                                          termux-apps-main/termux-am-library/
        fi
    else
        git_clone_retry --depth 1 https://github.com/termux-play-store/termux-packages.git    termux-packages-main
        git_clone_retry --depth 1 https://github.com/termux-play-store/termux-apps.git        termux-apps-main
    fi
    if [ -z "${DISABLE_X11}" ]; then
        git_clone_retry --depth 1 --recursive https://github.com/termux/termux-x11.git termux-apps-main/termux-x11
    fi
}

install_plugin() {
    apply_patches "plugins/$TERMUX_GENERATOR_PLUGIN/$TERMUX_APP_TYPE-patches/bootstrap-patches" termux-packages-main
    apply_patches "plugins/$TERMUX_GENERATOR_PLUGIN/$TERMUX_APP_TYPE-patches/app-patches" termux-apps-main
}

# Funktion, um Bootstrap-Patches anzuwenden
patch_bootstraps() {
    # The reason why it is necessary to replace the name first, then patch bootstraps, but do the reverse for apps,
    # is because command-not-found must be partially unpatched back to the default TERMUX_PREFIX to build,
    # so that patch must apply after the bootstraps' name replacement has completed, but the apps contain the
    # string "com.termux" in their code in many more places than the bootstraps do, so it's easier to patch them first.
    if [[ "$TERMUX_APP__PACKAGE_NAME" != "com.termux" ]]; then
        replace_termux_name termux-packages-main "$TERMUX_APP__PACKAGE_NAME"
    fi

    apply_patches "$TERMUX_APP_TYPE-patches/bootstrap-patches" termux-packages-main

    portable_sed_i -e "s|termux-package-builder|$TERMUX_GENERATOR_CONTAINER_NAME|g" termux-packages-main/scripts/run-docker.sh

    local bashrc="termux-packages-main/packages/bash/etc-bash.bashrc"

    if [[ -n "$ENABLE_SSH_SERVER" ]]; then
        if ! grep -q "start-sshd" "$bashrc" 2>/dev/null; then
            cat <<- EOF >> "$bashrc"
                if [ ! -f "\$HOME/.termux/boot/start-sshd" ]; then
                    mkdir -p "\$HOME/.termux/boot"
                    echo '#!/data/data/$TERMUX_APP__PACKAGE_NAME/files/usr/bin/sh' > "\$HOME/.termux/boot/start-sshd"
                    echo '. /data/data/$TERMUX_APP__PACKAGE_NAME/files/usr/etc/bash.bashrc' >> "\$HOME/.termux/boot/start-sshd"
                    chmod +x "\$HOME/.termux/boot/start-sshd"
                fi
                if [ ! -f "\$HOME/.termux_authinfo" ]; then
                    printf '$DEFAULT_PASSWORD\n$DEFAULT_PASSWORD' | passwd
                fi
                sshd
EOF
        fi
    fi

    cp -f "$TERMUX_GENERATOR_HOME/scripts/termux_generator_utils.sh" termux-packages-main/scripts/
}

# Funktion, um die App zu patchen
patch_apps() {
    if [ ! -d "termux-apps-main" ]; then
        return
    fi

    apply_patches "$TERMUX_APP_TYPE-patches/app-patches" termux-apps-main

    if [[ "$TERMUX_APP__PACKAGE_NAME" == "com.termux" ]]; then
        return
    fi

    replace_termux_name termux-apps-main "$TERMUX_APP__PACKAGE_NAME"

    migrate_termux_folder_tree termux-apps-main "$TERMUX_APP__PACKAGE_NAME"
}

# Common Gradle optimization flags
GRADLE_FLAGS="--parallel --build-cache --configure-on-demand --daemon"

build_termux_x11() {
    pushd termux-apps-main/termux-x11

    ./gradlew $GRADLE_FLAGS assembleDebug
    ./build_termux_package

    popd
}


move_termux_x11_deb() {
    pushd termux-apps-main/termux-x11

    if [[ "$TERMUX_APP_TYPE" == "f-droid" ]]; then
        local termux_x11_dest="$TERMUX_GENERATOR_HOME/termux-packages-main/output"
    else
        local termux_x11_dest="$TERMUX_GENERATOR_HOME/termux-packages-main"
    fi

    mkdir -p "$termux_x11_dest"
    # Iterate over any .deb files to avoid wildcard expansion issues with mv destination
    for deb in app/build/outputs/apk/debug/*.deb; do
        if [ -f "$deb" ]; then
            mv "$deb" "$termux_x11_dest/termux-x11-nightly_all.deb"
            break # Expecting only one relevant .deb, or just take the first one
        fi
    done

    popd
}

# Funktion, um Bootstraps zu erstellen
build_bootstraps() {
    pushd termux-packages-main

    local bootstrap_script_args=""

    if [ -n "$ENABLE_SSH_SERVER" ]; then
        ADDITIONAL_PACKAGES+=",openssh"
    fi

    bootstrap_script_args+=" --add ${ADDITIONAL_PACKAGES}"

    if [[ "$TERMUX_APP_TYPE" == "f-droid" ]]; then
        local bootstrap_script="build-bootstraps.sh"
        local bootstrap_architectures="aarch64,x86_64,arm,i686"
        if [ -n "${DISABLE_BOOTSTRAP_SECOND_STAGE-}" ]; then
            bootstrap_script_args+=" --disable-bootstrap-second-stage"
        fi
    else
        local bootstrap_script="generate-bootstraps.sh"
        local bootstrap_architectures="aarch64,x86_64,arm"
        bootstrap_script_args+=" --build"
    fi

    if [ -n "${BOOTSTRAP_ARCHITECTURES}" ]; then
        bootstrap_architectures="$BOOTSTRAP_ARCHITECTURES"
    fi

    bootstrap_script_args+=" --architectures $bootstrap_architectures"

    if [[ "${CI-}" == "true" ]]; then
        scripts/free-space.sh
    fi

    # Replace symbolic link /system which is inside the termux-package-builder docker image
    # pointed to /data/data/com.termux/aosp by default
    # https://github.com/termux/termux-packages/blob/650907de80114cc53b20b181161f993e3ad0dfad/scripts/setup-ubuntu.sh#L371
    # needed for building pypy and similar packages
    scripts/run-docker.sh sudo ln -sf "/data/data/$TERMUX_APP__PACKAGE_NAME/aosp" /system

    rm -rf .github/workflows/*
    sed -e "s|@TERMUX_APP__PACKAGE_NAME@|$TERMUX_APP__PACKAGE_NAME|g" \
        -e "s|@BOOTSTRAP_BUILD_COMMAND@|scripts/$bootstrap_script $bootstrap_script_args|g" \
        "$TERMUX_GENERATOR_HOME/scripts/build-bootstraps.yml.in" \
        > .github/workflows/build-bootstraps.yml

    scripts/run-docker.sh "scripts/$bootstrap_script" $bootstrap_script_args

    popd
}

# Funktion, um Bootstraps zu kopieren
move_bootstraps() {
    if [[ "$TERMUX_APP_TYPE" == "f-droid" ]]; then
        local app_assets_dir="app/src/main/assets/"
    else
        local app_assets_dir="src/main/assets/"
    fi
    if [ -z "${DISABLE_TERMINAL}" ]; then
        mkdir -p "termux-apps-main/termux-app/$app_assets_dir"
        mv termux-packages-main/bootstrap-*.zip "termux-apps-main/termux-app/$app_assets_dir"
    else
        for zip in termux-packages-main/bootstrap-*.zip; do
            mv "$zip" "$TERMUX_APP__PACKAGE_NAME-$TERMUX_APP_TYPE-$(basename $zip)"
        done
    fi
}

# Funktion, um die App zu bauen
build_apps() {
    pushd termux-apps-main

    if [[ "$TERMUX_APP_TYPE" == "f-droid" ]]; then
        if [ -z "${DISABLE_TERMINAL}" ]; then
pushd termux-app
    OLD_JAVA_HOME="$JAVA_HOME"
    unset JAVA_HOME
    ./gradlew $GRADLE_FLAGS publishReleasePublicationToMavenLocal
    export JAVA_HOME="$OLD_JAVA_HOME"
popd
        fi
        for app in *; do
            if [[ "$app" == "termux-app" ]] && [[ -n "${DISABLE_TERMINAL}" ]]; then
                continue
            fi
            if [[ "$app" == "termux-tasker" ]] && [[ -n "${DISABLE_TASKER}" ]]; then
                continue
            fi
            if [[ "$app" == "termux-float" ]] && [[ -n "${DISABLE_FLOAT}" ]]; then
                continue
            fi
            if [[ "$app" == "termux-widget" ]] && [[ -n "${DISABLE_WIDGET}" ]]; then
                continue
            fi
            if [[ "$app" == "termux-api" ]] && [[ -n "${DISABLE_API}" ]]; then
                continue
            fi
            if [[ "$app" == "termux-boot" ]] && [[ -n "${DISABLE_BOOT}" ]]; then
                continue
            fi
            if [[ "$app" == "termux-styling" ]] && [[ -n "${DISABLE_STYLING}" ]]; then
                continue
            fi
            if [[ "$app" == "termux-gui" ]] && [[ -n "${DISABLE_GUI}" ]]; then
                continue
            fi
            if [[ "$app" == "termux-x11" ]]; then
                continue
            fi
            
            # Build apps in parallel
            (
                echo "[*] Building $app in background..."
                pushd "$app" > /dev/null
                ( unset JAVA_HOME; ./gradlew $GRADLE_FLAGS assembleDebug ) > "build-$app.log" 2>&1
                if [ $? -eq 0 ]; then
                    echo "[+] $app build successful."
                else
                    echo "[!] $app build failed. Check termux-apps-main/$app/build-$app.log"
                fi
                popd > /dev/null
            ) &
        done
        wait
    else
        ./gradlew $GRADLE_FLAGS assembleDebug
    fi

    popd
}

# Funktion, um die APK zu kopieren
move_apks() {
    if [[ "$TERMUX_APP_TYPE" == "f-droid" ]]; then
        local build_dir="app/build/outputs/apk/debug"
    else
        local build_dir="build/outputs/apk/debug"
    fi

    if [ -z "${DISABLE_X11}" ]; then
        for apk in termux-apps-main/termux-x11/app/build/outputs/apk/debug/*.apk; do
            mv "$apk" "$TERMUX_APP__PACKAGE_NAME-$TERMUX_APP_TYPE-$(basename $apk)"
        done
    fi

    if [[ -z "${DISABLE_TERMINAL}" ]] || \
        [[ -z "${DISABLE_TASKER}" ]] || \
        [[ -z "${DISABLE_FLOAT}" ]] || \
        [[ -z "${DISABLE_WIDGET}" ]] || \
        [[ -z "${DISABLE_API}" ]] || \
        [[ -z "${DISABLE_BOOT}" ]] || \
        [[ -z "${DISABLE_STYLING}" ]] || \
        [[ -z "${DISABLE_GUI}" ]]; then
        for apk in termux-apps-main/*/"$build_dir"/*.apk; do
            mv "$apk" "$TERMUX_APP__PACKAGE_NAME-$TERMUX_APP_TYPE-$(basename $apk)"
        done
    fi
}
