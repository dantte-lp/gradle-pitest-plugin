# AGENTS.md — gradle-pitest-plugin

## Agent Configuration for AI-Assisted Development

### Project Context

This is a **Groovy Gradle plugin** project. Agents should:
- Understand Gradle Plugin Development API (Property, Provider, Task, Extension)
- Know Groovy syntax with `@CompileStatic` semantics
- Be aware of Gradle version compatibility (8.4 → 9.4.1)
- Follow existing patterns in the codebase (no new abstractions without need)

### Preferred Agent Types

| Task | Agent | Notes |
|------|-------|-------|
| Code exploration | `Explore` | Use for finding API patterns across files |
| Gradle API research | `general-purpose` | Web search for Gradle docs, deprecation guides |
| Code review | `superpowers:code-reviewer` | After completing any task |
| Plan execution | `superpowers:executing-plans` | For sprint tasks |
| Debugging | `superpowers:systematic-debugging` | For test failures |

### Key Files for Context

When working on this project, agents should read:
1. `CLAUDE.md` — project overview and conventions
2. `src/main/groovy/info/solidsoft/gradle/pitest/PitestPlugin.groovy` — main plugin
3. `src/main/groovy/info/solidsoft/gradle/pitest/PitestTask.groovy` — task implementation
4. `build.gradle` — build configuration
5. `docs/superpowers/plans/` — current implementation plans

### Quality Gates

Before claiming work is complete:
1. `./gradlew test` passes
2. `./gradlew codenarc` passes
3. `./gradlew validatePlugins` passes
4. `./gradlew build --warning-mode=all` shows no new deprecation warnings
5. ShellCheck passes on any modified shell scripts

### Gradle API Guidelines

- Use `Property<T>.set()` / `.get()` / `.getOrNull()` / `.convention()`
- Use `Provider.map()` / `.zip()` / `.flatMap()` for transformations
- Use `project.objects` (ObjectFactory) to create properties
- Use `project.providers.provider { }` for custom providers
- Use `project.layout.buildDirectory` not `project.buildDir`
- Use `DirectoryProperty.dir()` / `.file()` for lazy file resolution
