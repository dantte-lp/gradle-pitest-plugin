# Dev Container & Quality Pipeline Design

**Goal:** Adapt the jfrog-tools Containerfile.dev for gradle-pitest-plugin with a full quality pipeline (build, test, CodeNarc, security scanners).

**Base image:** jfrog-tools Containerfile.dev pattern (Oracle Linux 10, SDKMAN, GraalVM 25)

## Containerfile.dev

Stripped-down version of jfrog-tools:dev for a Groovy Gradle plugin project:

- **Keep:** GraalVM 25 (JDK), Gradle 9.4.1, SDKMAN, Semgrep, Trivy, Gitleaks, Grype, Syft, ShellCheck, Hadolint, OWASP Dependency-Check
- **Remove:** Kotlin, gradle-profiler, PMD/Checkstyle/SpotBugs standalone CLIs, Error Prone/NullAway/ArchUnit JARs, google-java-format, KICS, Checkov
- **Rationale:** CodeNarc runs via Gradle plugin (not CLI). No Java source to lint with PMD/Checkstyle. No IaC to scan.

## Quality Infrastructure

```
config/
  codenarc/codenarc.xml        (existing - no changes)
scripts/
  quality.sh                   (new - 4 modes: quick/full/security/lint)
deployment/
  containerfiles/
    Containerfile.dev           (new)
.editorconfig                  (new - from jfrog-tools pattern)
.gitleaks.toml                 (new - empty allowlist)
```

### quality.sh modes

| Mode | Tools | ~Duration |
|------|-------|-----------|
| quick | build + ShellCheck + Hadolint | 30s |
| full | build + test + funcTest + CodeNarc + Semgrep + Trivy + Gitleaks | 5-10min |
| security | Semgrep + Trivy + Gitleaks + OWASP Dep-Check | 3-5min |
| lint | ShellCheck + Hadolint + CodeNarc (via Gradle) | 1min |

### .editorconfig

From jfrog-tools with Groovy additions: `*.groovy` at 4-space indent, 120 max line length.

### .gitleaks.toml

Default rules, no allowlist needed (no secrets in codebase).
