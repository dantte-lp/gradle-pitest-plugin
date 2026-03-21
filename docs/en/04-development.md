---
id: 04-development
title: Development Guide
sidebar_label: Development
---

# Development Guide

![Gradle](https://img.shields.io/badge/Gradle-9.4.1-02303A?logo=gradle)
![GraalVM](https://img.shields.io/badge/GraalVM-17%20%7C%2021%20%7C%2025-E2231A?logo=oracle)
![Groovy](https://img.shields.io/badge/Groovy-4.0-4298B8?logo=apachegroovy)
![Oracle Linux](https://img.shields.io/badge/Oracle%20Linux-10-F80000?logo=oracle)
![License](https://img.shields.io/badge/License-Apache%202.0-blue)

This guide covers setting up a local development environment, running the build and test pipeline, and following the code conventions expected for contributions.

**All build and test commands must run inside the dev container.** Do not invoke Gradle, quality tools, or functional tests directly on the host machine.

---

## Prerequisites

| Tool | Minimum Version | Purpose |
|------|----------------|---------|
| [Podman](https://podman.io/) | 4.x | OCI-compatible container runtime for the dev environment |
| [Git](https://git-scm.com/) | 2.x | Source control and cloning the repository |

No JDK, Gradle, or any quality tool needs to be installed on the host. Everything runs inside the container.

---

## Dev Container Setup

### Build the Image

From the repository root, build the development image once:

```bash
podman build -f deployment/containerfiles/Containerfile.dev -t pitest-plugin:dev .
```

Expected output ends with:

```
All tools installed
Successfully tagged localhost/pitest-plugin:dev
```

First build takes approximately 5 minutes (downloads SDKMAN, GraalVM distributions, and all scanner binaries).

### Start an Interactive Session

```bash
podman run --rm -it -v .:/workspace:Z pitest-plugin:dev
```

The working directory inside the container is `/workspace`, which is bind-mounted to the repository root. The `:Z` flag sets the correct SELinux label on Linux hosts.

### Run a Single Command Non-Interactively

```bash
podman run --rm -v .:/workspace:Z pitest-plugin:dev bash scripts/quality.sh full
```

---

## Container Contents

The image is based on **Oracle Linux 10** and installs all tooling via SDKMAN and direct binary downloads. No internet access is required after the image is built.

### JDK and Build Tool

| Component | Version | Notes |
|-----------|---------|-------|
| Oracle Linux | 10 | Base OS |
| GraalVM JDK 17 | 17.0.12-graal | Gradle toolchain target |
| GraalVM JDK 21 | 21.0.10-graal | Gradle toolchain target |
| GraalVM JDK 25 | 25.0.2-graal | Default JVM, `JAVA_HOME` |
| Gradle | 9.4.1 | Via SDKMAN, `GRADLE_HOME` |

GraalVM 25 is the active JVM at container startup. The Gradle toolchain mechanism automatically selects GraalVM 17 or 21 when a test project requests a specific Java version.

### Security and Quality Scanners

| Tool | Category | Version |
|------|----------|---------|
| [Semgrep](https://semgrep.dev/) | SAST | Latest via pip |
| [Trivy](https://trivy.dev/) | Vulnerability scanner | Latest |
| [Gitleaks](https://github.com/gitleaks/gitleaks) | Secret detection | 8.27.2 |
| [Grype](https://github.com/anchore/grype) | SCA vulnerabilities | Latest |
| [Syft](https://github.com/anchore/syft) | SBOM generator | Latest |
| [ShellCheck](https://www.shellcheck.net/) | Shell script linter | 0.11.0 |
| [Hadolint](https://github.com/hadolint/hadolint) | Containerfile linter | 2.12.0 |
| [OWASP Dependency-Check](https://owasp.org/www-project-dependency-check/) | SCA audit | 12.1.0 |

The JVM is configured with container-aware memory limits:

```
-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError
```

Gradle parallel builds and build caching are enabled by default via `GRADLE_OPTS`.

---

## nebula-test 12.0.0 Prerequisite

nebula-test 12.0.0 is **not published to Maven Central**. Before running functional tests (`funcTest`), you must build it from source, apply a Spock 2.x compatibility patch, and publish it to the container-local Maven cache.

### Why the Patch is Required

nebula-test 12.0.0 calls `testMethodName` via the JUnit 4 `TestName` rule. Under Spock 2.x running on the JUnit Platform, this method returns `null`, causing an NPE during test directory setup. The patch adds a `resolveMethodName()` fallback that reads from `specificationContext` when the JUnit rule returns null.

### Build and Install nebula-test

Run this inside the container (or as a non-interactive `podman run`):

```bash
source /root/.sdkman/bin/sdkman-init.sh
cd /tmp
git clone --depth 1 --branch v12.0.0 https://github.com/nebula-plugins/nebula-test.git
cd nebula-test

# Patch BaseIntegrationSpec — fix testMethodName NPE under Spock 2.x + JUnit Platform
cat > src/main/groovy/nebula/test/BaseIntegrationSpec.groovy << 'PATCH1'
package nebula.test
import groovy.transform.CompileStatic
import org.junit.Rule
import org.junit.rules.TestName
import spock.lang.Specification
@CompileStatic
@Deprecated(forRemoval = true)
abstract class BaseIntegrationSpec extends Specification implements IntegrationBase {
    @Rule TestName testName = new TestName()
    protected String resolveMethodName() {
        String mn = testName?.methodName
        if (mn == null) {
            try { mn = specificationContext?.currentIteration?.parent?.name ?: "test" }
            catch (ignored) { mn = "test" }
        }
        return mn
    }
    void setup() { IntegrationBase.super.initialize(getClass(), resolveMethodName()) }
}
PATCH1

# Patch IntegrationSpec — same NPE fix
cat > src/main/groovy/nebula/test/IntegrationSpec.groovy << 'PATCH2'
package nebula.test
import groovy.transform.CompileStatic
@CompileStatic
@Deprecated(forRemoval = true)
abstract class IntegrationSpec extends BaseIntegrationSpec implements Integration {
    def setup() { Integration.super.initialize(getClass(), resolveMethodName()) }
}
PATCH2

# Disable signing and publish to local Maven repository
cat > /tmp/no-sign.gradle << 'NOSIGN'
allprojects { tasks.withType(Sign) { enabled = false } }
NOSIGN

./gradlew publishToMavenLocal -x test -x javadoc \
    -Prelease.version=12.0.0 --no-scan -I /tmp/no-sign.gradle
```

Expected output ends with `BUILD SUCCESSFUL`.

**Important:** The Maven local repository (`~/.m2/repository`) is ephemeral inside a container — it exists only for the current container invocation. Steps that build nebula-test and steps that run `funcTest` must share the same container session, or you must use a volume to persist `~/.m2`.

---

## Build Commands

All commands must be run from `/workspace` inside the container.

### Core Tasks

```bash
# Compile + unit tests + CodeNarc + validatePlugins (the standard CI check)
./gradlew build

# Unit tests only
./gradlew test

# Functional tests (Nebula-based, spawns real Gradle builds)
./gradlew funcTest

# Functional tests — quick mode (latest Gradle only)
PITEST_REGRESSION_TESTS=latestOnly ./gradlew funcTest

# Functional tests — full matrix (Gradle 6.x through 9.4.1)
PITEST_REGRESSION_TESTS=full ./gradlew funcTest

# CodeNarc static analysis only
./gradlew codenarc

# Gradle plugin metadata validation
./gradlew validatePlugins

# Show all deprecation warnings (must produce zero output for production code)
./gradlew build --warning-mode=all
```

### Combined Verification

```bash
# Full verification identical to CI green gate
./gradlew clean build funcTest
```

Expected results:
- Unit tests: 142/142 pass
- Functional tests: 22 pass, 4 skipped (PIT/ASM limitation on JDK 25 — not plugin bugs)
- CodeNarc: 0 violations
- `validatePlugins`: 0 warnings
- Deprecation warnings: 0

---

## Quality Pipeline

`scripts/quality.sh` orchestrates the complete quality pipeline in four modes. Run it inside the container:

```bash
bash scripts/quality.sh <mode>
```

Or non-interactively:

```bash
podman run --rm -v .:/workspace:Z pitest-plugin:dev bash scripts/quality.sh full
```

### Modes

| Mode | Tools Executed | Approximate Duration |
|------|---------------|---------------------|
| `quick` | `./gradlew build` + ShellCheck + Hadolint | ~30 seconds |
| `full` | `build` + `test` + `funcTest` + `codenarc` + Semgrep + Trivy + Gitleaks | 5–10 minutes |
| `security` | Semgrep + Trivy + Gitleaks + OWASP Dependency-Check | 3–5 minutes |
| `lint` | ShellCheck + Hadolint + `codenarc` (via Gradle) | ~1 minute |

The script prints a summary with pass/fail/warn counts and exits with a non-zero code if any check fails.

---

## Development Workflow

```kroki-mermaid
flowchart TD
    A([Edit source code]) --> B[./gradlew build]
    B --> C{Build passes?}
    C -- No --> A
    C -- Yes --> D[./gradlew test]
    D --> E{Tests pass?}
    E -- No --> A
    E -- Yes --> F[./gradlew codenarc]
    F --> G{No violations?}
    G -- No --> A
    G -- Yes --> H[./gradlew funcTest]
    H --> I{funcTest passes?}
    I -- No --> A
    I -- Yes --> J[bash scripts/quality.sh full]
    J --> K{Quality gate passes?}
    K -- No --> A
    K -- Yes --> L([Ready to commit])

    style A fill:#4a4a6a,color:#fff
    style L fill:#2d6a2d,color:#fff
    style C fill:#6a2d2d,color:#fff
    style E fill:#6a2d2d,color:#fff
    style G fill:#6a2d2d,color:#fff
    style I fill:#6a2d2d,color:#fff
    style K fill:#6a2d2d,color:#fff
```

The recommended inner loop during development is `build` then `test`. Run `funcTest` only before submitting changes, as each functional test invocation spawns multiple real Gradle builds and takes significantly longer.

---

## Code Conventions

All production Groovy code must conform to the following conventions. CodeNarc enforces these rules automatically via `config/codenarc/codenarc.xml`.

### Static Compilation

All production classes must use `@CompileStatic`. Dynamic dispatch is prohibited in production code:

```groovy
import groovy.transform.CompileStatic

@CompileStatic
class PitestPlugin implements Plugin<Project> {
    // All method calls resolved at compile time
}
```

`@CompileDynamic` is permitted only in test code (`src/test/` and `src/funcTest/`).

### Provider API for Task Properties

All task inputs and outputs must use the Gradle Provider API. Never store raw values:

```groovy
// Correct — lazy, configuration-cache compatible
abstract class PitestTask extends JavaExec {
    @Input
    abstract Property<String> getPitestVersion()

    @Input
    abstract SetProperty<String> getTargetClasses()

    @OutputDirectory
    abstract DirectoryProperty getReportsDirectory()
}
```

| Provider Type | Use Case |
|--------------|----------|
| `Property<T>` | Single scalar value |
| `ListProperty<T>` | Ordered list |
| `SetProperty<T>` | Unordered set (de-duplicated) |
| `MapProperty<K, V>` | Key-value pairs |
| `DirectoryProperty` | Output/input directory path |
| `RegularFileProperty` | Output/input file path |

### Lazy Evaluation

Never resolve file properties at configuration time. Use lazy providers for all file resolution:

```groovy
// Correct — resolved at execution time
reportsDir = baseDirectory.dir("pitest")

// Incorrect — resolves at configuration time, breaks configuration cache
reportsDir = baseDirectory.asFile.get().toPath().resolve("pitest").toFile()
```

### Task Registration

Always use `tasks.register()` (lazy) instead of `tasks.create()` (eager):

```groovy
// Correct
tasks.register("pitest", PitestTask) { task ->
    task.pitestVersion.convention(DEFAULT_PITEST_VERSION)
}

// Incorrect — configures the task even when it is not needed
tasks.create("pitest", PitestTask)
```

### Abstract Task Classes

Task classes that extend `JavaExec` must be declared `abstract`. Groovy 4 enforces that abstract `@Inject` methods from `JavaExec` can only be implemented by the Gradle instantiator, not by a concrete subclass:

```groovy
abstract class PitestTask extends JavaExec {
    // Gradle instantiator provides @Inject constructors
}
```

### Removed APIs — Do Not Use

The following APIs were removed in Gradle 9 and must not appear anywhere in production code:

| Removed API | Replacement |
|-------------|-------------|
| `project.exec()` / `project.javaexec()` | Extend `JavaExec` task directly |
| `project.getConvention()` (Convention API) | Extension API |
| `project.buildDir` | `project.layout.buildDirectory` |
| `tasks.create()` | `tasks.register()` |
| `jcenter()` repository | `mavenCentral()` |
| `Configuration.visible = false` | No replacement needed (removed in 9.0) |

---

## Project Source Layout

```
src/
  main/groovy/info/solidsoft/gradle/pitest/
    PitestPlugin.groovy              # Main plugin entry point
    PitestPluginExtension.groovy     # DSL extension (pitest { ... } block)
    PitestTask.groovy                # Abstract task extending JavaExec (@CacheableTask)
    PitestAggregatorPlugin.groovy    # Multi-project report aggregator (@Incubating)
    AggregateReportTask.groovy       # Worker API task for report aggregation
    AggregateReportGenerator.groovy  # WorkAction implementation
    internal/
      GradleVersionEnforcer.groovy   # Minimum Gradle version enforcement
      GradleUtil.groovy              # Internal utilities

  test/groovy/                       # Unit tests (Spock, @CompileDynamic allowed)
  funcTest/groovy/                   # Functional tests (Nebula Test + Spock)

config/
  codenarc/codenarc.xml             # CodeNarc rule configuration

deployment/
  containerfiles/
    Containerfile.dev               # Development container definition

scripts/
  quality.sh                        # 4-mode quality pipeline orchestrator
```

---

## See Also

- `docs/TEST-INSTRUCTIONS.md` — step-by-step instructions for running the full test suite for PR verification
- `CLAUDE.md` — concise project reference for AI-assisted development
- `AGENTS.md` — agent configuration and quality gate checklist
- `config/codenarc/codenarc.xml` — CodeNarc rule definitions
