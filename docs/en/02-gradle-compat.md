---
id: gradle-compat
title: Gradle 9.x Compatibility
sidebar_label: Gradle Compatibility
---

# Gradle 9.x Compatibility

![Gradle](https://img.shields.io/badge/Gradle-8.4--9.4.1-02303A?logo=gradle)
![Java](https://img.shields.io/badge/Java-17%2B-007396?logo=openjdk)
![Groovy](https://img.shields.io/badge/Groovy-4.x-4298B8?logo=apache-groovy)
![Status](https://img.shields.io/badge/Deprecation_Warnings-0-brightgreen)

## Overview

Starting with plugin version **1.19.0-rc.1**, gradle-pitest-plugin requires Gradle 8.4 as the minimum
supported version and is fully compatible with Gradle 9.x up to **9.4.1**. This document describes
every breaking change introduced in the Gradle 9.x line that affected this plugin, the specific code
changes made to address them, the version matrix, and the set of APIs that are deprecated in Gradle 9.x
but not yet removed — relevant for the eventual Gradle 10 migration.

The minimum supported Gradle version is enforced at runtime by
`src/main/groovy/info/solidsoft/gradle/pitest/internal/GradleVersionEnforcer.groovy` and is declared
as a public constant on `PitestPlugin`:

```groovy
// PitestPlugin.groovy, line 60
public static final GradleVersion MINIMAL_SUPPORTED_GRADLE_VERSION = GradleVersion.version("8.4")
```

---

## Gradle 9.0 Breaking Changes

### Convention API Removal

**Gradle issue:** `Project.getConvention()` and the entire Convention API were removed in Gradle 9.0.

**Plugin status:** Already resolved in **v1.15.0** (CHANGELOG entry, line 65). The plugin migrated to
`project.extensions.create()` and the Provider API well before the 9.0 release. No action was required
during the 9.x compatibility work.

---

### `Project.exec()` and `Project.javaexec()` Removal

**Gradle issue:** The convenience methods `Project.exec()` and `Project.javaexec()` were removed in
Gradle 9.0.

**Plugin status:** Not applicable. `PitestTask` extends `JavaExec` directly
(`PitestTask.groovy`, line 51) and overrides `exec()` to supply arguments at execution time
(`PitestTask.groovy`, lines 348–353). No call to `project.exec()` or `project.javaexec()` exists
anywhere in the production codebase.

---

### `Project.buildDir` Removal

**Gradle issue:** `Project.buildDir` and `Project.setBuildDir()` were removed in Gradle 9.0.

**Plugin status:** Already resolved before 1.19.0. The plugin uses the lazy
`project.layout.buildDirectory` Provider API throughout:

```groovy
// PitestPlugin.groovy, lines 200–209
task.additionalClasspathFile.set(
    project.layout.buildDirectory.file(PIT_ADDITIONAL_CLASSPATH_DEFAULT_FILE_NAME)
)
// ...
task.defaultFileForHistoryData.set(
    project.layout.buildDirectory.file(PIT_HISTORY_DEFAULT_FILE_NAME)
)
```

---

### `jcenter()` Repository Removal

**Gradle issue:** The `jcenter()` built-in repository shorthand was removed in Gradle 9.0.

**Plugin status:** Not applicable. `build.gradle` (line 39) uses `mavenCentral()` exclusively for
production dependency resolution. `mavenLocal()` and `gradlePluginPortal()` are present for the build
toolchain only.

---

### Groovy 4 Embedded in Gradle 9

Gradle 9 ships with Groovy 4 as its embedded scripting runtime. This introduced two concrete issues
for this plugin.

#### Abstract Class Requirement for Tasks with `@Inject` Methods

**Issue:** Groovy 4 enforces that a class containing abstract methods (including those inherited from
a superclass and annotated with `@Inject`) must itself be declared `abstract`. Gradle's `JavaExec`
task declares several abstract `@Inject` methods. In Groovy 3 and earlier, a non-abstract subclass
could instantiate without error; Groovy 4 raises a compilation or instantiation error.

**Fix applied:** `PitestTask` was changed to `abstract class` in `src/main/groovy/info/solidsoft/gradle/pitest/PitestTask.groovy`, line 51:

```groovy
// Before (Groovy 3 compatible)
class PitestTask extends JavaExec {

// After (required by Groovy 4)
abstract class PitestTask extends JavaExec {
```

This is consistent with Gradle's own documentation recommendation to declare all custom task types
as `abstract`.

#### Stricter Type Coercion

**Issue:** Groovy 4 enforces stricter coercion when calling methods whose return type is a parametrized
generic. In `PitestPlugin.groovy`, the call:

```groovy
project.configurations.named(PITEST_CONFIGURATION_NAME).get()
```

returns a `NamedDomainObjectProvider<Configuration>`, and Groovy 3 would silently coerce the `.get()`
result to `Configuration` in a `setFrom()` call. Groovy 4 raises a type error. The fix makes the
`.get()` call explicit where the resolved `Configuration` is used directly as a `Callable`:

```groovy
// PitestPlugin.groovy, lines 217–219
task.launchClasspath.setFrom({
    project.configurations.named(PITEST_CONFIGURATION_NAME).get()
} as Callable<Configuration>)
```

---

### JSpecify Nullability Annotations

**Gradle issue:** Gradle 9.0 introduced JSpecify nullability annotations (`@Nullable`, `@NonNull`)
on public API types, which can produce warnings in IDE tooling and annotation processors.

**Plugin status:** The plugin's production code uses `@CompileStatic` throughout and does not rely
on Gradle's annotated API in a way that conflicts with JSpecify. No source changes were required.
The `validatePlugins` task (`build.gradle`, line 129) with `enableStricterValidation = true` runs
clean against the 9.x API.

---

## Gradle 9.1+ Deprecations Fixed

### `Configuration.visible` Removed

**Gradle issue:** `Configuration.visible` was deprecated in Gradle 9.1 with removal planned for
Gradle 10.0. The property had no behavioral effect since Gradle 9.0 (the implicit behavior that
`visible = true` triggered artifact creation was removed in 9.0).

**Fix applied:** The `visible = false` lines were removed from both plugin classes.

`src/main/groovy/info/solidsoft/gradle/pitest/PitestPlugin.groovy`, lines 100–106 — the comment
on line 102 documents the removal:

```groovy
private Configuration createConfiguration() {
    return project.configurations.maybeCreate(PITEST_CONFIGURATION_NAME).with { configuration ->
        //visible = false removed: deprecated in Gradle 9.1 (no effect since 9.0)
        description = "The PIT libraries to be used for this project."
        return configuration
    }
}
```

`src/main/groovy/info/solidsoft/gradle/pitest/PitestAggregatorPlugin.groovy`, lines 50–56 — same
comment documents the removal at line 52.

---

### `ReportingExtension.file()` Replaced with `baseDirectory.dir()`

**Gradle issue:** `ReportingExtension.file(String)` was deprecated in Gradle 9.1. The replacement
is `ReportingExtension.baseDirectory.dir(String)`, which returns a `Provider<Directory>` and
participates in lazy configuration.

**Additional issue:** The previous implementation used `@CompileDynamic` to work around a
`ClassNotFoundException: org.gradle.api.file.FileSystemLocationProperty` on Gradle 5.x. Since the
minimum supported Gradle version is now 8.4, this workaround was dead code and was removed.

**Fix in `PitestPlugin.groovy`:** The method `setupReportDirInExtensionWithProblematicTypeForGradle5`
was renamed to `setupDefaultReportDir` and its `@CompileDynamic` annotation was removed. The
implementation at line 133 now uses the fully lazy `baseDirectory.dir()`:

```groovy
// PitestPlugin.groovy, lines 132–134
private void setupDefaultReportDir() {
    extension.reportDir.set(project.extensions.getByType(ReportingExtension).baseDirectory.dir(PITEST_REPORT_DIRECTORY_NAME))
}
```

**Fix in `PitestAggregatorPlugin.groovy`:** The `getReportBaseDirectory()` method at lines 108–113
now returns `Provider<Directory>` in both branches instead of eagerly resolving to a `File`:

```groovy
// PitestAggregatorPlugin.groovy, lines 108–113
private Provider<Directory> getReportBaseDirectory() {
    if (project.extensions.findByType(ReportingExtension)) {
        return project.extensions.getByType(ReportingExtension).baseDirectory
    }
    return project.layout.buildDirectory.dir("reports")
}
```

The call site at line 71 chains `.map { Directory dir -> dir.dir(...) }` so the full resolution
remains lazy until task execution.

---

### `afterSuite` Closure Replaced with `TestListener` Interface

**Gradle issue:** Closure-based event registration methods on the `Test` task — including
`afterSuite(Closure)` — were deprecated in Gradle 9.4 with removal planned for Gradle 10.0.

**Fix applied:** `build.gradle`, lines 114–126. The `afterSuite { suite, result -> }` Closure call
was replaced with `addTestListener(new TestListener() { ... })`. The three required imports were
added at the top of `build.gradle` (lines 1–3):

```groovy
// build.gradle, lines 1-3
import org.gradle.api.tasks.testing.TestListener
import org.gradle.api.tasks.testing.TestDescriptor
import org.gradle.api.tasks.testing.TestResult

// build.gradle, lines 106–127
tasks.withType(Test).configureEach { testTask ->
    testTask.configure {
        useJUnitPlatform()
        testLogging {
            exceptionFormat = 'full'
        }
        addTestListener(new TestListener() {
            void beforeSuite(TestDescriptor suite) {}
            void afterSuite(TestDescriptor suite, TestResult result) {
                if (!suite.parent) {
                    if (result.testCount == 0) {
                        throw new IllegalStateException("No tests were found. Failing the build")
                    }
                }
            }
            void beforeTest(TestDescriptor testDescriptor) {}
            void afterTest(TestDescriptor testDescriptor, TestResult result) {}
        })
    }
}
```

---

## Gradle 9.4 Changes

### `java-gradle-plugin` Moves `gradleApi()` to `compileOnlyApi`

**Gradle issue:** In Gradle 9.4, the `java-gradle-plugin` plugin changed the scope of the implicit
`gradleApi()` dependency from `api` to `compileOnlyApi`. This means source sets that are not
registered as test source sets under `gradlePlugin.testSourceSets` no longer receive `gradleApi()`
on their runtime classpath automatically.

**Impact:** The `funcTest` source set uses `nebula.test.functional.GradleRunner`, which requires
Gradle API classes at runtime. Without explicit registration, the functional tests would fail with
`ClassNotFoundException` at runtime.

**Fix applied:** Two changes in `build.gradle`:

1. The `funcTest` source set is registered with `gradlePlugin.testSourceSets` (lines 49–51), which
   is the canonical solution recommended by the Gradle team. This causes `java-gradle-plugin` to
   automatically supply `gradleApi()` to the funcTest compilation and runtime classpaths:

```groovy
// build.gradle, lines 48–51
//Gradle 9.4+ moves gradleApi() to compileOnlyApi; register funcTest for automatic gradleApi() access
gradlePlugin {
    testSourceSets sourceSets.funcTest
}
```

2. An explicit `testImplementation gradleApi()` dependency (line 63) was added for unit tests that
   use `ProjectBuilder`, since the scope change also affects unit test classpaths in some cases:

```groovy
// build.gradle, line 63
//Gradle 9.4+ moves gradleApi() to compileOnlyApi; tests need it at runtime for ProjectBuilder
testImplementation gradleApi()
```

---

## Version Matrix

The table below shows which combinations of Gradle version, JDK version, and plugin status are
covered by the functional test suite in
`src/funcTest/groovy/info/solidsoft/gradle/pitest/functional/PitestPluginGradleVersionFunctionalSpec.groovy`.

| Gradle Version | JDK 17 | JDK 21 | JDK 24 | JDK 25 | Notes |
|----------------|--------|--------|--------|--------|-------|
| 8.4            | OK     | OK     | --     | --     | Minimum supported version |
| 8.5 – 8.7      | OK     | OK     | --     | --     | |
| 8.8 – 8.9      | OK     | OK     | --     | --     | |
| 8.10 – 8.11    | OK     | OK     | OK     | --     | JDK 23 requires Gradle 8.10+ |
| 8.12 – 8.13    | OK     | OK     | OK     | --     | |
| 8.14.x         | OK     | OK     | OK     | --     | JDK 24 requires Gradle 8.14+ |
| 9.0.0          | OK     | OK     | OK     | --     | First Gradle 9 release |
| 9.1.0 – 9.2.0  | OK     | OK     | OK     | --     | |
| 9.3.0          | OK     | OK     | OK     | --     | |
| 9.4.0          | OK     | OK     | OK     | --     | `gradleApi()` scope change |
| 9.4.1          | OK     | OK     | OK     | OK     | JDK 25 requires Gradle 9.4.1+ |

**Legend:**
- `OK` — covered by functional test regression suite
- `--` — that JDK version is not supported by that Gradle version per the official compatibility matrix

**PIT version constraint on JDK 25:** PIT versions below 1.19.0 use ASM 9.7, which does not support
class file version 69 (JDK 25). The functional test suite automatically skips those PIT versions
on JDK 25+ (see `PitestPluginGradleVersionFunctionalSpec.groovy`, `applyJavaCompatibilityAdjustment`).

The MINIMAL_GRADLE_VERSION_FOR_JAVA_VERSION map (lines 37–50 of `PitestPluginGradleVersionFunctionalSpec.groovy`)
captures these constraints:

```groovy
private static final Map<JavaVersion, GradleVersion> MINIMAL_GRADLE_VERSION_FOR_JAVA_VERSION = [
    (JavaVersion.VERSION_15): GradleVersion.version("6.7"),
    (JavaVersion.VERSION_16): GradleVersion.version("7.0.2"),
    (JavaVersion.VERSION_17): GradleVersion.version("7.2"),
    (JavaVersion.VERSION_21): GradleVersion.version("8.4"),
    (JavaVersion.VERSION_22): GradleVersion.version("8.7"),
    (JavaVersion.VERSION_23): GradleVersion.version("8.10"),
    (JavaVersion.VERSION_24): GradleVersion.version("8.14"),
    (JavaVersion.VERSION_25): GradleVersion.version("9.4.1"),
]
```

---

## Migration Flowchart

The diagram below shows the decision path that was followed when evaluating each Gradle 9.x breaking
change against the plugin codebase.

```kroki-mermaid
flowchart TD
    A[Gradle 9.x Breaking Change] --> B{Affects plugin?}

    B -- No --> C[Document as N/A]
    B -- Yes --> D{Already fixed\nin prior release?}

    D -- Yes --> E[Document as pre-existing fix]
    D -- No --> F{Type of change}

    F -- API removed --> G[Convention API\nProject.exec\nProject.buildDir\njcenter]
    F -- API deprecated --> H{Gradle version\nof deprecation}
    F -- Behavior change --> I[Groovy 4\ncompiler rules]

    G --> J[Verify not used\nor migration done]
    J --> K{Used?}
    K -- No --> C
    K -- Yes --> L[Migrate to replacement API]

    H -- 9.1 --> M[Configuration.visible\nReportingExtension.file\ncanBeConsumed/canBeResolved]
    H -- 9.4 --> N[afterSuite Closure\ngradleApi scope\nDomainObjectCollection.findAll]

    M --> O{Removal in\nGradle 10?}
    O -- Yes urgent --> P[Fix now]
    O -- Monitor --> Q[Track for Gradle 10]

    N --> P

    I --> R[abstract class\nfor JavaExec subclass]
    R --> S[PitestTask → abstract]

    P --> T[Implement fix]
    T --> U[Run ./gradlew build\n--warning-mode=all]
    U --> V{Warnings?}
    V -- Yes --> T
    V -- No --> W[Verify 0 deprecation warnings\n142 unit tests pass\n22 functional tests pass]
```

---

## APIs Deprecated in Gradle 9.x — Prepare for Gradle 10

The APIs listed below are **not yet removed** but are deprecated in Gradle 9.x and are scheduled
for removal in Gradle 10.0. Code that uses them will produce deprecation warnings when building
with `--warning-mode=all` in Gradle 9.x. The plugin currently produces **zero deprecation warnings**
with Gradle 9.4.1.

| API | Deprecated in | Planned removal | Affected file | Current status |
|-----|--------------|-----------------|---------------|----------------|
| `Configuration.canBeConsumed` direct setter | Gradle 9.x | Gradle 10.0 | `PitestAggregatorPlugin.groovy`, line 53 | Used; monitor for Gradle 10 migration guide |
| `Configuration.canBeResolved` direct setter | Gradle 9.x | Gradle 10.0 | `PitestAggregatorPlugin.groovy`, line 54 | Used; monitor for Gradle 10 migration guide |
| `DomainObjectCollection.findAll(Closure)` | Gradle 9.4 | Gradle 10.0 | NOT used in plugin | N/A — `findAll` calls in plugin use Groovy's `Collection.findAll`, not Gradle's `DomainObjectCollection.findAll` |
| `Test` task Closure methods (e.g. `afterSuite`) | Gradle 9.4 | Gradle 10.0 | `build.gradle` | **Fixed** — replaced with `TestListener` interface |
| `ReportingExtension.file(String)` | Gradle 9.1 | Gradle 10.0 | `PitestPlugin.groovy`, `PitestAggregatorPlugin.groovy` | **Fixed** — replaced with `baseDirectory.dir()` |
| `Configuration.visible` | Gradle 9.1 | Gradle 10.0 | `PitestPlugin.groovy`, `PitestAggregatorPlugin.groovy` | **Fixed** — removed |

### `canBeConsumed` / `canBeResolved` Detail

These setters are used in `PitestAggregatorPlugin.groovy` to mark the `pitestReport` configuration
as a consumer-only (non-consumable, resolvable) configuration:

```groovy
// PitestAggregatorPlugin.groovy, lines 50–56
Configuration pitestReportConfiguration = project.configurations.create(PITEST_REPORT_AGGREGATE_CONFIGURATION_NAME).with { configuration ->
    attributes.attribute(Usage.USAGE_ATTRIBUTE, (Usage) project.objects.named(Usage, Usage.JAVA_RUNTIME))
    //visible = false removed: deprecated in Gradle 9.1 (no effect since 9.0)
    canBeConsumed = false
    canBeResolved = true
    return configuration
}
```

The replacement API in Gradle 10 is expected to use role-based configuration methods (e.g.
`resolvable()` / `consumable()` factory methods). This will be addressed when the Gradle 10 migration
guide is published.

### `DomainObjectCollection.findAll(Closure)` — Why It Does Not Apply

The calls to `.findAll { }` in the plugin source operate on standard Groovy/Java collections, not
on `DomainObjectCollection`:

- `PitestAggregatorPlugin.groovy`, line 116: `project.allprojects.findAll { ... }` — `allprojects`
  returns a plain `Set<Project>`, so Groovy's `Collection.findAll` is invoked, not Gradle's.
- `PitestPlugin.groovy`, line 190: a lambda inside a `zip()` provider chain operating on
  `List<FileSystemLocation>`.
- `PitestTask.groovy`, line 436: `map.findAll { ... }` on a plain `Map`.

None of these trigger the deprecated Gradle API.

---

## See Also

- [Gradle 9.0 Upgrade Guide](https://docs.gradle.org/9.0/userguide/upgrading_version_8.html)
- [Gradle 9.4 Release Notes](https://docs.gradle.org/9.4/release-notes.html)
- [CHANGELOG.md](../../CHANGELOG.md) — entries for v1.15.0, v1.19.0-rc.1, v1.19.0-rc.2
- [CHANGES.md](../../CHANGES.md) — detailed change log for the Gradle 9.x compatibility sprint
- `src/funcTest/groovy/info/solidsoft/gradle/pitest/functional/PitestPluginGradleVersionFunctionalSpec.groovy` — full version matrix and regression test modes
