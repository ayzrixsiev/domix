#!/usr/bin/env bash
#
# Refuses an Android build that would fail on the JDK version, and says why.
#
# Yandex MapKit's Flutter plugin ships class files at version 65 (Java 21). A javac from JDK 17
# cannot read them at all, and what it prints is:
#
#   bad class file: .../YandexMapsPlugin.class
#   class file has wrong version 65.0, should be 61.0
#
# - several hundred lines into a Gradle log, naming neither Java nor the JDK. 65 is Java 21, 61 is
# Java 17.
#
# **It must resolve the JDK the way Flutter does, not the way the shell does**, and those two
# genuinely disagree on this machine. `flutter config --jdk-dir` points at JDK 21 while
# archlinux-java still has `java` on PATH as 17, so a naive `java -version` check reports 17 and
# blocks a build that works perfectly. Flutter's own order is: --jdk-dir, then JAVA_HOME, then
# Android Studio's bundled runtime, then PATH.

set -uo pipefail

readonly REQUIRED_MAJOR=21

# `flutter config --list` is authoritative and costs ~0.15s. Reading Flutter's settings file
# directly would be faster and wrong: its location moves with XDG_CONFIG_HOME (on this machine it is
# ~/.config/settings, not ~/.config/flutter/settings).
jdk_dir="$(flutter config --list 2>/dev/null | sed -n 's/^[[:space:]]*jdk-dir:[[:space:]]*//p')"

if [[ -n "$jdk_dir" ]]; then
    java_bin="$jdk_dir/bin/java"
    source_of_truth="flutter config --jdk-dir"
elif [[ -n "${JAVA_HOME:-}" ]]; then
    java_bin="$JAVA_HOME/bin/java"
    source_of_truth="JAVA_HOME"
else
    java_bin="$(command -v java || true)"
    source_of_truth="java on PATH"
fi

fail() {
    echo "$@" >&2
    echo >&2
    echo "  sudo pacman -S jdk21-openjdk" >&2
    echo "  flutter config --jdk-dir /usr/lib/jvm/java-21-openjdk" >&2
    echo >&2
    echo "In that order. Setting --jdk-dir to a path that does not exist yet takes the whole" >&2
    echo "Android toolchain down, and the build then fails with a bare 'Error: Build process" >&2
    echo "failed' that says nothing about Java. 'flutter config --jdk-dir=' undoes it." >&2
    exit 1
}

if [[ -z "$java_bin" ]]; then
    fail "ERROR: no Java found at all. The Android build needs JDK $REQUIRED_MAJOR or newer."
fi

# The exact trap that cost a debugging session: --jdk-dir set to a directory that does not exist.
# `flutter doctor` reports "Cannot execute .../bin/java", every build dies with an unexplained
# "Error: Build process failed", and nothing mentions the setting that caused it.
if [[ ! -x "$java_bin" ]]; then
    fail "ERROR: $source_of_truth points at $java_bin, which does not exist or is not executable."
fi

version_line="$("$java_bin" -version 2>&1 | head -1)"
# openjdk version "21.0.12" 2026-07-21  ->  21
major="$(sed -E 's/.*version "([0-9]+).*/\1/' <<<"$version_line")"

if [[ ! "$major" =~ ^[0-9]+$ ]]; then
    fail "ERROR: could not read a version out of: $version_line"
fi

if (( major < REQUIRED_MAJOR )); then
    fail "ERROR: the Android build needs JDK $REQUIRED_MAJOR or newer, but $source_of_truth gives
       $version_line
       Yandex MapKit's plugin is compiled with Java 21 and javac $major cannot read it."
fi
