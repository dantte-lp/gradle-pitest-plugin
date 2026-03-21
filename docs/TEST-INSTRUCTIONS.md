# Test Instructions for Gradle 9.x Compatibility PR

## Prerequisites

- Podman installed
- Repository cloned at `/opt/projects/repositories/gradle-pitest-plugin`

## Step 1: Build the dev container

```bash
cd /opt/projects/repositories/gradle-pitest-plugin
podman build -f deployment/containerfiles/Containerfile.dev -t pitest-plugin:dev .
```

Expected: `Successfully tagged localhost/pitest-plugin:dev`
Time: ~5 minutes (first build)

## Step 2: Build patched nebula-test 12.0.0

nebula-test 12.0.0 is not published to Maven Central. It must be built from source with a Spock 2.x patch.

```bash
podman run --rm -v /opt/projects/repositories/gradle-pitest-plugin:/workspace:Z pitest-plugin:dev \
  bash -lc '
source /root/.sdkman/bin/sdkman-init.sh
cd /tmp
git clone --depth 1 --branch v12.0.0 https://github.com/nebula-plugins/nebula-test.git
cd nebula-test

# Patch BaseIntegrationSpec — fix testMethodName NPE with Spock 2.x + JUnit Platform
cat > src/main/groovy/nebula/test/BaseIntegrationSpec.groovy << '\''PATCH1'\''
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

# Patch IntegrationSpec — same fix
cat > src/main/groovy/nebula/test/IntegrationSpec.groovy << '\''PATCH2'\''
package nebula.test
import groovy.transform.CompileStatic
@CompileStatic
@Deprecated(forRemoval = true)
abstract class IntegrationSpec extends BaseIntegrationSpec implements Integration {
    def setup() { Integration.super.initialize(getClass(), resolveMethodName()) }
}
PATCH2

# Disable signing and publish to mavenLocal
cat > /tmp/no-sign.gradle << '\''NOSIGN'\''
allprojects { tasks.withType(Sign) { enabled = false } }
NOSIGN
./gradlew publishToMavenLocal -x test -x javadoc -Prelease.version=12.0.0 --no-scan -I /tmp/no-sign.gradle
'
```

Expected: `BUILD SUCCESSFUL` (last line)
Time: ~1 minute

## Step 3: Run unit tests

```bash
podman run --rm -v /opt/projects/repositories/gradle-pitest-plugin:/workspace:Z pitest-plugin:dev \
  bash -lc 'source /root/.sdkman/bin/sdkman-init.sh && ./gradlew test'
```

Expected: `BUILD SUCCESSFUL`, 142 tests pass, 0 failures

## Step 4: Run full build (includes CodeNarc + validatePlugins)

```bash
podman run --rm -v /opt/projects/repositories/gradle-pitest-plugin:/workspace:Z pitest-plugin:dev \
  bash -lc 'source /root/.sdkman/bin/sdkman-init.sh && ./gradlew build --warning-mode=all'
```

Expected:
- `BUILD SUCCESSFUL`
- No deprecation warnings in output
- CodeNarc: 0 violations
- validatePlugins: no warnings

## Step 5: Run functional tests

**IMPORTANT:** Steps 2 and 5 must run in the same container invocation (nebula-test in mavenLocal is ephemeral).

```bash
podman run --rm -v /opt/projects/repositories/gradle-pitest-plugin:/workspace:Z pitest-plugin:dev \
  bash -lc '
source /root/.sdkman/bin/sdkman-init.sh

# Step 2 inline — build nebula-test
cd /tmp
git clone --depth 1 --branch v12.0.0 https://github.com/nebula-plugins/nebula-test.git
cd nebula-test
cat > src/main/groovy/nebula/test/BaseIntegrationSpec.groovy << '\''P1'\''
package nebula.test
import groovy.transform.CompileStatic; import org.junit.Rule; import org.junit.rules.TestName; import spock.lang.Specification
@CompileStatic @Deprecated(forRemoval = true)
abstract class BaseIntegrationSpec extends Specification implements IntegrationBase {
    @Rule TestName testName = new TestName()
    protected String resolveMethodName() { String mn = testName?.methodName; if (mn == null) { try { mn = specificationContext?.currentIteration?.parent?.name ?: "test" } catch (ignored) { mn = "test" } }; return mn }
    void setup() { IntegrationBase.super.initialize(getClass(), resolveMethodName()) }
}
P1
cat > src/main/groovy/nebula/test/IntegrationSpec.groovy << '\''P2'\''
package nebula.test
import groovy.transform.CompileStatic
@CompileStatic @Deprecated(forRemoval = true)
abstract class IntegrationSpec extends BaseIntegrationSpec implements Integration {
    def setup() { Integration.super.initialize(getClass(), resolveMethodName()) }
}
P2
cat > /tmp/no-sign.gradle << '\''NS'\''
allprojects { tasks.withType(Sign) { enabled = false } }
NS
./gradlew publishToMavenLocal -x test -x javadoc -Prelease.version=12.0.0 --no-scan -I /tmp/no-sign.gradle

# Now run funcTest
cd /workspace
PITEST_REGRESSION_TESTS=latestOnly ./gradlew clean build funcTest
'
```

Expected:
- `BUILD SUCCESSFUL`
- Unit tests: 142 pass
- Functional tests: ~22 pass, ~4 skipped (JDK 25 PIT/ASM limitations)
- 0 failures

## Step 6 (optional): Check deprecation warnings

```bash
# In the same container session as Step 5:
./gradlew build --warning-mode=all 2>&1 | grep -i deprecat
```

Expected: no output (zero deprecation warnings)

## What to verify

- [ ] Container builds successfully (Step 1)
- [ ] nebula-test 12.0.0 builds from source (Step 2)
- [ ] Unit tests: 142/142 pass (Step 3)
- [ ] CodeNarc: 0 violations (Step 4)
- [ ] validatePlugins: clean (Step 4)
- [ ] Functional tests: 0 failures (Step 5)
- [ ] Deprecation warnings: 0 (Step 6)

## Known Skipped Tests (JDK 25)

These tests are skipped by design when running on JDK 25:

| Test | Reason |
|------|--------|
| PIT 1.7.1 version test | ASM 9.7 doesn't support class file version 69 |
| PIT 1.17.1 version test | ASM 9.7 doesn't support class file version 69 |
| PIT 1.18.0 version test | ASM 9.7 doesn't support class file version 69 |
| RegularFileProperty historyInputLocation | PIT internal error on JDK 25 |

These are PIT limitations, not plugin bugs. Tests pass on JDK 17/21.

## Files changed (PR scope)

19 files, +109/-79 lines. No new production classes. Changes are:
- 3 production source files (PitestPlugin, PitestAggregatorPlugin, PitestTask)
- 4 build/wrapper files
- 5 functional test specs
- 4 test project configs
- 1 .editorconfig
- 1 unit test (PitestPluginTest)
- 1 CHANGES.md
