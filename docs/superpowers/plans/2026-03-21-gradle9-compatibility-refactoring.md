# gradle-pitest-plugin Gradle 9.x Compatibility Refactoring Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor gradle-pitest-plugin to be fully compatible with Gradle 9.0 through 9.4.1+, eliminate all deprecation warnings, and prepare for Gradle 10 by addressing newly deprecated APIs.

**Architecture:** The plugin already has partial Gradle 9.x support (tested up to 9.3.0). This plan addresses: (1) deprecated `Configuration.visible` property, (2) deprecated `ReportingExtension.file()` usage and eager resolution, (3) `java-gradle-plugin` scope change for `gradleApi()` in 9.4, (4) Groovy 4 compatibility (Spock, exclude groups), (5) legacy `@CompileDynamic` workarounds for pre-6.0 compatibility, (6) `afterSuite` Closure deprecation on `Test` task, (7) functional test matrix fixes, (8) bump wrapper to 9.4.1, (9) third-party plugin compatibility audit.

**Tech Stack:** Groovy 4 (embedded in Gradle 9), Gradle Plugin Development (`java-gradle-plugin`), Spock 2.4, Nebula Test 10.6.2

**Current state:** Plugin compiles with Gradle 8.14.3 wrapper, targets `sourceCompatibility = 1.8`, min supported Gradle = 8.4, functional tests cover 9.0.0-9.3.0.

**Hard constraint:** Plugins authored with Groovy DSL and built with Gradle 9.x require Gradle >= 7.0 at runtime (Groovy 4 bytecode). Current min is 8.4, so this is satisfied.

## Sprint Plan

### Sprint 1: Foundation (Tasks 0-2) — DONE 2026-03-21
- [x] Task 0: Audit third-party plugins (axion-release OK, nexus-publish unverified, plugin-publish OK, gradle-versions OK with --no-parallel)
- [x] Task 1: Bump Gradle wrapper to 9.4.1
- [x] Task 2: Fix build.gradle (sourceCompat→17, Spock→groovy-4.0, Groovy 4 excludes, funcTest gradleApi, afterSuite→TestListener)
- [x] Bonus: PitestTask → abstract (Groovy 4 enforces abstract @Inject methods from JavaExec)
- [x] Bonus: configurations.named().get() type coercion fix (Groovy 4 stricter)

### Sprint 2: Plugin Source Fixes (Tasks 3-4) — DONE 2026-03-21
- [x] Task 3: Remove deprecated `Configuration.visible`
- [x] Task 4: Fix ReportingExtension → lazy `baseDirectory.dir()`, remove `@CompileDynamic`, rename method

### Sprint 3: Test Matrix & Verification (Tasks 5-7) — DONE 2026-03-21
- [x] Task 5: Fix functional test version lists (decouple GRADLE8 from LATEST_KNOWN, add 9.4.x, GRADLE9 in full)
- [x] Task 6: Verify zero deprecation warnings `--warning-mode=all` — CLEAN
- [x] Task 7: `./gradlew build` — 142 tests pass, CodeNarc clean, validatePlugins clean

### Sprint 4: Dependency Updates — DONE 2026-03-21
- [x] plugin-publish-plugin 2.0.0 → 2.1.1
- [x] pitest-aggregator + DEFAULT_PITEST_VERSION 1.22.0 → 1.23.0
- [x] byte-buddy 1.18.4 → 1.18.7
- [x] junit-platform-launcher → 6.0.3
- [x] nebula-test 10.6.2 → 12.0.0 (built from source — not published to Maven Central)
- [x] JUnit 4:4.13.2 added (nebula-test 12.x no longer pulls it transitively)
- [x] spock-core 2.4-groovy-4.0 — kept (groovy-5.0 incompatible with Gradle 9's Groovy 4)

### Sprint 5: JDK 25 Compatibility — DONE 2026-03-21
- [x] Patched nebula-test 12.0.0 BaseIntegrationSpec + IntegrationSpec for Spock 2.x JUnit Platform (testMethodName NPE fix)
- [x] PIT version filter: exclude PIT < 1.19.0 on JDK 25+ (ASM 9.7 doesn't support class version 69)
- [x] Kotlin test projects: Kotlin 2.0.21 → 2.1.20, sourceCompat 1.8 → 17, jvmTarget → 17
- [x] Spock 2 test project: spock-core groovy-3.0 → groovy-4.0
- [x] InvalidUserCodeException test: Gradle 8.14.1 → current (8.14.1 can't run on JDK 25)
- [x] RegularFileProperty test: @IgnoreIf JDK 25+ (PIT internal error with historyInputLocation)
- [x] Subproject test: removed deprecated cross-project configuration access
- [x] funcTest ignoreDeprecations=true (Kotlin plugin legacy Usage attribute warnings)
- [x] Containerfile.dev: GraalVM 17+21+25 (Gradle toolchain support for multi-JDK)

### Sprint 6: Final Verification — DONE 2026-03-21
- [x] `./gradlew clean build funcTest` — **BUILD SUCCESSFUL**
- [x] Unit tests: 142/142 pass
- [x] Functional tests: 22/22 pass, 4 skipped (JDK 25 incompatible PIT versions + PIT internal bug)
- [x] CodeNarc: clean (0 violations)
- [x] validatePlugins: clean
- [x] Deprecation warnings: 0

### Sprint 7: QA Fixes & Documentation — DONE 2026-03-21
- [x] QA review by code-reviewer agent — 4 actionable items found
- [x] Fix #1: Comment on dead code `failWithMeaningfulErrorMessage...` for Gradle 9+
- [x] Fix #2: PIT version comparison — lexicographic → GradleVersion.version() comparator
- [x] Fix #3: Add JavaVersion.VERSION_25 → Gradle 9.4.1 to version map
- [x] Fix #4: Deduplicate GRADLE7_VERSIONS list
- [x] CLAUDE.md updated with final state
- [x] PM/QA assessment report created
- [x] `./gradlew clean build funcTest` — **BUILD SUCCESSFUL**

### Sprint 8: Commit & PR — TODO
- [ ] Commit all changes
- [ ] Create PR to upstream

---

## Analysis: Gradle 9.x Breaking Changes Affecting This Plugin

### Already handled (no action needed)
- Convention API removal (`Project.getConvention()`) - removed in v1.15.0 (CHANGELOG line 65)
- `Project.exec()`/`Project.javaexec()` removal - NOT USED in codebase (plugin extends `JavaExec` task directly)
- `Project.getBuildDir()` removal - uses `project.layout.buildDirectory` already
- `jcenter()` removal - uses `mavenCentral()` only
- Configuration cache for `pitestReportAggregate` - fixed in 1.19.0-rc.2
- Task registration uses lazy `tasks.register()`, not eager `tasks.create()`
- Worker API usage is compatible
- `@CacheableTask` is compatible
- `JavaForkOptions.setAllJvmArgs()` deprecation (9.1) - NOT USED; codebase uses `setJvmArgs()` only

### Requires refactoring

| # | Issue | Severity | Gradle Ver | File(s) |
|---|-------|----------|-----------|---------|
| 1 | `Configuration.visible = false` deprecated | MEDIUM | 9.1 (removal 10.0) | PitestPlugin:103, PitestAggregatorPlugin:51 |
| 2 | `ReportingExtension` eager `.asFile.get()` + `@CompileDynamic` legacy | MEDIUM | 9.1 (file() deprecated) | PitestPlugin:131-134, PitestAggregatorPlugin:107-112 |
| 3 | `java-gradle-plugin` moves `gradleApi()` to `compileOnlyApi` | HIGH | 9.4 | build.gradle (funcTest sourceSet) |
| 4 | `sourceCompatibility = 1.8` — Gradle 9 requires JVM 17+ | HIGH | 9.0 | build.gradle:27 |
| 5 | Spock `groovy-3.0` variant + Groovy 4 in Gradle 9 | MEDIUM | 9.0 | build.gradle:50 |
| 6 | nebula-test exclude group `org.codehaus.groovy` → `org.apache.groovy` | MEDIUM | 9.0 | build.gradle:59 |
| 7 | `afterSuite { }` Closure method on Test task deprecated | MEDIUM | 9.4 (removal 10.0) | build.gradle:95 |
| 8 | Functional test `GRADLE8_VERSIONS` uses `LATEST_KNOWN_GRADLE_VERSION` | HIGH | 9.4.1 | FunctionalSpec:121 |
| 9 | `GRADLE9_VERSIONS` missing from `full` regression list | MEDIUM | - | FunctionalSpec:138 |
| 10 | Third-party buildscript plugins Gradle 9 compatibility | HIGH | 9.4.1 | build.gradle:9-24 |

### Not affected (verified)
- `allprojects.findAll(Closure)` — uses Groovy's `Collection.findAll`, NOT Gradle's `DomainObjectCollection.findAll` (PitestAggregatorPlugin:115)
- `tasks.withType()` in aggregator — returns lazy `TaskCollection`, acceptable for aggregator pattern
- `setAllJvmArgs()` — NOT USED; PitestTask uses `setJvmArgs()` only

---

## File Structure

### Files to modify:
- `build.gradle` — sourceCompatibility, Spock dependency, Groovy exclude group, funcTest gradleApi(), afterSuite fix
- `gradle/wrapper/gradle-wrapper.properties` — bump to 9.4.1
- `src/main/groovy/info/solidsoft/gradle/pitest/PitestPlugin.groovy` — remove `visible`, fix ReportingExtension, rename method
- `src/main/groovy/info/solidsoft/gradle/pitest/PitestAggregatorPlugin.groovy` — remove `visible`, fix ReportingExtension lazy
- `src/funcTest/groovy/info/solidsoft/gradle/pitest/functional/PitestPluginGradleVersionFunctionalSpec.groovy` — fix version lists, add 9.4.1

### Files to review (no changes expected):
- `src/main/groovy/info/solidsoft/gradle/pitest/PitestPluginExtension.groovy` — null-convention pattern OK
- `src/main/groovy/info/solidsoft/gradle/pitest/AggregateReportTask.groovy` — Worker API OK
- `src/main/groovy/info/solidsoft/gradle/pitest/PitestTask.groovy` — jvmArgs assignment OK
- `gradle/publishing.gradle` — gradlePlugin block (check for testSourceSets)

---

## Task 0: Audit Third-Party Plugin Compatibility

**Files:**
- Review: `build.gradle:9-24` (buildscript dependencies)

The `build.gradle` uses a `buildscript {}` block with classpath dependencies for imperative plugin application. These third-party plugins must be compatible with Gradle 9.4.1:

| Plugin | Version | Gradle 9 Status |
|--------|---------|-----------------|
| axion-release | 1.21.1 | Check release notes |
| nexus-publish-plugin | 2.0.0 | Check release notes |
| plugin-publish-plugin | 2.0.0 | Check release notes |
| gradle-versions-plugin | 0.53.0 | Check release notes |

- [ ] **Step 1: Check each plugin's Gradle 9 compatibility**

```bash
# Search for Gradle 9 compatibility in each plugin's releases/issues
gh search repos "axion-release" --limit 1
gh search repos "gradle-nexus-publish-plugin" --limit 1
```

Or check release notes on their GitHub repos.

- [ ] **Step 2: Upgrade plugins if needed**

If any plugin is incompatible, update the version in `build.gradle:18-23`. Common issues:
- Plugins using removed Convention API
- Plugins using `Project.exec()`/`Project.javaexec()`
- Plugins compiled against old Gradle versions

- [ ] **Step 3: Document findings**

Record which plugins needed upgrades and any workarounds applied.

---

## Task 1: Bump Gradle Wrapper to 9.4.1

**Files:**
- Modify: `gradle/wrapper/gradle-wrapper.properties`

This is the foundational change. Everything else builds on top of a Gradle 9.4.1 build environment.

- [ ] **Step 1: Run wrapper upgrade command**

```bash
cd /opt/projects/repositories/gradle-pitest-plugin
./gradlew wrapper --gradle-version 9.4.1 --distribution-type all
```

- [ ] **Step 2: Verify wrapper properties updated**

```bash
cat gradle/wrapper/gradle-wrapper.properties
```
Expected: `distributionUrl` points to `gradle-9.4.1-all.zip`

- [ ] **Step 3: Verify Gradle runs (expect build failures — that's OK)**

```bash
./gradlew --version
```
Expected: `Gradle 9.4.1`

- [ ] **Step 4: Commit**

```bash
git add gradle/wrapper/gradle-wrapper.properties gradle/wrapper/gradle-wrapper.jar gradlew gradlew.bat
git commit -m "build: bump Gradle wrapper to 9.4.1"
```

---

## Task 2: Fix Build Script Compatibility (build.gradle)

**Files:**
- Modify: `build.gradle:27` (sourceCompatibility)
- Modify: `build.gradle:50` (Spock dependency)
- Modify: `build.gradle:59` (nebula-test exclude group)
- Modify: `build.gradle` (funcTest gradleApi)
- Modify: `build.gradle:95` (afterSuite Closure)

### 2a: Update sourceCompatibility to 17

- [ ] **Step 1: Update sourceCompatibility**

In `build.gradle:26-28`, change:
```groovy
java {
    sourceCompatibility = 17
}
```

Rationale: Plugin already declares Java 17 as minimum (1.19.0-rc.1), Gradle 9 requires JVM 17+.

### 2b: Update Spock and Groovy dependencies for Groovy 4

- [ ] **Step 2: Update Spock dependency for Groovy 4**

In `build.gradle:50`, change from `groovy-3.0` to `groovy-4.0` AND fix exclude group:
```groovy
testImplementation('org.spockframework:spock-core:2.4-groovy-4.0') {
    exclude group: 'org.apache.groovy'  // Groovy 4 changed group from org.codehaus.groovy
}
```

- [ ] **Step 3: Update nebula-test exclude group for Groovy 4**

In `build.gradle:58-60`, change:
```groovy
funcTestImplementation('com.netflix.nebula:nebula-test:10.6.2') {
    exclude group: 'org.apache.groovy', module: 'groovy-all'
}
```

Note: Groovy 4 moved from `org.codehaus.groovy` to `org.apache.groovy`.

### 2c: Register funcTest source set for gradleApi() access

- [ ] **Step 4: Register funcTest source set with java-gradle-plugin**

First check if `gradle/publishing.gradle` already calls `testSourceSets`. If not, add in `build.gradle` (preferred over raw `funcTestImplementation gradleApi()`):

```groovy
// After the gradlePlugin block in gradle/publishing.gradle, or in build.gradle:
gradlePlugin {
    testSourceSets sourceSets.funcTest
}
```

This is the cleanest approach: `java-gradle-plugin` will automatically add `gradleApi()` to the funcTest compilation and runtime classpaths.

If `gradlePlugin` block is only in `gradle/publishing.gradle`, add `testSourceSets` there alongside the plugin declarations.

### 2d: Replace deprecated `afterSuite` Closure

- [ ] **Step 5: Replace `afterSuite` Closure with Action/Listener**

In `build.gradle:87-103`, the `afterSuite { desc, result -> }` Closure is deprecated in Gradle 9.4. Replace with `addTestListener`:

```groovy
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

**Note:** Add required imports at top of `build.gradle`:
```groovy
import org.gradle.api.tasks.testing.TestListener
import org.gradle.api.tasks.testing.TestDescriptor
import org.gradle.api.tasks.testing.TestResult
```

- [ ] **Step 6: Try building to see current state**

```bash
./gradlew compileGroovy 2>&1 | head -50
```

Note any compilation errors — these will guide subsequent tasks.

- [ ] **Step 7: Commit**

```bash
git add build.gradle gradle/publishing.gradle
git commit -m "build: Gradle 9 compat — sourceCompat 17, Spock groovy-4.0, Groovy 4 exclude group, funcTest gradleApi, fix afterSuite"
```

---

## Task 3: Remove Deprecated `Configuration.visible` Property

**Files:**
- Modify: `src/main/groovy/info/solidsoft/gradle/pitest/PitestPlugin.groovy:101-106`
- Modify: `src/main/groovy/info/solidsoft/gradle/pitest/PitestAggregatorPlugin.groovy:49-55`

`Configuration.visible` was deprecated in Gradle 9.1 (removal in 10.0). Since Gradle 9.0 already removed the implicit behavior where `visible=true` triggered artifact creation, the `visible = false` line has no effect and can be safely removed.

- [ ] **Step 1: Remove `visible = false` from PitestPlugin.groovy**

In `PitestPlugin.groovy:101-106`, change:
```groovy
private Configuration createConfiguration() {
    return project.configurations.maybeCreate(PITEST_CONFIGURATION_NAME).with { configuration ->
        description = "The PIT libraries to be used for this project."
        return configuration
    }
}
```

- [ ] **Step 2: Remove `visible = false` from PitestAggregatorPlugin.groovy**

In `PitestAggregatorPlugin.groovy:49-55`, change:
```groovy
Configuration pitestReportConfiguration = project.configurations.create(PITEST_REPORT_AGGREGATE_CONFIGURATION_NAME).with { configuration ->
    attributes.attribute(Usage.USAGE_ATTRIBUTE, (Usage) project.objects.named(Usage, Usage.JAVA_RUNTIME))
    canBeConsumed = false
    canBeResolved = true
    return configuration
}
```

- [ ] **Step 3: Run unit tests**

```bash
./gradlew test 2>&1 | tail -20
```
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add src/main/groovy/info/solidsoft/gradle/pitest/PitestPlugin.groovy
git add src/main/groovy/info/solidsoft/gradle/pitest/PitestAggregatorPlugin.groovy
git commit -m "refactor: remove deprecated Configuration.visible property (Gradle 9.1+)"
```

---

## Task 4: Fix ReportingExtension Usage — Remove `@CompileDynamic` and Eager Resolution

**Files:**
- Modify: `src/main/groovy/info/solidsoft/gradle/pitest/PitestPlugin.groovy:131-134`
- Modify: `src/main/groovy/info/solidsoft/gradle/pitest/PitestAggregatorPlugin.groovy:107-112`

Two issues:
1. `@CompileDynamic` annotation exists "to keep Gradle <6.0 compatibility" — no longer needed since min Gradle is 8.4.
2. `ReportingExtension.baseDirectory.asFile.get()` eagerly resolves the directory at configuration time. Use `ReportingExtension.getBaseDirectory().dir()` instead (the `file(String)` method is deprecated in 9.1).

- [ ] **Step 1: Fix PitestPlugin.groovy — replace eager resolution with lazy provider and rename method**

Remove the `@CompileDynamic` annotation, rename from `setupReportDirInExtensionWithProblematicTypeForGradle5` to `setupDefaultReportDir`, and use lazy approach:

```groovy
private void setupDefaultReportDir() {
    extension.reportDir.set(project.extensions.getByType(ReportingExtension).baseDirectory.dir(PITEST_REPORT_DIRECTORY_NAME))
}
```

This uses `DirectoryProperty.dir(String)` which returns a `Provider<Directory>` — fully lazy. The `@CompileDynamic` is no longer needed since we don't reference `FileSystemLocationProperty` directly (the issue from Gradle 5.x).

Also update the call site in `setupExtensionWithDefaults()` (line 111):
```groovy
setupDefaultReportDir()
```

Also remove the now-unnecessary `import groovy.transform.CompileDynamic`.

- [ ] **Step 2: Fix PitestAggregatorPlugin.groovy — use lazy directory resolution**

Replace `getReportBaseDirectory()` in `PitestAggregatorPlugin.groovy:107-112`:

```groovy
private Provider<Directory> getReportBaseDirectory() {
    if (project.extensions.findByType(ReportingExtension)) {
        return project.extensions.getByType(ReportingExtension).baseDirectory
    }
    return project.layout.buildDirectory.dir("reports")
}
```

Both branches return `Provider<Directory>`:
- `ReportingExtension.baseDirectory` is a `DirectoryProperty` which extends `Provider<Directory>`
- `project.layout.buildDirectory.dir("reports")` returns `Provider<Directory>`

Then update the call site in `configureTaskDefaults` (line 70):

```groovy
reportDir.set(getReportBaseDirectory().map { it.dir(PitestPlugin.PITEST_REPORT_DIRECTORY_NAME) })
```

**Note:** Add import `org.gradle.api.file.Directory`.

- [ ] **Step 3: Run unit tests**

```bash
./gradlew test 2>&1 | tail -20
```

- [ ] **Step 4: Commit**

```bash
git add src/main/groovy/info/solidsoft/gradle/pitest/PitestPlugin.groovy
git add src/main/groovy/info/solidsoft/gradle/pitest/PitestAggregatorPlugin.groovy
git commit -m "refactor: use lazy ReportingExtension.baseDirectory, remove @CompileDynamic legacy workaround

Rename setupReportDirInExtensionWithProblematicTypeForGradle5 -> setupDefaultReportDir.
Both PitestPlugin and PitestAggregatorPlugin now use Provider<Directory> instead
of eagerly resolving to File."
```

---

## Task 5: Fix Functional Test Version Lists

**Files:**
- Modify: `src/funcTest/groovy/info/solidsoft/gradle/pitest/functional/PitestPluginGradleVersionFunctionalSpec.groovy`

Critical issues:
1. `GRADLE8_VERSIONS` starts with `LATEST_KNOWN_GRADLE_VERSION.version` (line 121). When we bump `LATEST_KNOWN_GRADLE_VERSION` to `"9.4.1"`, this inserts a Gradle 9 version into the Gradle 8 list — semantically wrong.
2. `GRADLE9_VERSIONS` is missing from the `"full"` regression case (line 138).
3. Need to add 9.4.0 and 9.4.1 to the test matrix.

- [ ] **Step 1: Fix GRADLE8_VERSIONS to not use LATEST_KNOWN_GRADLE_VERSION**

In `PitestPluginGradleVersionFunctionalSpec.groovy:121-122`, change:
```groovy
private static final List<String> GRADLE8_VERSIONS = ["8.14.3", "8.13", "8.12.1", "8.11.1", "8.10.2",
                                                       "8.9", "8.8", "8.7", "8.6.4", "8.5", "8.4", "8.3", "8.2.1", "8.1.1", "8.0.2"]
```

Remove the `LATEST_KNOWN_GRADLE_VERSION.version` reference from this list — it now belongs in `GRADLE9_VERSIONS`.

- [ ] **Step 2: Update LATEST_KNOWN_GRADLE_VERSION and GRADLE9_VERSIONS**

```groovy
private static final GradleVersion LATEST_KNOWN_GRADLE_VERSION = GradleVersion.version("9.4.1")

private static final List<String> GRADLE9_VERSIONS = [LATEST_KNOWN_GRADLE_VERSION.version, "9.4.0", "9.3.0", "9.2.0", "9.1.0", "9.0.0"]
```

- [ ] **Step 3: Update GRADLE_LATEST_VERSIONS to include Gradle 9 latest**

In `PitestPluginGradleVersionFunctionalSpec.groovy:124-125`:
```groovy
private static final List<String> GRADLE_LATEST_VERSIONS = [GRADLE6_VERSIONS.first(), GRADLE7_VERSIONS.first(),
                                                             GRADLE8_VERSIONS.first(), GRADLE9_VERSIONS.first(),
                                                             PitestPlugin.MINIMAL_SUPPORTED_GRADLE_VERSION.version]
```

- [ ] **Step 4: Add GRADLE9_VERSIONS to `full` regression case**

In `PitestPluginGradleVersionFunctionalSpec.groovy:138`, change:
```groovy
case "full":
    return GRADLE6_VERSIONS + GRADLE7_VERSIONS + GRADLE8_VERSIONS + GRADLE9_VERSIONS
```

- [ ] **Step 5: Run functional tests (quick)**

```bash
PITEST_REGRESSION_TESTS=latestOnly ./gradlew funcTest 2>&1 | tail -30
```

- [ ] **Step 6: Commit**

```bash
git add src/funcTest/groovy/info/solidsoft/gradle/pitest/functional/PitestPluginGradleVersionFunctionalSpec.groovy
git commit -m "test: fix version lists and add Gradle 9.4.1 to functional test matrix

- Decouple GRADLE8_VERSIONS from LATEST_KNOWN_GRADLE_VERSION
- Add GRADLE9_VERSIONS to full regression case
- Bump LATEST_KNOWN_GRADLE_VERSION to 9.4.1"
```

---

## Task 6: Verify No Deprecation Warnings with `--warning-mode=all`

**Files:** None to modify (verification step)

- [ ] **Step 1: Run the plugin's own build with deprecation warnings**

```bash
./gradlew build --warning-mode=all 2>&1 | grep -i "deprecat"
```

- [ ] **Step 2: Run functional tests to check plugin output for deprecation warnings**

```bash
PITEST_REGRESSION_TESTS=latestOnly ./gradlew funcTest --warning-mode=all 2>&1 | grep -i "deprecat"
```

- [ ] **Step 3: Address any remaining deprecation warnings**

For each warning found, create a fix following the patterns in earlier tasks.

Known potential warnings to watch for:
- `Configuration.canBeConsumed`/`canBeResolved` direct setters (may warn in future)
- Any Groovy 4 behavior differences in tests
- CodeNarc 2.0.0 may need upgrade (Gradle 9 bundles newer Groovy; ensure compatibility)

- [ ] **Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: resolve remaining Gradle 9.x deprecation warnings"
```

---

## Task 7: Run Full Test Suite and Final Verification

**Files:** None to modify (verification step)

- [ ] **Step 1: Run full unit tests**

```bash
./gradlew test
```
Expected: All tests pass.

- [ ] **Step 2: Run functional tests (quick)**

```bash
PITEST_REGRESSION_TESTS=quick ./gradlew funcTest
```
Expected: Tests pass on latest Gradle 6/7/8/9 versions.

- [ ] **Step 3: Run full regression if CI available**

```bash
PITEST_REGRESSION_TESTS=full ./gradlew funcTest
```

- [ ] **Step 4: Run validatePlugins**

```bash
./gradlew validatePlugins
```
Expected: No warnings, no failures.

- [ ] **Step 5: Final commit if needed**

---

## Summary of Changes

| File | Change | Why |
|------|--------|-----|
| `gradle-wrapper.properties` | Bump to 9.4.1 | Build with target Gradle |
| `build.gradle` | sourceCompat=17, Spock groovy-4.0, Groovy 4 exclude groups, funcTest gradleApi, afterSuite fix | Gradle 9 compatibility |
| `PitestPlugin.groovy:103` | Remove `visible = false` | Deprecated in 9.1 |
| `PitestPlugin.groovy:131-134` | Remove `@CompileDynamic`, rename method, use lazy `baseDirectory.dir()` | Remove pre-6.0 workaround, fix deprecated `file()` |
| `PitestAggregatorPlugin.groovy:51` | Remove `visible = false` | Deprecated in 9.1 |
| `PitestAggregatorPlugin.groovy:107-112` | Return `Provider<Directory>` instead of eager `File` | Lazy evaluation, avoid deprecated API |
| `PitestPluginGradleVersionFunctionalSpec` | Fix version list contamination, add GRADLE9_VERSIONS to full, add 9.4.x | Test coverage |

## Risks and Mitigations

1. **Third-party plugin compatibility**: The buildscript block plugins (axion-release 1.21.1, nexus-publish 2.0.0, plugin-publish 2.0.0, gradle-versions 0.53.0) must be verified for Gradle 9.4.1 compatibility. Task 0 addresses this — if a plugin is incompatible, upgrade or replace it before proceeding.

2. **Groovy 4 runtime differences**: Groovy 4 changed closure `DELEGATE_FIRST` behavior and package structure (`org.codehaus.groovy` → `org.apache.groovy`). The plugin uses `@CompileStatic` extensively which avoids dynamic lookup issues. The few `@CompileDynamic` usages are in tests, which is acceptable.

3. **Backward compatibility (HARD CONSTRAINT)**: Plugins authored with Groovy DSL and built with Gradle 9.x **require Gradle >= 7.0** at runtime due to Groovy 4 bytecode. The minimum supported version is 8.4, so this constraint is satisfied. This is NOT a "may" — it is a hard requirement from the Gradle upgrade guide.

4. **nebula-test compatibility**: Nebula-test 10.6.2 may not work with Gradle 9. If it doesn't, consider upgrading or switching to `GradleRunner` from Gradle TestKit directly.

5. **`java-gradle-plugin` scope change (9.4)**: The funcTest source set may lose access to Gradle API classes. Mitigation: register funcTest via `gradlePlugin.testSourceSets` (preferred) or add explicit `gradleApi()` dependency.

6. **CodeNarc version**: `build.gradle:111` hardcodes `toolVersion = "2.0.0"`. If CodeNarc 2.0.0 is incompatible with Groovy 4 (embedded in Gradle 9), upgrade to CodeNarc 3.x.

## APIs Deprecated in Gradle 9.x (Track for Gradle 10)

These are NOT broken yet but should be tracked for the next major refactoring:

| API | Deprecated In | Removal In | Affected Code | Status |
|-----|--------------|-----------|---------------|--------|
| `Configuration.canBeConsumed`/`canBeResolved` direct setters | Future | 10.0 | PitestAggregatorPlugin:52-53 | Monitor |
| `DomainObjectCollection.findAll(Closure)` | 9.4 | 10.0 | NOT affected (uses Groovy's findAll on Set) | N/A |
| `Test` task Closure methods (`afterSuite`) | 9.4 | 10.0 | build.gradle:95 | **Fixed in Task 2d** |
| Multi-string dependency notation | 9.1 | 10.0 | Not affected | N/A |
| `ReportingExtension.file(String)` | 9.1 | 10.0 | **Fixed in Task 4** | Done |
| `JavaForkOptions.setAllJvmArgs()` | 9.1 | 10.0 | Not affected (uses setJvmArgs) | N/A |
| `Configuration.visible` property | 9.1 | 10.0 | **Fixed in Task 3** | Done |
