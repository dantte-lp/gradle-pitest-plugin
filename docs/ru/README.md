# Документация gradle-pitest-plugin

![Version](https://img.shields.io/badge/Version-1.20.0--SNAPSHOT-1a73e8?style=for-the-badge)
![Documents](https://img.shields.io/badge/Documents-7-34a853?style=for-the-badge)
![Language](https://img.shields.io/badge/Lang-Русский-ea4335?style=for-the-badge)
![Gradle](https://img.shields.io/badge/Gradle-9.4.1-02303A?style=for-the-badge&logo=gradle)

> Техническая документация для **gradle-pitest-plugin** — Gradle-плагина для
> [мутационного тестирования PIT](https://pitest.org/). Этот форк ориентирован на Gradle 9.x
> и JDK 25 LTS.

---

## Карта документации

```mermaid
graph TD
    IDX["docs/ru/README.md<br/>(Вы здесь)"]

    subgraph "Архитектура"
        A1["01-architecture.md<br/>Архитектура плагина"]
        A2["02-gradle-compat.md<br/>Совместимость с Gradle 9.x"]
    end

    subgraph "Использование"
        B1["03-configuration.md<br/>Справочник DSL"]
    end

    subgraph "Разработка"
        C1["04-development.md<br/>Dev-окружение"]
        C2["05-testing.md<br/>Руководство по тестированию"]
    end

    subgraph "Совместимость"
        D1["06-jdk-compat.md<br/>Совместимость с JDK 25"]
    end

    subgraph "Процессы"
        E1["07-changelog.md<br/>Руководство по журналу изменений"]
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

## Указатель документов

| # | Документ | Описание |
|---|----------|-------------|
| 01 | [Архитектура](01-architecture.md) | Архитектура плагина, поток задач, модель расширения, структура пакетов |
| 02 | [Совместимость с Gradle](02-gradle-compat.md) | Критические изменения Gradle 9.x, подробности миграции, матрица версий |
| 03 | [Конфигурация](03-configuration.md) | Полный справочник DSL — все свойства `pitest { }` с примерами |
| 04 | [Разработка](04-development.md) | Dev-контейнер, команды сборки, конвейер качества |
| 05 | [Тестирование](05-testing.md) | Юнит-тесты, функциональные тесты, матрица регрессии версий Gradle |
| 06 | [Совместимость с JDK](06-jdk-compat.md) | Поддержка JDK 25, ограничения ASM, влияние Groovy 4, toolchain |
| 07 | [Руководство по журналу изменений](07-changelog.md) | Как поддерживать CHANGES.md, процесс выпуска |

## Быстрые ссылки

- [Справочник DSL плагина](03-configuration.md) — начните здесь, если вы используете плагин
- [Настройка dev-контейнера](04-development.md#настройка-dev-контейнера) — начните здесь, если вы вносите вклад
- [Миграция на Gradle 9.x](02-gradle-compat.md) — что изменилось и почему
- [Примечания о JDK 25](06-jdk-compat.md) — ограничения версий ASM/PIT

## Другие языки

- [English](../en/README.md)
