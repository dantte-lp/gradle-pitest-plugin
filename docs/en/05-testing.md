---
id: testing
title: Testing Guide
sidebar_label: Testing
---

# Testing Guide

![Spock](https://img.shields.io/badge/Spock-2.4--groovy--4.0-green?style=flat-square)
![Nebula Test](https://img.shields.io/badge/Nebula_Test-12.0.0-blue?style=flat-square)
![Unit Tests](https://img.shields.io/badge/Unit_Tests-142-brightgreen?style=flat-square)
![Functional Tests](https://img.shields.io/badge/Functional_Tests-22_active%20%2F%204_skipped-yellow?style=flat-square)
![CodeNarc](https://img.shields.io/badge/CodeNarc-2.0.0-orange?style=flat-square)

> This guide describes the test pyramid, how to run each layer, Gradle version regression matrix, PIT version compatibility filtering, and static analysis configuration.

---

## Test Pyramid

The project uses a three-layer test pyramid. Each layer increases scope and execution time while decreasing quantity.

```kroki-mermaid
graph TD
    A["Unit Tests<br/>142 tests · Spock 2.4<br/>ProjectBuilder (in-process)<br/>./gradlew test"]
    B["Functional Tests<br/>22 active + 4 skipped · nebula-test<br/>Spawns real Gradle builds<br/>./gradlew funcTest"]
    C["Gradle Version Regression<br/>PITEST_REGRESSION_TESTS matrix<br/>6.x → 9.4.1<br/>./gradlew funcTest (full mode)"]

    C --> B --> A

    style A fill:#2e7d32,color:#fff
    style B fill:#1565c0,color:#fff
    style C fill:#6a1b9a,color:#fff
```

| Layer | Count | Framework | Scope | Speed |
|---|---|---|---|---|
| Unit | 142 | Spock 2.4-groovy-4.0 | In-process `ProjectBuilder` | Fast (seconds) |
| Functional | 22 active + 4 skipped | nebula-test 12.0.0 `IntegrationSpec` | Spawns real Gradle builds | Slow (minutes) |
| Gradle regression | variable | Functional tests parameterized | Multiple Gradle versions | Very slow |

---

## Unit Tests

### Overview

Unit tests live in `src/test/groovy/info/solidsoft/gradle/pitest/` and use the Gradle `ProjectBuilder` API to create in-process Gradle projects. This avoids spawning external processes, making the tests fast.

All test classes extend Spock's `Specification` directly or share setup via the `BasicProjectBuilderSpec` base class.

### Base Setup: `BasicProjectBuilderSpec`

`BasicProjectBuilderSpec` is the shared base for ProjectBuilder-based tests. It:

- Creates a temporary project directory via `@TempDir`.
- Applies the `java` and `info.solidsoft.pitest` plugins.
- Retrieves the `PitestPluginExtension` instance.
- Sets `project.group = 'test.group'` to satisfy the `targetClasses` requirement.
- Creates a stub empty classpath file to satisfy `useClasspathFile = true` (the default since [#237](https://github.com/szpak/gradle-pitest-plugin/issues/237)).
- Marks all tasks as `EXECUTED` at configuration time so that lazy property providers can be resolved without errors.

```groovy
class BasicProjectBuilderSpec extends Specification {

    @TempDir
    protected File tmpProjectDir

    protected Project project
    protected PitestPluginExtension pitestConfig

    void setup() {
        project = ProjectBuilder.builder().withProjectDir(tmpProjectDir).build()
        project.pluginManager.apply('java')
        project.pluginManager.apply('info.solidsoft.pitest')
        pitestConfig = project.getExtensions().getByType(PitestPluginExtension)
        project.group = 'test.group'
        // creates stub pit-additional-classpath file so useClasspathFile=true doesn't fail
        rouchEmptyPitClasspathFileWorkaround(project)
        project.tasks.configureEach {
            state.outcome = TaskExecutionOutcome.EXECUTED
        }
    }
}
```

### Test Classes

| Class | Description |
|---|---|
| `PitestPluginTest` | Plugin registration, task group, lazy Java plugin wiring |
| `PitestPluginExtensionTest` | Extension defaults and property types |
| `PitestTaskConfigurationSpec` | Task argument construction, parameter-to-CLI mapping |
| `PitestTaskPluginConfigurationTest` | Plugin configuration applied to task |
| `PitestTaskTestPluginConfigurationSpec` | Test plugin options applied to task |
| `PitestTaskIncrementalAnalysisTest` | `historyInputLocation` / `historyOutputLocation` wiring |
| `PitestPluginClasspathFilteringSpec` | Classpath exclusion and filtering logic |
| `PitestPluginTargetClassesTest` | `targetClasses` derivation from `project.group` |
| `PitestPluginTypesConversionTest` | Property type conversions (Boolean, Integer, Charset) |
| `PitestAggregatorPluginTest` | Aggregator plugin registration and task wiring |

### Running Unit Tests

```bash
./gradlew test
```

Reports are written to `build/reports/tests/test/index.html`.

The build listener enforces that **at least one test was found** — the build fails with `IllegalStateException` if `testCount == 0`. This prevents silent no-op runs.

---

## Functional Tests

### Overview

Functional tests live in `src/funcTest/groovy/info/solidsoft/gradle/pitest/functional/`. They use the `nebula-test` `IntegrationSpec` to spawn real Gradle builds in a temporary directory on the filesystem.

> **Important:** nebula-test 12.0.0 is not published to Maven Central. It must be built from source (tag `v12.0.0`) with a Spock 2.x `testMethodName` patch and installed to `mavenLocal` before running functional tests.

All functional test classes extend `AbstractPitestFunctionalSpec`, which itself extends `IntegrationSpec` and provides:

- `fork = true` — required for stdout capture with Gradle Tooling API.
- `memorySafeMode = true` — shuts down the Gradle Daemon after a few seconds of inactivity.
- `enableConfigurationCache()` — writes `org.gradle.configuration-cache=true` into `gradle.properties` for every test project.
- Helper methods: `getBasicGradlePitestConfig()`, `writeHelloPitClass()`, `writeHelloPitTest()`.

### Functional Test Classes

| Class | Active Tests | Notes |
|---|---|---|
| `PitestPluginGeneralFunctionalSpec` | 4 | General plugin behavior, build cache, charset |
| `PitestPluginGradleVersionFunctionalSpec` | 1 (parameterized) | Gradle version matrix, version enforcement |
| `PitestPluginPitVersionFunctionalSpec` | 1 (parameterized) | PIT version compatibility |
| `Junit5FunctionalSpec` | 6 | JUnit 5, Kotlin + JUnit 5, Spock 2, configuration cache |
| `OverridePluginFunctionalSpec` | 2 active | Command-line overrides via `@Option` |
| `AcceptanceTestsInSeparateSubprojectFunctionalSpec` | 2 | Multi-project builds, report aggregation |
| `TargetClassesFunctionalSpec` | 1 | Error when `targetClasses` not configured |
| `TestFixturesFunctionalSpec` | 2 | `java-test-fixtures` source set support |

### Running Functional Tests

```bash
./gradlew funcTest
```

Functional tests run after unit tests (`funcTest.shouldRunAfter test`) and before `check` (`check.shouldRunAfter funcTest`). The combined report is generated by the `testReport` task:

```bash
./gradlew testReport
```

The combined report merges binary results from both `test` and `funcTest` into `build/reports/allTests/`.

---

## Gradle Version Regression Matrix

`PitestPluginGradleVersionFunctionalSpec` contains the full version matrix. The test is parameterized — one test case is generated per Gradle version entry.

### Version Lists

| Constant | Versions |
|---|---|
| `GRADLE6_VERSIONS` | `6.9.2`, `6.8.3`, `6.7`, `6.6`, `6.5`, `8.4` (minimal supported) |
| `GRADLE7_VERSIONS` | `7.6.4`, `7.5.1`, `7.4.2`, `7.4.1`, `7.3.3`, `7.2`, `7.1.1`, `7.0.2` |
| `GRADLE8_VERSIONS` | `8.14.3`, `8.13`, `8.12.1`, `8.11.1`, `8.10.2`, `8.9`, `8.8`, `8.7`, `8.6.4`, `8.5`, `8.4`, `8.3`, `8.2.1`, `8.1.1`, `8.0.2` |
| `GRADLE9_VERSIONS` | `9.4.1`, `9.4.0`, `9.3.0`, `9.2.0`, `9.1.0`, `9.0.0` |
| `GRADLE_LATEST_VERSIONS` | One latest from each major series + minimal supported (`8.4`) |

### `PITEST_REGRESSION_TESTS` Environment Variable

The set of Gradle versions tested is controlled by the `PITEST_REGRESSION_TESTS` environment variable:

| Value | Versions tested | Typical use |
|---|---|---|
| `latestOnly` (default) | One latest per major series | CI, day-to-day development |
| `quick` | Same as `latestOnly` | Alias for `latestOnly` |
| `full` | All versions across all four lists | Pre-release validation |
| _(unset)_ | Same as `latestOnly` | Default behaviour |

```bash
# Default (latestOnly) — fastest
./gradlew funcTest

# Full matrix — all supported Gradle versions
PITEST_REGRESSION_TESTS=full ./gradlew funcTest

# Explicit latestOnly
PITEST_REGRESSION_TESTS=latestOnly ./gradlew funcTest
```

Any unrecognised value triggers a warning and falls back to `latestOnly`.

### Java / Gradle Compatibility Filtering

The test automatically filters out Gradle versions that do not support the JDK currently running the build. This prevents test failures caused by genuine Gradle / JDK incompatibilities rather than plugin bugs:

| JDK | Minimum Gradle |
|---|---|
| JDK 15 | 6.7 |
| JDK 16 | 7.0.2 |
| JDK 17 | 7.2 |
| JDK 21 | 8.4 |
| JDK 22 | 8.7 |
| JDK 23 | 8.10 |
| JDK 24 | 8.14 |
| JDK 25 | 9.4.1 |

If after filtering fewer than two versions remain, the minimum compatible version is added automatically to ensure at least one meaningful test case runs.

---

## PIT Version Compatibility Testing

`PitestPluginPitVersionFunctionalSpec` verifies that the plugin works correctly with multiple PIT releases. The test is parameterized over a version list computed at runtime.

### Base Version List

| PIT Version | Notes |
|---|---|
| `1.7.1` | Minimum supported (verbosity flag introduced September 2021) |
| `1.17.1` | Intermediate release |
| `1.18.0` | Intermediate release |
| `1.23.0` | Current default (`DEFAULT_PITEST_VERSION`) |

### JDK-Based Filtering

The version list is filtered at runtime based on the JDK running the build:

| Condition | Effect |
|---|---|
| JDK > 17 | `1.7.1` is removed (ASM limitations on newer class files) |
| JDK >= 25 | All PIT versions < `1.19.0` are removed (ASM 9.7.x does not support class file version 69) |

**Root cause:** PIT versions prior to `1.19.0` bundle ASM 9.7.x, which cannot parse JDK 25 class files (class file format version 69). Any PIT version that would fail to instrument the test project under the current JDK is excluded before the test parameterization is built.

### What Each Parameterized Case Verifies

```
result.standardOutput.contains("Using PIT: ${pitVersion}")
result.standardOutput.contains("pitest-${pitVersion}.jar")
result.standardOutput.contains('Generated 2 mutations Killed 1 (50%)')
result.standardOutput.contains('Ran 2 tests (1 tests per mutation)')
```

---

## Known Skipped Tests

The following tests are explicitly skipped under specific runtime conditions. Skipping is implemented via Spock's `@IgnoreIf` or `@PendingFeature` annotations.

| Test | Class | Mechanism | Condition | Reason |
|---|---|---|---|---|
| `allow to use RegularFileProperty @Input and @Output fields in task` | `PitestPluginGeneralFunctionalSpec` | `@IgnoreIf` | `Runtime.version().feature() >= 25` | PIT crashes with `historyInputLocation` on JDK 25+ due to an internal PIT error unrelated to the plugin |
| `should fail with meaningful error message with too old Gradle version` | `PitestPluginGradleVersionFunctionalSpec` | `@IgnoreIf` | `javaVersion >= 13` | No unsupported Gradle version exists that is compatible with JDK 13+; test cannot exercise the intended failure path |
| `should allow to override String configuration parameter from command line` | `OverridePluginFunctionalSpec` | `@PendingFeature` | Always (known limitation) | `gradle-override-plugin` and `@Option` do not work with `DirectoryProperty`; expected to fail with `GradleException` |
| `should allow to define features from command line and override those from configuration` | `OverridePluginFunctionalSpec` | `@PendingFeature` | Always (known limitation) | Not yet implemented due to Gradle limitations with list-type `@Option` overrides; tracked in [#139](https://github.com/szpak/gradle-pitest-plugin/issues/139) |

---

## Test Execution Flow

```kroki-mermaid
sequenceDiagram
    participant Dev as Developer
    participant Gradle as Gradle Build
    participant JUnit as JUnit Platform
    participant PB as ProjectBuilder (unit)
    participant NB as nebula-test (func)
    participant ExtG as External Gradle Process

    Dev->>Gradle: ./gradlew test
    Gradle->>JUnit: useJUnitPlatform()
    JUnit->>PB: Run Spock specs
    PB->>PB: apply plugins in-process
    PB-->>JUnit: assertions pass / fail
    JUnit-->>Gradle: 142 tests complete

    Dev->>Gradle: ./gradlew funcTest
    Gradle->>JUnit: useJUnitPlatform()
    JUnit->>NB: Run IntegrationSpec
    NB->>NB: Write build files to temp dir
    NB->>ExtG: Spawn Gradle build (fork=true)
    ExtG-->>NB: stdout / stderr / exit code
    NB-->>JUnit: assertions on output
    JUnit-->>Gradle: 22 tests complete (4 skipped)

    Dev->>Gradle: ./gradlew testReport
    Gradle->>Gradle: Merge binary results
    Gradle-->>Dev: build/reports/allTests/index.html
```

---

## Static Analysis: CodeNarc

CodeNarc 2.0.0 is applied to all Groovy source sets (main, test, funcTest).

### Configuration File

`config/codenarc/codenarc.xml`

### Enabled Rule Categories

| Category | Notable Exclusions |
|---|---|
| `basic` | — |
| `braces` | — |
| `concurrency` | — |
| `convention` | `PublicMethodsBeforeNonPublicMethods`, `IfStatementCouldBeTernary`, `TrailingComma`, `StaticMethodsBeforeInstanceMethods` |
| `design` | `ReturnsNullInsteadOfEmptyCollection`, `AbstractClassWithoutAbstractMethod`, `AbstractClassWithPublicConstructor` |
| `dry` | `DuplicateStringLiteral` |
| `exceptions` | — |
| `formatting` | `Indentation`, `LineLength`, `ClosureStatementOnOpeningLineOfMultipleLineClosure`, `SpaceAroundMapEntryColon` (replaced by custom rule) |
| `generic` | — |
| `groovyism` | — |
| `imports` | `MisorderedStaticImports` (replaced by custom rule: static imports come after regular imports) |
| `junit` | `JUnitPublicNonTestMethod` |
| `logging` | — |
| `naming` | `MethodName`, `FactoryMethodName` (Spock uses natural-language method names) |
| `serialization` | — |
| `unnecessary` | `UnnecessaryGetter`, `UnnecessaryGString`, `UnnecessaryReturnKeyword`, `UnnecessaryElseStatement`, `UnnecessaryBooleanExpression` |
| `unused` | — |

### Custom Rule Overrides

```xml
<!-- Space required after colon in map literals -->
<rule class='org.codenarc.rule.formatting.SpaceAroundMapEntryColonRule'>
    <property name='characterAfterColonRegex' value='\ '/>
</rule>

<!-- Static imports must come AFTER regular imports -->
<rule class="org.codenarc.rule.imports.MisorderedStaticImportsRule">
    <property name="comesBefore" value="false"/>
</rule>
```

### Running CodeNarc

```bash
./gradlew codenarc
```

On failure, CodeNarc prints the full plain-text report to the Gradle warning log before the build fails. HTML and text reports are also written to `build/reports/codenarc/`.

---

## Plugin Validation: `validatePlugins`

The `validatePlugins` task is provided by the `java-gradle-plugin` plugin and validates that all task properties are correctly annotated with Gradle's incremental build annotations (`@Input`, `@OutputDirectory`, etc.).

The project enables the strictest validation mode:

```groovy
tasks.validatePlugins {
    enableStricterValidation = true   // enables additional checks (e.g. missing @Internal)
    failOnWarning = true              // treats any warning as a build failure
}
```

```bash
./gradlew validatePlugins
```

This task is part of the `check` lifecycle and is also a prerequisite of the publishing tasks.

---

## Running the Full Quality Pipeline

```bash
# Compile + unit tests + CodeNarc only
./gradlew build

# Unit tests only
./gradlew test

# Functional tests only (latestOnly Gradle versions)
./gradlew funcTest

# Functional tests with all Gradle versions
PITEST_REGRESSION_TESTS=full ./gradlew funcTest

# CodeNarc lint
./gradlew codenarc

# Plugin annotation validation
./gradlew validatePlugins

# Show all deprecation warnings from the build itself
./gradlew build --warning-mode=all

# Full quality pipeline via helper script
bash scripts/quality.sh full
```

> All commands must be run inside the dev container. Do not run them directly on the host machine.

---

## See Also

- [CLAUDE.md](../../CLAUDE.md) — project architecture, build commands, conventions
- [Build Commands](../../CLAUDE.md#build-commands) — full list of Gradle tasks
- [Quality Pipeline](../../CLAUDE.md#quality-pipeline) — `scripts/quality.sh` options
- [JDK 25 Compatibility Notes](../../CLAUDE.md#jdk-25-compatibility-notes) — ASM limitations and functional test exclusions
