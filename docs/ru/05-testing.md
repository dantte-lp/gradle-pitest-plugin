---
id: testing
title: Руководство по тестированию
sidebar_label: Тестирование
---

# Руководство по тестированию

![Spock](https://img.shields.io/badge/Spock-2.4--groovy--4.0-green?style=flat-square)
![Nebula Test](https://img.shields.io/badge/Nebula_Test-12.0.0-blue?style=flat-square)
![Unit Tests](https://img.shields.io/badge/Unit_Tests-142-brightgreen?style=flat-square)
![Functional Tests](https://img.shields.io/badge/Functional_Tests-22_active%20%2F%204_skipped-yellow?style=flat-square)
![CodeNarc](https://img.shields.io/badge/CodeNarc-2.0.0-orange?style=flat-square)

> Это руководство описывает пирамиду тестирования, порядок запуска каждого уровня, матрицу
> регрессии версий Gradle, фильтрацию совместимости версий PIT и конфигурацию статического анализа.

---

## Пирамида тестирования

Проект использует трёхуровневую пирамиду тестирования. Каждый уровень увеличивает охват и время
выполнения при уменьшении количества тестов.

```kroki-mermaid
graph TD
    A["Юнит-тесты<br/>142 теста · Spock 2.4<br/>ProjectBuilder (в процессе)<br/>./gradlew test"]
    B["Функциональные тесты<br/>22 активных + 4 пропущенных · nebula-test<br/>Запускает реальные сборки Gradle<br/>./gradlew funcTest"]
    C["Регрессия версий Gradle<br/>Матрица PITEST_REGRESSION_TESTS<br/>6.x → 9.4.1<br/>./gradlew funcTest (полный режим)"]

    C --> B --> A

    style A fill:#2e7d32,color:#fff
    style B fill:#1565c0,color:#fff
    style C fill:#6a1b9a,color:#fff
```

| Уровень | Количество | Фреймворк | Охват | Скорость |
|---|---|---|---|---|
| Юнит | 142 | Spock 2.4-groovy-4.0 | `ProjectBuilder` в процессе | Быстрый (секунды) |
| Функциональный | 22 активных + 4 пропущенных | nebula-test 12.0.0 `IntegrationSpec` | Запускает реальные сборки Gradle | Медленный (минуты) |
| Регрессия Gradle | переменное | Параметризованные функциональные тесты | Несколько версий Gradle | Очень медленный |

---

## Юнит-тесты

### Обзор

Юнит-тесты располагаются в `src/test/groovy/info/solidsoft/gradle/pitest/` и используют Gradle
`ProjectBuilder` API для создания проектов Gradle в процессе. Это позволяет избежать запуска
внешних процессов, делая тесты быстрыми.

Все тестовые классы расширяют `Specification` Spock напрямую или используют общую настройку
через базовый класс `BasicProjectBuilderSpec`.

### Базовая настройка: `BasicProjectBuilderSpec`

`BasicProjectBuilderSpec` — общая база для тестов на основе ProjectBuilder. Она:

- Создаёт временную директорию проекта через `@TempDir`.
- Применяет плагины `java` и `info.solidsoft.pitest`.
- Получает экземпляр `PitestPluginExtension`.
- Устанавливает `project.group = 'test.group'` для удовлетворения требования `targetClasses`.
- Создаёт заглушку пустого файла classpath для удовлетворения `useClasspathFile = true`
  (по умолчанию с [#237](https://github.com/szpak/gradle-pitest-plugin/issues/237)).
- Помечает все задачи как `EXECUTED` во время конфигурации, чтобы ленивые провайдеры свойств
  могли разрешаться без ошибок.

```groovy
class BasicProjectBuilderSpec extends Specification {

    @TempDir
    protected File tmpProjectDir

    protected Project project
    protected PitestPluginExtension pitestConfig

    void setup() {
        project = ProjectBuilder.builder().withProjectDir(tmpProjectDir).build()
        project.pluginManager.apply('java')
        project.pluginManager.apply('info.solidsoft.pitest')
        pitestConfig = project.getExtensions().getByType(PitestPluginExtension)
        project.group = 'test.group'
        // создаёт заглушку pit-additional-classpath файла, чтобы useClasspathFile=true не давал сбоев
        rouchEmptyPitClasspathFileWorkaround(project)
        project.tasks.configureEach {
            state.outcome = TaskExecutionOutcome.EXECUTED
        }
    }
}
```

### Тестовые классы

| Класс | Описание |
|---|---|
| `PitestPluginTest` | Регистрация плагина, группа задач, ленивое связывание с JavaPlugin |
| `PitestPluginExtensionTest` | Значения по умолчанию расширения и типы свойств |
| `PitestTaskConfigurationSpec` | Построение аргументов задачи, отображение параметров на CLI |
| `PitestTaskPluginConfigurationTest` | Конфигурация плагина, применённая к задаче |
| `PitestTaskTestPluginConfigurationSpec` | Параметры тестового плагина, применённые к задаче |
| `PitestTaskIncrementalAnalysisTest` | Связывание `historyInputLocation` / `historyOutputLocation` |
| `PitestPluginClasspathFilteringSpec` | Логика исключения и фильтрации classpath |
| `PitestPluginTargetClassesTest` | Вывод `targetClasses` из `project.group` |
| `PitestPluginTypesConversionTest` | Преобразования типов свойств (Boolean, Integer, Charset) |
| `PitestAggregatorPluginTest` | Регистрация плагина-агрегатора и связывание задач |

### Запуск юнит-тестов

```bash
./gradlew test
```

Отчёты записываются в `build/reports/tests/test/index.html`.

Слушатель сборки проверяет, что **найден хотя бы один тест** — при `testCount == 0` сборка
завершается с `IllegalStateException`. Это предотвращает молчаливые холостые запуски.

---

## Функциональные тесты

### Обзор

Функциональные тесты располагаются в `src/funcTest/groovy/info/solidsoft/gradle/pitest/functional/`.
Они используют `IntegrationSpec` из `nebula-test` для запуска реальных сборок Gradle во временной
директории файловой системы.

> **Важно:** nebula-test 12.0.0 не опубликован в Maven Central. Его необходимо собрать из
> исходного кода (тег `v12.0.0`) с патчем `testMethodName` для Spock 2.x и установить в
> `mavenLocal` перед запуском функциональных тестов.

Все классы функциональных тестов расширяют `AbstractPitestFunctionalSpec`, который сам расширяет
`IntegrationSpec` и предоставляет:

- `fork = true` — необходимо для перехвата stdout через Gradle Tooling API.
- `memorySafeMode = true` — завершает Gradle Daemon после нескольких секунд неактивности.
- `enableConfigurationCache()` — записывает `org.gradle.configuration-cache=true` в
  `gradle.properties` для каждого тестового проекта.
- Вспомогательные методы: `getBasicGradlePitestConfig()`, `writeHelloPitClass()`, `writeHelloPitTest()`.

### Классы функциональных тестов

| Класс | Активных тестов | Примечания |
|---|---|---|
| `PitestPluginGeneralFunctionalSpec` | 4 | Общее поведение плагина, кэш сборки, кодировка |
| `PitestPluginGradleVersionFunctionalSpec` | 1 (параметризован) | Матрица версий Gradle, проверка версии |
| `PitestPluginPitVersionFunctionalSpec` | 1 (параметризован) | Совместимость версий PIT |
| `Junit5FunctionalSpec` | 6 | JUnit 5, Kotlin + JUnit 5, Spock 2, кэш конфигурации |
| `OverridePluginFunctionalSpec` | 2 активных | Переопределения командной строки через `@Option` |
| `AcceptanceTestsInSeparateSubprojectFunctionalSpec` | 2 | Многомодульные сборки, агрегация отчётов |
| `TargetClassesFunctionalSpec` | 1 | Ошибка при ненастроенном `targetClasses` |
| `TestFixturesFunctionalSpec` | 2 | Поддержка набора источников `java-test-fixtures` |

### Запуск функциональных тестов

```bash
./gradlew funcTest
```

Функциональные тесты запускаются после юнит-тестов (`funcTest.shouldRunAfter test`) и перед
`check` (`check.shouldRunAfter funcTest`). Объединённый отчёт генерируется задачей `testReport`:

```bash
./gradlew testReport
```

Объединённый отчёт объединяет бинарные результаты из `test` и `funcTest` в `build/reports/allTests/`.

---

## Матрица регрессии версий Gradle

`PitestPluginGradleVersionFunctionalSpec` содержит полную матрицу версий. Тест параметризован —
один тест-кейс генерируется для каждой записи версии Gradle.

### Списки версий

| Константа | Версии |
|---|---|
| `GRADLE6_VERSIONS` | `6.9.2`, `6.8.3`, `6.7`, `6.6`, `6.5`, `8.4` (минимальная поддерживаемая) |
| `GRADLE7_VERSIONS` | `7.6.4`, `7.5.1`, `7.4.2`, `7.4.1`, `7.3.3`, `7.2`, `7.1.1`, `7.0.2` |
| `GRADLE8_VERSIONS` | `8.14.3`, `8.13`, `8.12.1`, `8.11.1`, `8.10.2`, `8.9`, `8.8`, `8.7`, `8.6.4`, `8.5`, `8.4`, `8.3`, `8.2.1`, `8.1.1`, `8.0.2` |
| `GRADLE9_VERSIONS` | `9.4.1`, `9.4.0`, `9.3.0`, `9.2.0`, `9.1.0`, `9.0.0` |
| `GRADLE_LATEST_VERSIONS` | По одной последней из каждой мажорной серии + минимальная поддерживаемая (`8.4`) |

### Переменная окружения `PITEST_REGRESSION_TESTS`

Набор тестируемых версий Gradle управляется переменной окружения `PITEST_REGRESSION_TESTS`:

| Значение | Тестируемые версии | Типичное использование |
|---|---|---|
| `latestOnly` (по умолчанию) | Одна последняя для каждой мажорной серии | CI, ежедневная разработка |
| `quick` | То же, что `latestOnly` | Псевдоним для `latestOnly` |
| `full` | Все версии по всем четырём спискам | Валидация перед выпуском |
| _(не задано)_ | То же, что `latestOnly` | Поведение по умолчанию |

```bash
# По умолчанию (latestOnly) — быстрейший
./gradlew funcTest

# Полная матрица — все поддерживаемые версии Gradle
PITEST_REGRESSION_TESTS=full ./gradlew funcTest

# Явный latestOnly
PITEST_REGRESSION_TESTS=latestOnly ./gradlew funcTest
```

Нераспознанное значение выдаёт предупреждение и откатывается на `latestOnly`.

### Фильтрация совместимости Java / Gradle

Тест автоматически отфильтровывает версии Gradle, не поддерживающие JDK, на котором в данный
момент выполняется сборка. Это предотвращает ошибки тестов, вызванные реальной несовместимостью
Gradle / JDK, а не багами плагина:

| JDK | Минимальный Gradle |
|---|---|
| JDK 15 | 6.7 |
| JDK 16 | 7.0.2 |
| JDK 17 | 7.2 |
| JDK 21 | 8.4 |
| JDK 22 | 8.7 |
| JDK 23 | 8.10 |
| JDK 24 | 8.14 |
| JDK 25 | 9.4.1 |

Если после фильтрации остаётся менее двух версий, минимальная совместимая версия добавляется
автоматически, чтобы обеспечить хотя бы один значимый тест-кейс.

---

## Тестирование совместимости версий PIT

`PitestPluginPitVersionFunctionalSpec` проверяет корректную работу плагина с несколькими
выпусками PIT. Тест параметризован по списку версий, вычисляемому во время выполнения.

### Базовый список версий

| Версия PIT | Примечания |
|---|---|
| `1.7.1` | Минимально поддерживаемая (флаг verbosity введён в сентябре 2021) |
| `1.17.1` | Промежуточный выпуск |
| `1.18.0` | Промежуточный выпуск |
| `1.23.0` | Текущая версия по умолчанию (`DEFAULT_PITEST_VERSION`) |

### Фильтрация по версии JDK

Список версий фильтруется во время выполнения на основе JDK, запускающего сборку:

| Условие | Эффект |
|---|---|
| JDK > 17 | `1.7.1` удаляется (ограничения ASM на более новых class-файлах) |
| JDK >= 25 | Все версии PIT < `1.19.0` удаляются (ASM 9.7.x не поддерживает class-файл версии 69) |

**Основная причина:** Версии PIT до `1.19.0` включают ASM 9.7.x, который не может разбирать
class-файлы JDK 25 (формат class-файла версии 69). Любая версия PIT, которая не смогла бы
инструментировать тестовый проект под текущим JDK, исключается до построения параметризации теста.

### Что проверяет каждый параметризованный кейс

```
result.standardOutput.contains("Using PIT: ${pitVersion}")
result.standardOutput.contains("pitest-${pitVersion}.jar")
result.standardOutput.contains('Generated 2 mutations Killed 1 (50%)')
result.standardOutput.contains('Ran 2 tests (1 tests per mutation)')
```

---

## Известные пропускаемые тесты

Следующие тесты явно пропускаются при определённых условиях выполнения. Пропуск реализован
через аннотации Spock `@IgnoreIf` или `@PendingFeature`.

| Тест | Класс | Механизм | Условие | Причина |
|---|---|---|---|---|
| `allow to use RegularFileProperty @Input and @Output fields in task` | `PitestPluginGeneralFunctionalSpec` | `@IgnoreIf` | `Runtime.version().feature() >= 25` | PIT завершается с ошибкой при `historyInputLocation` на JDK 25+ из-за внутренней ошибки PIT, не связанной с плагином |
| `should fail with meaningful error message with too old Gradle version` | `PitestPluginGradleVersionFunctionalSpec` | `@IgnoreIf` | `javaVersion >= 13` | Не существует неподдерживаемой версии Gradle, совместимой с JDK 13+; тест не может воспроизвести нужный путь с ошибкой |
| `should allow to override String configuration parameter from command line` | `OverridePluginFunctionalSpec` | `@PendingFeature` | Всегда (известное ограничение) | `gradle-override-plugin` и `@Option` не работают с `DirectoryProperty`; ожидается завершение с `GradleException` |
| `should allow to define features from command line and override those from configuration` | `OverridePluginFunctionalSpec` | `@PendingFeature` | Всегда (известное ограничение) | Ещё не реализовано из-за ограничений Gradle с переопределениями `@Option` типа list; отслеживается в [#139](https://github.com/szpak/gradle-pitest-plugin/issues/139) |

---

## Поток выполнения тестов

```kroki-mermaid
sequenceDiagram
    participant Dev as Разработчик
    participant Gradle as Сборка Gradle
    participant JUnit as JUnit Platform
    participant PB as ProjectBuilder (юнит)
    participant NB as nebula-test (функц.)
    participant ExtG as Внешний процесс Gradle

    Dev->>Gradle: ./gradlew test
    Gradle->>JUnit: useJUnitPlatform()
    JUnit->>PB: Запустить Spock specs
    PB->>PB: применить плагины в процессе
    PB-->>JUnit: утверждения успешны / провалены
    JUnit-->>Gradle: 142 теста завершены

    Dev->>Gradle: ./gradlew funcTest
    Gradle->>JUnit: useJUnitPlatform()
    JUnit->>NB: Запустить IntegrationSpec
    NB->>NB: Записать build-файлы во временную директорию
    NB->>ExtG: Запустить сборку Gradle (fork=true)
    ExtG-->>NB: stdout / stderr / код завершения
    NB-->>JUnit: утверждения на основе вывода
    JUnit-->>Gradle: 22 теста завершены (4 пропущено)

    Dev->>Gradle: ./gradlew testReport
    Gradle->>Gradle: Объединить бинарные результаты
    Gradle-->>Dev: build/reports/allTests/index.html
```

---

## Статический анализ: CodeNarc

CodeNarc 2.0.0 применяется ко всем наборам Groovy-источников (main, test, funcTest).

### Файл конфигурации

`config/codenarc/codenarc.xml`

### Включённые категории правил

| Категория | Примечательные исключения |
|---|---|
| `basic` | — |
| `braces` | — |
| `concurrency` | — |
| `convention` | `PublicMethodsBeforeNonPublicMethods`, `IfStatementCouldBeTernary`, `TrailingComma`, `StaticMethodsBeforeInstanceMethods` |
| `design` | `ReturnsNullInsteadOfEmptyCollection`, `AbstractClassWithoutAbstractMethod`, `AbstractClassWithPublicConstructor` |
| `dry` | `DuplicateStringLiteral` |
| `exceptions` | — |
| `formatting` | `Indentation`, `LineLength`, `ClosureStatementOnOpeningLineOfMultipleLineClosure`, `SpaceAroundMapEntryColon` (заменено пользовательским правилом) |
| `generic` | — |
| `groovyism` | — |
| `imports` | `MisorderedStaticImports` (заменено пользовательским правилом: статические импорты идут после обычных) |
| `junit` | `JUnitPublicNonTestMethod` |
| `logging` | — |
| `naming` | `MethodName`, `FactoryMethodName` (Spock использует имена методов на естественном языке) |
| `serialization` | — |
| `unnecessary` | `UnnecessaryGetter`, `UnnecessaryGString`, `UnnecessaryReturnKeyword`, `UnnecessaryElseStatement`, `UnnecessaryBooleanExpression` |
| `unused` | — |

### Переопределения пользовательских правил

```xml
<!-- Обязательный пробел после двоеточия в литералах Map -->
<rule class='org.codenarc.rule.formatting.SpaceAroundMapEntryColonRule'>
    <property name='characterAfterColonRegex' value='\ '/>
</rule>

<!-- Статические импорты должны идти ПОСЛЕ обычных импортов -->
<rule class="org.codenarc.rule.imports.MisorderedStaticImportsRule">
    <property name="comesBefore" value="false"/>
</rule>
```

### Запуск CodeNarc

```bash
./gradlew codenarc
```

При ошибке CodeNarc выводит полный текстовый отчёт в журнал предупреждений Gradle до завершения
сборки с ошибкой. HTML и текстовые отчёты также записываются в `build/reports/codenarc/`.

---

## Валидация плагина: `validatePlugins`

Задача `validatePlugins` предоставляется плагином `java-gradle-plugin` и проверяет, что все
свойства задач правильно аннотированы инкрементальными аннотациями сборки Gradle (`@Input`,
`@OutputDirectory` и т. д.).

Проект включает строжайший режим валидации:

```groovy
tasks.validatePlugins {
    enableStricterValidation = true   // включает дополнительные проверки (напр., отсутствующий @Internal)
    failOnWarning = true              // любое предупреждение считается ошибкой сборки
}
```

```bash
./gradlew validatePlugins
```

Эта задача является частью жизненного цикла `check` и также является предварительным требованием
задач публикации.

---

## Запуск полного конвейера качества

```bash
# Только компиляция + юнит-тесты + CodeNarc
./gradlew build

# Только юнит-тесты
./gradlew test

# Только функциональные тесты (latestOnly версии Gradle)
./gradlew funcTest

# Функциональные тесты со всеми версиями Gradle
PITEST_REGRESSION_TESTS=full ./gradlew funcTest

# Линтинг CodeNarc
./gradlew codenarc

# Валидация аннотаций плагина
./gradlew validatePlugins

# Показать все предупреждения об устаревании самой сборки
./gradlew build --warning-mode=all

# Полный конвейер качества через вспомогательный скрипт
bash scripts/quality.sh full
```

> Все команды должны выполняться внутри dev-контейнера. Не запускайте их непосредственно
> на хост-машине.

---

## См. также

- [CLAUDE.md](../../CLAUDE.md) — архитектура проекта, команды сборки, соглашения
- [Команды сборки](../../CLAUDE.md#build-commands) — полный список задач Gradle
- [Конвейер качества](../../CLAUDE.md#quality-pipeline) — опции `scripts/quality.sh`
- [Примечания о совместимости с JDK 25](../../CLAUDE.md#jdk-25-compatibility-notes) — ограничения ASM и исключения функциональных тестов
