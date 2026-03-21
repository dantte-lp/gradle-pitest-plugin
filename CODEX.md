# CODEX.md — gradle-pitest-plugin

## For OpenAI Codex / ChatGPT Code Interpreter

### Quick Start

```bash
./gradlew build          # compile + unit tests
./gradlew funcTest       # functional tests against multiple Gradle versions
./gradlew codenarc       # Groovy code lint
```

### Project Structure

- `src/main/groovy/` — plugin source (Groovy, @CompileStatic)
- `src/test/groovy/` — unit tests (Spock)
- `src/funcTest/groovy/` — functional tests (Nebula + Spock)
- `config/codenarc/` — CodeNarc rules
- `gradle/publishing.gradle` — plugin publishing config
- `deployment/containerfiles/` — dev container
- `scripts/quality.sh` — quality pipeline

### Tech Stack

| Component | Technology |
|-----------|------------|
| Language | Groovy (production: @CompileStatic) |
| Build | Gradle 9.4.1 (Groovy DSL) |
| Test | Spock 2.4, Nebula Test 10.6.2 |
| Lint | CodeNarc 2.0.0 |
| Plugin type | Gradle plugin (extends JavaExec) |
| Min Gradle | 8.4 |
| Min Java | 17 |

### Conventions

- Lazy task configuration with `tasks.register()`
- Gradle Provider/Property API for all task inputs/outputs
- `@CacheableTask` on PitestTask with proper `@Input`/`@InputFiles`/`@OutputDirectory` annotations
- Worker API with classloader isolation for report aggregation
- No Convention API (removed in Gradle 9)
- No `project.exec()` / `project.javaexec()` (removed in Gradle 9)

### Current Work

Refactoring for Gradle 9.x compatibility. See plan in `docs/superpowers/plans/`.
