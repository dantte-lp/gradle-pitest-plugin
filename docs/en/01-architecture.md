---
id: architecture
title: Architecture
sidebar_label: Architecture
---

# Architecture

![Maven Central](https://img.shields.io/maven-central/v/info.solidsoft.gradle.pitest/gradle-pitest-plugin)
[![Gradle Plugin Portal](https://img.shields.io/gradle-plugin-portal/v/info.solidsoft.pitest)](https://plugins.gradle.org/plugin/info.solidsoft.pitest)
![Gradle 8.4+](https://img.shields.io/badge/Gradle-8.4%2B-blue)
![Java 17+](https://img.shields.io/badge/Java-17%2B-blue)
![Groovy @CompileStatic](https://img.shields.io/badge/Groovy-%40CompileStatic-green)

## Overview

`gradle-pitest-plugin` integrates [PIT mutation testing](https://pitest.org/) into Gradle builds. The plugin bridges Gradle's task model and PIT's command-line interface: it translates DSL configuration into CLI arguments, assembles the correct classpath, and launches PIT in a child JVM process via `JavaExec`.

The plugin ships two independent plugins in a single artifact:

| Plugin ID | Purpose | Entry class |
|---|---|---|
| `info.solidsoft.pitest` | Mutation analysis for a single Gradle project | `PitestPlugin` |
| `info.solidsoft.pitest.aggregator` | Aggregated HTML report across multi-module builds | `PitestAggregatorPlugin` |

Both plugins enforce a minimum Gradle version of **8.4** at apply time. The default PIT version bundled is **1.23.0**.

> **Groovy convention.** All production code is annotated with `@CompileStatic`. Dynamic dispatch is limited exclusively to test code. This eliminates a class of runtime type errors and makes IDE navigation reliable.

---

## Package Structure

```
src/main/groovy/info/solidsoft/gradle/pitest/
├── PitestPlugin.groovy                 # Main plugin
├── PitestPluginExtension.groovy        # DSL extension (pitest { ... })
├── PitestTask.groovy                   # @CacheableTask extending JavaExec
├── PitestAggregatorPlugin.groovy       # Multi-module aggregator plugin
├── AggregateReportTask.groovy          # Aggregation task (Worker API)
├── AggregateReportGenerator.groovy     # WorkAction implementation
├── AggregateReportWorkParameters.groovy # Worker parameters interface
├── ReportAggregatorProperties.groovy   # Nested DSL block for aggregator
└── internal/
    ├── GradleVersionEnforcer.groovy    # Minimum Gradle version guard
    └── GradleUtil.groovy               # Project property utilities
```

---

## Main Plugin Architecture

### Initialization Sequence

`PitestPlugin` applies to any Gradle project that also has `JavaPlugin` applied. All setup runs lazily inside a `plugins.withType(JavaPlugin)` callback — the extension and task are never created if the project does not use Java.

```kroki-mermaid
graph TD
    A[build.gradle\napply plugin: 'info.solidsoft.pitest'] --> B[PitestPlugin.apply]
    B --> C[GradleVersionEnforcer\nfailBuild if Gradle < 8.4]
    B --> D[createConfiguration\npitest Configuration]
    B --> E{JavaPlugin\npresent?}
    E -->|yes, lazy callback| F[setupExtensionWithDefaults\ncreates PitestPluginExtension]
    E -->|no| Z[skip — no task registered]
    F --> G[addPitDependencies\norg.pitest:pitest-command-line]
    F --> H[tasks.register 'pitest'\nPitestTask]
    H --> I[configureTaskDefault\nwires Provider chains\nextension → task inputs]
    G --> J[pitest Configuration\nresolves at execution time]
    I --> K[PitestTask\n@CacheableTask extends JavaExec]
```

### Component Responsibilities

```kroki-mermaid
graph LR
    subgraph "Configuration Phase"
        EXT[PitestPluginExtension\npitest DSL block]
        CFG[pitest Configuration\nGradle dependency container]
    end

    subgraph "Execution Phase"
        TASK[PitestTask\nJavaExec subprocess]
        PIT[PIT CLI\norg.pitest...MutationCoverageReport]
        RPT[HTML / XML Reports\nbuild/reports/pitest/]
    end

    EXT -->|Provider chains\nlazy wiring| TASK
    CFG -->|launchClasspath\nresolved at exec| TASK
    TASK -->|--targetClasses --reportDir\n--classPath ... 30+ args| PIT
    PIT --> RPT
```

---

## Provider API and Lazy Evaluation

The plugin uses the Gradle **Provider / Property API** throughout. No file paths or dependency sets are resolved at configuration time. Every property in `PitestPluginExtension` is a `Property<T>`, `SetProperty<T>`, `ListProperty<T>`, `MapProperty<K,V>`, `DirectoryProperty`, or `RegularFileProperty`.

`PitestPlugin.configureTaskDefault()` wires extension properties to task inputs using `.set()` provider chaining:

```groovy
// Direct scalar wiring
task.threads.set(extension.threads)

// Derived provider — computed lazily at execution time
task.targetClasses.set(project.providers.provider {
    if (extension.targetClasses.isPresent()) {
        return extension.targetClasses.get()
    }
    if (project.getGroup()) {
        return [project.getGroup().toString() + ".*"] as Set
    }
    return null
} as Provider<Iterable<String>>)

// File collection wiring with classpath filtering
task.additionalClasspath.setFrom(
    extension.testSourceSets.zip(extension.fileExtensionsToFilter.orElse([])) { sourceSets, extensions ->
        sourceSets*.runtimeClasspath*.elements*.map { locations ->
            locations.findAll { loc -> !extensions.any { loc.asFile.name.endsWith(".$it") } }
        }
    }
)
```

Task registration uses `tasks.register()` (lazy), never `tasks.create()`. File layout is expressed as `project.layout.buildDirectory.file(...)`, not `project.buildDir`.

---

## PitestTask Execution Model

`PitestTask` is an `abstract class` extending `JavaExec`. The `abstract` modifier is required by Groovy 4 (embedded in Gradle 9) to satisfy `@Inject`-annotated abstract methods inherited from `JavaExec`.

`@CacheableTask` enables Gradle's build cache: if inputs are unchanged between builds, the cached report is restored instead of re-running PIT.

```kroki-mermaid
sequenceDiagram
    participant G as Gradle Execution Engine
    participant T as PitestTask.exec()
    participant C as argumentsForPit()
    participant J as JavaExec (child JVM)
    participant P as PIT CLI

    G->>T: execute task
    T->>C: taskArgumentMap() — collect 30+ CLI args
    C-->>T: Map[String, String] → List["--key=value"]
    T->>T: write classpath to pitClasspath file\n(useClasspathFile=true by default)
    T->>J: jvmArgs = mainProcessJvmArgs\nclasspath = launchClasspath\nmain = MutationCoverageReport
    J->>P: spawn child JVM with assembled args
    P-->>J: exit code
    J-->>G: success / failure
```

### CLI Argument Assembly

`taskArgumentMap()` builds a `Map<String, String>` from every configured property, filtering out null and empty values. Multi-value properties (sets, lists) are joined with commas. The `--pluginConfiguration` argument is emitted as multiple `--pluginConfiguration=key=value` entries via `multiValueArgsAsList()`.

By default, classpath is written to a file (`build/pitClasspath`) to avoid command-line length limits on Windows, controlled by `useClasspathFile` (enabled by default since 1.19.0).

---

## Dependency Management

`PitestPlugin` creates a `pitest` Gradle `Configuration` and populates it lazily:

| Artifact | Condition |
|---|---|
| `org.pitest:pitest-command-line:<pitestVersion>` | Always added |
| `org.pitest:pitest-junit5-plugin:<junit5PluginVersion>` | When `junit5PluginVersion` is set |
| `org.junit.platform:junit-platform-launcher:<version>` | When `addJUnitPlatformLauncher=true` (default) and `junit-platform-engine` or `junit-platform-commons` is found in `testImplementation` |

The `junit-platform-launcher` auto-detection resolves `testImplementation` transiently at configuration time to match the exact JUnit Platform version already on the classpath, avoiding version skew.

---

## PitestPluginExtension — DSL Properties

The `pitest { ... }` block exposes 40+ properties via `PitestPluginExtension`. All are Gradle `Provider`-typed and default to `notPresent` unless explicitly listed below.

### Defaults Set by the Plugin

| Property | Default value | Source |
|---|---|---|
| `pitestVersion` | `1.23.0` | `PitestPlugin.DEFAULT_PITEST_VERSION` |
| `reportDir` | `build/reports/pitest` | `ReportingExtension.baseDirectory` |
| `testSourceSets` | `[sourceSets.test]` | `SourceSetContainer` |
| `mainSourceSets` | `[sourceSets.main]` | `SourceSetContainer` |
| `fileExtensionsToFilter` | `['pom', 'so', 'dll', 'dylib']` | Hardcoded list |
| `useClasspathFile` | `true` | Since 1.19.0 |
| `verbosity` | `NO_SPINNER` | Plugin default |
| `addJUnitPlatformLauncher` | `true` | Since 1.14.0 |

### Property Type Summary

| Groovy type | Gradle API type | Used for |
|---|---|---|
| `Property<String>` | scalar | `pitestVersion`, `mutationEngine`, `verbosity`, … |
| `Property<Boolean>` | scalar | `failWhenNoMutations`, `timestampedReports`, … |
| `Property<Integer>` | scalar | `threads`, `mutationThreshold`, `maxSurviving`, … |
| `SetProperty<String>` | unordered collection | `targetClasses`, `mutators`, `excludedClasses`, … |
| `ListProperty<String>` | ordered collection | `jvmArgs`, `mainProcessJvmArgs`, `features`, … |
| `MapProperty<String, String>` | key-value pairs | `pluginConfiguration` |
| `DirectoryProperty` | file system path | `reportDir` |
| `RegularFileProperty` | file path | `historyInputLocation`, `historyOutputLocation`, `jvmPath` |
| `SetProperty<SourceSet>` | Gradle source sets | `testSourceSets`, `mainSourceSets` |

`SetProperty` and `ListProperty` fields that must distinguish "not set" from "empty collection" are initialized with a null-returning `Provider` via a `nullSetPropertyOf()` / `nullListPropertyOf()` helper, rather than an empty convention.

---

## Aggregator Plugin Architecture

`PitestAggregatorPlugin` (`@Incubating`) is applied to a root or aggregating project. It does not require `JavaPlugin`. It collects `mutations.xml` and `linecoverage.xml` files from every subproject that has `info.solidsoft.pitest` applied, then delegates HTML report generation to the Worker API to achieve classloader isolation from the build JVM.

```kroki-mermaid
graph TD
    subgraph "Root Project"
        AGG[PitestAggregatorPlugin.apply]
        CFG2[pitestReport Configuration\norg.pitest:pitest-aggregator]
        ATASK[AggregateReportTask\n@DisableCachingByDefault]
        WQ[WorkQueue\nclassLoaderIsolation]
        GEN[AggregateReportGenerator\nimplements WorkAction]
        PRA[pitest-aggregator\nReportAggregator API]
    end

    subgraph "Subproject A"
        PA[PitestTask A]
        RA[mutations.xml\nlinecoverage.xml]
    end

    subgraph "Subproject B"
        PB[PitestTask B]
        RB[mutations.xml\nlinecoverage.xml]
    end

    PA --> RA
    PB --> RB
    RA -->|collectMutationFiles| ATASK
    RB -->|collectMutationFiles| ATASK
    AGG --> CFG2
    AGG --> ATASK
    CFG2 --> WQ
    ATASK -->|mustRunAfter all PitestTasks| ATASK
    ATASK --> WQ
    WQ --> GEN
    GEN --> PRA
    PRA --> OUT[build/reports/pitest/index.html]
```

### Worker API Isolation

`AggregateReportTask` uses `WorkerExecutor.classLoaderIsolation()`. The `pitest-aggregator` JAR (resolved via the `pitestReport` configuration) is loaded in a separate classloader, keeping PIT's internal classes off the build classpath. Parameters are passed through `AggregateReportWorkParameters` (a `WorkParameters` interface).

```kroki-mermaid
sequenceDiagram
    participant T as AggregateReportTask.aggregate()
    participant WE as WorkerExecutor
    participant CL as Isolated ClassLoader\n(pitest-aggregator JAR)
    participant GEN as AggregateReportGenerator.execute()
    participant RA as ReportAggregator\n(PIT API)

    T->>WE: classLoaderIsolation { classpath = pitestReportClasspath }
    WE->>T: WorkQueue
    T->>WE: workQueue.submit(AggregateReportGenerator, params)
    WE->>CL: load AggregateReportGenerator
    CL->>GEN: execute()
    GEN->>RA: builder.addMutationResultsFile()\n.addLineCoverageFile()\n.addSourceCodeDirectory()\n.build()
    RA-->>GEN: AggregationResult
    GEN->>GEN: check testStrengthThreshold\ncheck mutationThreshold\ncheck maxSurviving
    GEN-->>T: done / GradleException on threshold breach
```

### Report Collection Strategy

`PitestAggregatorPlugin` discovers subproject outputs by iterating `project.allprojects` at configuration time:

- **Source directories** — from `PitestTask.sourceDirs` on every registered `PitestTask`
- **Classpath directories** — from `PitestTask.additionalClasspath`, filtered to directories only (excludes JARs)
- **Mutation files** — `PitestPluginExtension.reportDir` + `mutations.xml` per subproject with the plugin
- **Line coverage files** — `PitestPluginExtension.reportDir` + `linecoverage.xml` per subproject with the plugin

If `PitestPluginExtension` is not present on the root project, the aggregator searches subprojects for the first available extension to read `pitestVersion`, `inputCharset`, `outputCharset`, and threshold settings.

---

## Key Classes Reference

| Class | Package | Role |
|---|---|---|
| `PitestPlugin` | `info.solidsoft.gradle.pitest` | Plugin entry point; creates `pitest` configuration, registers `pitest` task, wires all Provider chains from extension to task |
| `PitestPluginExtension` | `info.solidsoft.gradle.pitest` | DSL `pitest { }` block; 40+ `@CompileStatic` Provider-typed properties; used at configuration time only |
| `PitestTask` | `info.solidsoft.gradle.pitest` | `abstract` `@CacheableTask` extending `JavaExec`; builds CLI argument map; launches PIT in child JVM |
| `PitestAggregatorPlugin` | `info.solidsoft.gradle.pitest` | `@Incubating` aggregator plugin; collects subproject outputs; registers `pitestReportAggregate` task |
| `AggregateReportTask` | `info.solidsoft.gradle.pitest` | `@Incubating` `@DisableCachingByDefault` task; submits work to `WorkerExecutor` with classloader isolation |
| `AggregateReportGenerator` | `info.solidsoft.gradle.pitest` | `WorkAction` implementation; invokes PIT's `ReportAggregator` API; enforces score thresholds |
| `AggregateReportWorkParameters` | `info.solidsoft.gradle.pitest` | `WorkParameters` interface carrying serializable inputs across classloader boundary |
| `ReportAggregatorProperties` | `info.solidsoft.gradle.pitest` | Nested DSL object for `pitest { reportAggregator { ... } }` thresholds |
| `GradleVersionEnforcer` | `info.solidsoft.gradle.pitest.internal` | Reads `GradleVersion.current()`; throws `GradleException` if below minimum; can be suppressed via `-Pgpp.disableGradleVersionEnforcement` |
| `GradleUtil` | `info.solidsoft.gradle.pitest.internal` | Single static utility: `isPropertyNotDefinedOrFalse()` |

---

## Data Flow: Extension to PIT Execution

```kroki-mermaid
flowchart LR
    DSL["pitest { ... }\nbuild.gradle DSL"]
    EXT["PitestPluginExtension\nProperty&lt;T&gt; fields"]
    WIRE["PitestPlugin\nconfigureTaskDefault()"]
    TINP["PitestTask\n@Input properties"]
    ARGM["taskArgumentMap()\nMap&lt;String,String&gt;"]
    ARGV["CLI args list\n--key=value ..."]
    CPFILE["pitClasspath file\nbuild/pitClasspath"]
    JVM["JavaExec\nchild JVM process"]
    PIT["PIT MutationCoverageReport\norg.pitest.*"]
    RPTH["HTML report\nbuild/reports/pitest/"]
    RPTX["XML report\nmutations.xml\nlinecoverage.xml"]

    DSL -->|set| EXT
    EXT -->|.set provider chain| WIRE
    WIRE -->|task.prop.set extension.prop| TINP
    TINP -->|exec| ARGM
    ARGM -->|argumentsListFromMap| ARGV
    ARGV -->|useClasspathFile=true| CPFILE
    ARGV --> JVM
    CPFILE --> JVM
    JVM -->|spawn| PIT
    PIT --> RPTH
    PIT --> RPTX
```

The `exec()` override in `PitestTask` is the only point where Provider values are resolved to concrete values. This preserves Gradle's up-to-date checking and configuration cache compatibility — no file paths or dependency sets are materialized before execution begins.

---

## Build Cache Behavior

`PitestTask` is annotated with `@CacheableTask`. Gradle tracks the following as cache key inputs:

- All `@Input` properties (target classes, mutators, threads, thresholds, etc.)
- `@InputFiles @Classpath` collections: `additionalClasspath`, `launchClasspath`
- `@InputFiles @PathSensitive(RELATIVE)` collections: `sourceDirs`, `mutableCodePaths`

The `@OutputDirectory reportDir` is restored from cache on a hit. Properties marked `@Internal` (e.g., `additionalClasspathFile`, `defaultFileForHistoryData`, `jvmPath`) are excluded from the cache key; their path values are exposed as separate `@Input String` getters to satisfy the build cache without triggering the known Gradle issue [#12351](https://github.com/gradle/gradle/issues/12351) with `RegularFileProperty` serialization.

`AggregateReportTask` is annotated `@DisableCachingByDefault` pending a future implementation decision.

---

## See Also

- [PIT documentation](https://pitest.org/quickstart/commandline/) — full CLI argument reference
- [Gradle Provider API](https://docs.gradle.org/current/userguide/lazy_configuration.html) — lazy configuration model
- [Gradle Worker API](https://docs.gradle.org/current/userguide/worker_api.html) — classloader isolation used by aggregator
- [Gradle Build Cache](https://docs.gradle.org/current/userguide/build_cache.html) — caching semantics for `@CacheableTask`
