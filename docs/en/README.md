# gradle-pitest-plugin Documentation

![Version](https://img.shields.io/badge/Version-1.20.0--SNAPSHOT-1a73e8?style=for-the-badge)
![Documents](https://img.shields.io/badge/Documents-7-34a853?style=for-the-badge)
![Language](https://img.shields.io/badge/Lang-English-ea4335?style=for-the-badge)
![Gradle](https://img.shields.io/badge/Gradle-9.4.1-02303A?style=for-the-badge&logo=gradle)

> Technical documentation for **gradle-pitest-plugin** — a Gradle plugin for [PIT mutation testing](https://pitest.org/). This fork targets Gradle 9.x and JDK 25 LTS.

---

## Documentation Map

```mermaid
graph TD
    IDX["docs/en/README.md<br/>(You are here)"]

    subgraph "Architecture"
        A1["01-architecture.md<br/>Plugin Architecture"]
        A2["02-gradle-compat.md<br/>Gradle 9.x Compatibility"]
    end

    subgraph "Usage"
        B1["03-configuration.md<br/>DSL Reference"]
    end

    subgraph "Development"
        C1["04-development.md<br/>Dev Environment"]
        C2["05-testing.md<br/>Testing Guide"]
    end

    subgraph "Compatibility"
        D1["06-jdk-compat.md<br/>JDK 25 Compatibility"]
    end

    subgraph "Process"
        E1["07-changelog.md<br/>Changelog Guide"]
    end

    IDX --> A1 & B1 & C1 & D1 & E1
    A1 --> A2
    C1 --> C2
    A2 --> D1

    style IDX fill:#1a73e8,color:#fff
    style A1 fill:#e8f0fe,color:#1a73e8
    style A2 fill:#e8f0fe,color:#1a73e8
    style B1 fill:#fef7e0,color:#e37400
    style C1 fill:#e6f4ea,color:#137333
    style C2 fill:#e6f4ea,color:#137333
    style D1 fill:#fce8e6,color:#c5221f
    style E1 fill:#f3e8fd,color:#7627bb
```

## Document Index

| # | Document | Description |
|---|----------|-------------|
| 01 | [Architecture](01-architecture.md) | Plugin architecture, task flow, extension model, package structure |
| 02 | [Gradle Compatibility](02-gradle-compat.md) | Gradle 9.x breaking changes, migration details, version matrix |
| 03 | [Configuration](03-configuration.md) | Full DSL reference — all `pitest { }` properties with examples |
| 04 | [Development](04-development.md) | Dev container, build commands, quality pipeline |
| 05 | [Testing](05-testing.md) | Unit tests, functional tests, Gradle version regression matrix |
| 06 | [JDK Compatibility](06-jdk-compat.md) | JDK 25 support, ASM constraints, Groovy 4 impacts, toolchains |
| 07 | [Changelog Guide](07-changelog.md) | How to maintain CHANGES.md, release process |

## Quick Links

- [Plugin DSL Reference](03-configuration.md) — start here if you're using the plugin
- [Dev Container Setup](04-development.md#dev-container) — start here if you're contributing
- [Gradle 9.x Migration](02-gradle-compat.md) — what changed and why
- [JDK 25 Notes](06-jdk-compat.md) — ASM/PIT version constraints

## Other Languages

- [Русский (Russian)](../ru/README.md)
