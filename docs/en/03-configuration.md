---
id: configuration
title: Configuration Reference
sidebar_label: Configuration Reference
---

# Configuration Reference

![Gradle](https://img.shields.io/badge/Gradle-8.4%2B-blue)
![PIT](https://img.shields.io/badge/PIT-1.23.0%20default-green)
![Java](https://img.shields.io/badge/Java-17%2B-orange)

This document is the complete reference for the `pitest { }` DSL extension provided by
`info.solidsoft.pitest`. Every property maps directly to a PIT command-line argument unless
noted as Gradle-plugin-specific.

---

## Basic Usage

### Groovy DSL

```groovy
// build.gradle
plugins {
    id 'java'
    id 'info.solidsoft.pitest' version '1.15.0'
}

pitest {
    pitestVersion = '1.23.0'
    targetClasses = ['com.example.*']
    threads      = 4
    outputFormats = ['HTML', 'XML']
    mutationThreshold = 80
}
```

### Kotlin DSL

```kotlin
// build.gradle.kts
plugins {
    java
    id("info.solidsoft.pitest") version "1.15.0"
}

pitest {
    pitestVersion.set("1.23.0")
    targetClasses.set(setOf("com.example.*"))
    threads.set(4)
    outputFormats.set(setOf("HTML", "XML"))
    mutationThreshold.set(80)
}
```

> **Kotlin DSL note:** All properties use `.set()` — direct assignment (`=`) is not
> supported for Gradle `Property<T>` types. See the
> [Kotlin DSL Gotchas](#kotlin-dsl-gotchas) section for more details.

---

## Property Reference

### Core

These properties control the fundamental execution of PIT.

| Property | Type | Default | Description |
|---|---|---|---|
| `pitestVersion` | `Property<String>` | `1.23.0` | PIT version to resolve from Maven Central. Overrides the version bundled with the plugin. |
| `targetClasses` | `SetProperty<String>` | Derived from `project.group` (e.g., `com.example.*`) | Glob patterns for production classes to mutate. **Required** when `project.group` is not set. |
| `targetTests` | `SetProperty<String>` | Mirrors `targetClasses` | Glob patterns for test classes to run. Falls back to the resolved value of `targetClasses` when not set. |
| `threads` | `Property<Integer>` | `null` (PIT default: 1) | Number of parallel mutation testing threads. |
| `mutationEngine` | `Property<String>` | `null` (PIT default: `gregor`) | Mutation engine to use. Alternatives include `descartes` (requires plugin). |
| `failWhenNoMutations` | `Property<Boolean>` | `null` (PIT default: `true`) | Fail the build when PIT finds no mutations to test. Set to `false` in projects with no mutable code (e.g., pure interface modules). |
| `skipFailingTests` | `Property<Boolean>` | `null` (PIT default: `false`) | Skip tests that are already failing before mutation. Useful to get a mutation score even when the baseline is broken. |
| `fullMutationMatrix` | `Property<Boolean>` | `null` (PIT default: `false`) | Test every mutant against every test. Significantly increases runtime. |
| `verbosity` | `Property<String>` | `NO_SPINNER` | Output verbosity. One of: `QUIET`, `QUIET_WITH_PROGRESS`, `DEFAULT`, `NO_SPINNER`, `VERBOSE_NO_SPINNER`, `VERBOSE`. |
| `verbose` | `Property<Boolean>` | `null` | **Deprecated since 1.9.11.** Use `verbosity` instead. |

#### Example

```groovy
pitest {
    pitestVersion    = '1.23.0'
    targetClasses    = ['com.example.service.*', 'com.example.domain.*']
    targetTests      = ['com.example.**.*Test', 'com.example.**.*Spec']
    threads          = Runtime.runtime.availableProcessors()
    failWhenNoMutations = false
    verbosity        = 'NO_SPINNER'
}
```

---

### Reporting

| Property | Type | Default | Description |
|---|---|---|---|
| `reportDir` | `DirectoryProperty` | `$buildDir/reports/pitest` | Directory where PIT writes its output. Automatically set from Gradle's `ReportingExtension`. |
| `outputFormats` | `SetProperty<String>` | `null` (PIT default: `HTML`) | Report formats to generate. Common values: `HTML`, `XML`, `CSV`. Multiple formats can be specified simultaneously. |
| `timestampedReports` | `Property<Boolean>` | `null` (PIT default: `true`) | Append a timestamp to the report directory name. Set to `false` to always overwrite the same directory — convenient for CI. |
| `exportLineCoverage` | `Property<Boolean>` | `null` (PIT default: `false`) | Export line coverage data alongside mutation results. Intended for debugging. |
| `inputCharset` | `Property<Charset>` | `null` (PIT default: platform) | Character set for reading source files. Alias: `inputEncoding` (deprecated, kept for Maven plugin compatibility). |
| `outputCharset` | `Property<Charset>` | `null` (PIT default: platform) | Character set for writing reports. Alias: `outputEncoding` (deprecated). |

#### Example

```groovy
pitest {
    outputFormats      = ['HTML', 'XML']
    timestampedReports = false
    reportDir          = file("$buildDir/reports/pitest")
    inputCharset       = java.nio.charset.Charset.forName('UTF-8')
    outputCharset      = java.nio.charset.Charset.forName('UTF-8')
}
```

---

### Mutation

| Property | Type | Default | Description |
|---|---|---|---|
| `mutators` | `SetProperty<String>` | `null` (PIT default: `DEFAULTS`) | Mutator groups or individual mutator names to apply. Common groups: `DEFAULTS`, `STRONGER`, `ALL`. See [PIT mutators](https://pitest.org/quickstart/mutators/) for the full list. |
| `excludedMethods` | `SetProperty<String>` | `null` | Glob patterns for method names to exclude from mutation. Matched against the simple method name only (no class prefix). |
| `excludedClasses` | `SetProperty<String>` | `null` | Glob patterns for production classes to exclude from mutation. |
| `excludedTestClasses` | `SetProperty<String>` | `null` | Glob patterns for test classes to exclude from execution during mutation. Incubating. |
| `avoidCallsTo` | `SetProperty<String>` | `null` | Fully qualified class/package names. Calls to these are not mutated (e.g., logging frameworks). |
| `detectInlinedCode` | `Property<Boolean>` | `null` (PIT default: `false`) | Detect and handle inlined code generated by the compiler (e.g., string concatenation). |
| `mutationThreshold` | `Property<Integer>` | `null` | Minimum percentage of mutations that must be killed. Build fails if the score falls below this value (0–100). |
| `coverageThreshold` | `Property<Integer>` | `null` | Minimum percentage of code that must be covered by tests. Build fails below this value (0–100). |
| `testStrengthThreshold` | `Property<Integer>` | `null` | Minimum test strength percentage. Build fails below this value (0–100). |
| `maxSurviving` | `Property<Integer>` | `null` | Maximum number of surviving mutants allowed before the build fails. Alternative to `mutationThreshold` for absolute counts. |
| `timeoutFactor` | `Property<BigDecimal>` | `null` (PIT default: `1.25`) | Multiplier applied to the normal test execution time to compute the timeout for mutation runs. |
| `timeoutConstInMillis` | `Property<Integer>` | `null` (PIT default: `4000`) | Constant added to the computed timeout in milliseconds, in addition to the `timeoutFactor` calculation. |
| `features` | `ListProperty<String>` | `null` | Enable or disable named PIT features and plugin features. Prefix with `+` to enable, `-` to disable (e.g., `+EXPORT`, `-FEWMUTANTS`). Incubating. |

#### Example

```groovy
pitest {
    mutators         = ['DEFAULTS', 'REMOVE_CONDITIONALS']
    excludedClasses  = ['com.example.generated.*', '*.dto.*']
    excludedMethods  = ['toString', 'hashCode', 'equals']
    avoidCallsTo     = ['java.util.logging', 'org.slf4j', 'org.apache.log4j']
    mutationThreshold   = 80
    coverageThreshold   = 90
    testStrengthThreshold = 75
    timeoutFactor    = 2.0
    timeoutConstInMillis = 5000
    features         = ['+EXPORT']
}
```

---

### Test

| Property | Type | Default | Description |
|---|---|---|---|
| `junit5PluginVersion` | `Property<String>` | `null` | Version of `org.pitest:pitest-junit5-plugin` to add as a dependency automatically. When set, also configures `testPlugin = 'junit5'` unless `testPlugin` is explicitly set to something else. |
| `addJUnitPlatformLauncher` | `Property<Boolean>` | `true` | Automatically add `junit-platform-launcher` to `testRuntimeOnly` when `junit-platform-engine` or `junit-platform-commons` is found in `testImplementation`. Required by `pitest-junit5-plugin` 1.2.0+. Incubating. |
| `includedGroups` | `SetProperty<String>` | `null` | JUnit 4 categories or JUnit 5 tag expressions to include. Only tests matching these groups run during mutation. |
| `excludedGroups` | `SetProperty<String>` | `null` | JUnit 4 categories or JUnit 5 tag expressions to exclude. |
| `includedTestMethods` | `SetProperty<String>` | `null` | Glob patterns matching test method names to include. Added in PIT 1.3.2. |
| `testSourceSets` | `SetProperty<SourceSet>` | `[sourceSets.test]` | Gradle source sets treated as test code. Override when using custom test source sets (e.g., integration tests). Gradle-plugin-specific. |
| `mainSourceSets` | `SetProperty<SourceSet>` | `[sourceSets.main]` | Gradle source sets treated as production code to mutate. Gradle-plugin-specific. |
| `testPlugin` | `Property<String>` | `null` | **Deprecated since GPP 1.7.4.** Not used by PIT 1.6.7+. |

#### Example: JUnit 5 project

```groovy
dependencies {
    testImplementation 'org.junit.jupiter:junit-jupiter:5.10.0'
}

pitest {
    junit5PluginVersion = '1.2.1'
    // addJUnitPlatformLauncher = true (default — no action needed)
    includedGroups = ['fast', 'unit']
    excludedGroups = ['slow', 'integration']
}
```

#### Example: custom source sets

```groovy
pitest {
    mainSourceSets = [sourceSets.main, sourceSets.customModule]
    testSourceSets = [sourceSets.test, sourceSets.integrationTest]
}
```

---

### Advanced

| Property | Type | Default | Description |
|---|---|---|---|
| `jvmArgs` | `ListProperty<String>` | `null` | JVM arguments passed to the **child (minion) processes** that execute test mutations. |
| `mainProcessJvmArgs` | `ListProperty<String>` | `null` | JVM arguments passed to the **main PIT process** launched by Gradle. When set, this overrides the standard `jvmArgs` inherited from `JavaExec`. |
| `pluginConfiguration` | `MapProperty<String, String>` | `null` | Key/value pairs forwarded to PIT plugins as `--pluginConfiguration=key=value`. Each entry becomes a separate CLI argument. |
| `jvmPath` | `RegularFileProperty` | `null` (uses Gradle toolchain JVM) | Explicit path to the `java` executable used to launch PIT child processes. |
| `additionalMutableCodePaths` | `SetProperty<File>` | `null` | Extra directories or JARs containing production code to include in mutation analysis. Useful when mutating classes from another subproject's output JAR. Gradle-plugin-specific. |

#### Example

```groovy
pitest {
    jvmArgs = ['-Xmx512m', '-XX:+UseG1GC']
    mainProcessJvmArgs = ['-Xmx1g']
    pluginConfiguration = [
        'arcmutate.license.key': 'YOUR-KEY',
        'gregor.mutate.static.initialisers': 'true'
    ]
}
```

---

### Files

| Property | Type | Default | Description |
|---|---|---|---|
| `historyInputLocation` | `RegularFileProperty` | `null` | File from which PIT reads previous mutation results for incremental analysis. When `enableDefaultIncrementalAnalysis` is `true`, defaults to `$buildDir/pitHistory.txt`. |
| `historyOutputLocation` | `RegularFileProperty` | `null` | File to which PIT writes mutation results for future incremental analysis runs. Mirrors `historyInputLocation` when `enableDefaultIncrementalAnalysis` is `true`. |
| `enableDefaultIncrementalAnalysis` | `Property<Boolean>` | `null` | Enable incremental analysis using the default history file at `$buildDir/pitHistory.txt`. Alias: `withHistory` (kept for Maven plugin migration). |
| `useClasspathFile` | `Property<Boolean>` | `true` | Write the classpath to a temporary file and pass `--classPathFile` to PIT instead of a long `--classPath` argument. Enabled by default since 1.19.0. Avoids command-line length limits on Windows. Incubating. |
| `useClasspathJar` | `Property<Boolean>` | `null` | Package the classpath into a JAR manifest and pass it as a single entry. Alternative to `useClasspathFile` for environments with strict path length limits. Requires PIT 1.4.2+. Incubating. |
| `fileExtensionsToFilter` | `ListProperty<String>` | `['pom', 'so', 'dll', 'dylib']` | File extensions to remove from the classpath before passing it to PIT. PIT fails on native libraries and non-Java classpath entries. Add project-specific extensions as needed. Gradle-plugin-specific. Incubating. |

#### Example

```groovy
pitest {
    enableDefaultIncrementalAnalysis = true
    // historyInputLocation and historyOutputLocation are set automatically

    useClasspathFile = true

    // Append extra extensions to the built-in defaults:
    fileExtensionsToFilter.addAll('xml', 'orbit')
}
```

> **Note:** The `+=` operator for `fileExtensionsToFilter` is not supported due to a Gradle
> limitation ([gradle#10475](https://github.com/gradle/gradle/issues/10475)). Always use
> `.addAll(...)` to extend the default list.

---

## Aggregator Plugin Configuration

The `info.solidsoft.pitest.aggregator` plugin registers a `pitestReportAggregate` task that
merges PIT reports from all subprojects into a single HTML report. It is declared separately
and typically applied to the root project.

### Applying the plugin

```groovy
// root build.gradle
plugins {
    id 'info.solidsoft.pitest.aggregator' version '1.15.0'
}
```

### `reportAggregator { }` block

When the aggregator plugin is applied alongside `info.solidsoft.pitest`, the `pitest { }`
extension exposes a nested `reportAggregator { }` block that controls build quality gates
applied to the **aggregated** result.

| Property | Type | Default | Description |
|---|---|---|---|
| `mutationThreshold` | `Property<Integer>` | `null` | Minimum mutation score percentage for the aggregated report (0–100). Build fails below this value. |
| `testStrengthThreshold` | `Property<Integer>` | `null` | Minimum test strength percentage for the aggregated report. |
| `maxSurviving` | `Property<Integer>` | `null` | Maximum surviving mutants across all subprojects. |

```groovy
// Groovy DSL
pitest {
    reportAggregator {
        mutationThreshold     = 75
        testStrengthThreshold = 70
        maxSurviving          = 10
    }
}
```

```kotlin
// Kotlin DSL
pitest {
    reportAggregator {
        mutationThreshold.set(75)
        testStrengthThreshold.set(70)
        maxSurviving.set(10)
    }
}
```

### Multi-project layout

```groovy
// settings.gradle
rootProject.name = 'my-app'
include 'core', 'api', 'web'
```

```groovy
// root build.gradle
plugins {
    id 'info.solidsoft.pitest.aggregator' version '1.15.0'
}

pitest {
    reportAggregator {
        mutationThreshold = 75
    }
}
```

```groovy
// core/build.gradle, api/build.gradle, web/build.gradle (same for each)
plugins {
    id 'java'
    id 'info.solidsoft.pitest' version '1.15.0'
}

pitest {
    pitestVersion = '1.23.0'
    targetClasses = ["com.example.${project.name}.*"]
    outputFormats = ['XML']   // XML required for aggregation
    exportLineCoverage = true // line coverage required for aggregation
    timestampedReports = false
}
```

Run aggregation:

```bash
./gradlew pitestReportAggregate
```

The task automatically runs after all `pitest` tasks via `mustRunAfter`. To run everything in
one invocation:

```bash
./gradlew pitest pitestReportAggregate
```

---

## Configuration Examples

### Minimal

Suitable for a simple single-module project where `project.group` is already set.

```groovy
pitest {
    junit5PluginVersion = '1.2.1'
    outputFormats       = ['HTML']
    mutationThreshold   = 70
}
```

`targetClasses` is derived automatically from `project.group` (e.g., if `group = 'com.example'`
then `targetClasses = ['com.example.*']`).

---

### Typical

A realistic configuration for a Spring Boot application with JUnit 5.

```groovy
pitest {
    pitestVersion       = '1.23.0'
    junit5PluginVersion = '1.2.1'

    targetClasses = ['com.example.service.*', 'com.example.domain.*']
    excludedClasses = [
        'com.example.**.*Config',
        'com.example.**.*Application'
    ]
    excludedMethods = ['toString', 'hashCode', 'equals', 'canEqual']
    avoidCallsTo    = ['org.slf4j', 'org.springframework.util.Assert']

    threads          = 4
    outputFormats    = ['HTML', 'XML']
    timestampedReports = false
    mutationThreshold  = 80

    enableDefaultIncrementalAnalysis = true

    jvmArgs = ['-Xmx512m']
}
```

---

### Advanced

Full configuration for a performance-sensitive CI pipeline with custom thresholds, incremental
analysis, and plugin integration.

```groovy
pitest {
    pitestVersion       = '1.23.0'
    junit5PluginVersion = '1.2.1'

    targetClasses = ['com.example.*']
    excludedClasses = [
        'com.example.**.generated.**',
        'com.example.**.*Dto',
        'com.example.**.*Mapper'
    ]
    excludedMethods    = ['toString', 'hashCode', 'equals', 'canEqual', 'builder']
    excludedTestClasses = ['com.example.**.*IT']
    avoidCallsTo       = ['org.slf4j', 'org.apache.commons.logging']

    threads          = 8
    outputFormats    = ['HTML', 'XML', 'CSV']
    timestampedReports = false

    mutators         = ['STRONGER']
    mutationThreshold   = 85
    coverageThreshold   = 90
    testStrengthThreshold = 80
    maxSurviving        = 0

    timeoutFactor       = 2.0
    timeoutConstInMillis = 8000

    enableDefaultIncrementalAnalysis = true

    useClasspathFile = true
    fileExtensionsToFilter.addAll('xml', 'yaml', 'properties')

    jvmArgs         = ['-Xmx768m', '-XX:+UseG1GC', '-XX:MaxGCPauseMillis=200']
    mainProcessJvmArgs = ['-Xmx2g']

    features        = ['+EXPORT']
    pluginConfiguration = [
        'gregor.mutate.static.initialisers': 'true'
    ]

    inputCharset  = java.nio.charset.Charset.forName('UTF-8')
    outputCharset = java.nio.charset.Charset.forName('UTF-8')
}
```

---

## Kotlin DSL Gotchas

When using `build.gradle.kts`, there are several differences from the Groovy DSL.

### All property assignments use `.set()`

```kotlin
// Correct
pitest {
    pitestVersion.set("1.23.0")
    targetClasses.set(setOf("com.example.*"))
    threads.set(4)
    timestampedReports.set(false)
}

// Wrong — does not compile
pitest {
    pitestVersion = "1.23.0"   // compile error
}
```

### Collection properties use typed factory functions

```kotlin
pitest {
    targetClasses.set(setOf("com.example.*"))     // SetProperty
    outputFormats.set(setOf("HTML", "XML"))        // SetProperty
    jvmArgs.set(listOf("-Xmx512m"))               // ListProperty
    mutators.set(setOf("DEFAULTS"))                // SetProperty
    features.set(listOf("+EXPORT"))               // ListProperty
}
```

### Extending default lists with `addAll`

```kotlin
pitest {
    fileExtensionsToFilter.addAll("xml", "orbit")
}
```

### `pluginConfiguration` requires explicit map type

```kotlin
pitest {
    pluginConfiguration.set(
        mapOf(
            "arcmutate.license.key" to "YOUR-KEY",
            "gregor.mutate.static.initialisers" to "true"
        )
    )
}
```

### `reportAggregator` nested block

```kotlin
pitest {
    reportAggregator {
        mutationThreshold.set(75)
        testStrengthThreshold.set(70)
    }
}
```

### File properties

```kotlin
pitest {
    reportDir.set(layout.buildDirectory.dir("reports/pitest").get())
    historyInputLocation.set(layout.buildDirectory.file("pitHistory.txt").get())
    jvmPath.set(file("/usr/lib/jvm/java-17/bin/java"))
}
```

### `mainSourceSets` and `testSourceSets`

```kotlin
pitest {
    mainSourceSets.set(setOf(sourceSets["main"], sourceSets["generatedSources"]))
    testSourceSets.set(setOf(sourceSets["test"], sourceSets["integrationTest"]))
}
```

---

## See Also

- [PIT Mutators Reference](https://pitest.org/quickstart/mutators/)
- [PIT JUnit 5 Plugin](https://github.com/szpak/gradle-pitest-plugin#junit5)
- [gradle-pitest-plugin GitHub](https://github.com/szpak/gradle-pitest-plugin)
- [Gradle Provider API](https://docs.gradle.org/current/userguide/lazy_configuration.html)
