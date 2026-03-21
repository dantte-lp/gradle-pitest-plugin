# CLAUDE.md — gradle-pitest-plugin

## Project Overview

Gradle plugin for [PIT mutation testing](https://pitest.org/). Two plugins:
- `info.solidsoft.pitest` — main plugin, registers `pitest` task (extends `JavaExec`)
- `info.solidsoft.pitest.aggregator` — aggregates PIT reports across subprojects

**Language:** Groovy (with `@CompileStatic` on all production code)
**Build:** Gradle 9.4.1 (`build.gradle` — Groovy DSL)
**Test:** Spock 2.4-groovy-4.0 + Nebula Test 12.0.0 (functional tests)
**Quality:** CodeNarc 2.0.0 (`config/codenarc/codenarc.xml`)
**Default PIT:** 1.23.0
**Min Gradle:** 8.4 | **Min Java:** 17

## Key Architecture

```
src/main/groovy/info/solidsoft/gradle/pitest/
  PitestPlugin.groovy              # Main plugin — applies to projects with JavaPlugin
  PitestPluginExtension.groovy     # DSL extension (pitest { ... })
  PitestTask.groovy                # Abstract task extending JavaExec, @CacheableTask
  PitestAggregatorPlugin.groovy    # Aggregator plugin (@Incubating)
  AggregateReportTask.groovy       # Report aggregation via Worker API
  AggregateReportGenerator.groovy  # WorkAction implementation
  internal/
    GradleVersionEnforcer.groovy   # Min Gradle version check
    GradleUtil.groovy              # Utilities
```

## Build Commands (run inside container)

```bash
# Container
podman build -f deployment/containerfiles/Containerfile.dev -t pitest-plugin:dev .
podman run --rm -it -v .:/workspace:Z pitest-plugin:dev

# Build & test
./gradlew build                              # compile + unit tests + codenarc
./gradlew test                               # unit tests only
./gradlew funcTest                           # functional tests (Nebula)
PITEST_REGRESSION_TESTS=latestOnly ./gradlew funcTest  # quick regression
PITEST_REGRESSION_TESTS=full ./gradlew funcTest        # all Gradle versions
./gradlew codenarc                           # CodeNarc lint
./gradlew validatePlugins                    # Gradle plugin validation
./gradlew build --warning-mode=all           # show deprecation warnings
```

## Quality Pipeline

```bash
bash scripts/quality.sh quick      # build + shellcheck + hadolint
bash scripts/quality.sh full       # build + test + funcTest + codenarc + semgrep + trivy + gitleaks
bash scripts/quality.sh security   # semgrep + trivy + gitleaks + dep-check
bash scripts/quality.sh lint       # shellcheck + hadolint + codenarc
```

## Dev Container

Oracle Linux 10, GraalVM 17+21+25 (Gradle toolchain auto-detect), Gradle 9.4.1.
Security tools: Semgrep, Trivy, Gitleaks, Grype, Syft, ShellCheck, Hadolint, OWASP Dep-Check.

**IMPORTANT:** nebula-test 12.0.0 is NOT published to Maven Central. It must be built from source (v12.0.0 tag) with a Spock 2.x testMethodName patch and installed to mavenLocal before running funcTest. See Sprint 5 notes in the plan.

## Conventions

- All production Groovy code uses `@CompileStatic`; `@CompileDynamic` only in tests
- `PitestTask` is `abstract class` (required by Groovy 4 for JavaExec's abstract @Inject methods)
- Properties: Gradle Provider API (`Property<T>`, `ListProperty<T>`, `SetProperty<T>`, `MapProperty<T>`)
- Task registration via `tasks.register()` (lazy), never `tasks.create()`
- Extension created via `project.extensions.create()`
- Lazy file resolution: `baseDirectory.dir()` not `.asFile.get()`
- Minimum supported Gradle: 8.4 (`PitestPlugin.MINIMAL_SUPPORTED_GRADLE_VERSION`)
- Functional tests cover Gradle 6.x through 9.4.1 (`PitestPluginGradleVersionFunctionalSpec`)
- `pitestAggregatorVersion` in build.gradle MUST equal `DEFAULT_PITEST_VERSION` in PitestPlugin

## JDK 25 Compatibility Notes

- PIT < 1.19.0 uses ASM 9.7 which doesn't support class file version 69 (JDK 25)
- funcTest excludes PIT < 1.19.0 on JDK 25+ automatically
- Kotlin test projects use Kotlin 2.1.20 with jvmTarget=17
- Spock test project uses spock-core:2.4-groovy-4.0
- RegularFileProperty historyInputLocation test skipped on JDK 25+ (PIT internal error)
- Groovy 4 (embedded in Gradle 9) requires plugins built with Gradle 9 to run on Gradle >= 7.0

## Don'ts

- Do NOT use `project.exec()` or `project.javaexec()` — removed in Gradle 9
- Do NOT use Convention API (`project.getConvention()`) — removed in Gradle 9
- Do NOT use `project.buildDir` — use `project.layout.buildDirectory`
- Do NOT use `@CompileDynamic` in production code
- Do NOT add `jcenter()` — removed in Gradle 9
- Do NOT eagerly resolve file properties (`.asFile.get()`) at configuration time — use lazy providers
- Do NOT use `tasks.create()` — use `tasks.register()`
- Do NOT use `Configuration.visible` — deprecated in Gradle 9.1, no effect since 9.0
- Do NOT run build/test commands directly on host — use dev container only
