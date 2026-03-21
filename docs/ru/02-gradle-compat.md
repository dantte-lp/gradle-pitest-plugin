---
id: gradle-compat
title: Совместимость с Gradle 9.x
sidebar_label: Совместимость с Gradle
---

# Совместимость с Gradle 9.x

![Gradle](https://img.shields.io/badge/Gradle-8.4--9.4.1-02303A?logo=gradle)
![Java](https://img.shields.io/badge/Java-17%2B-007396?logo=openjdk)
![Groovy](https://img.shields.io/badge/Groovy-4.x-4298B8?logo=apache-groovy)
![Status](https://img.shields.io/badge/Deprecation_Warnings-0-brightgreen)

## Обзор

Начиная с версии плагина **1.19.0-rc.1**, gradle-pitest-plugin требует Gradle 8.4 в качестве минимальной
поддерживаемой версии и полностью совместим с Gradle 9.x вплоть до **9.4.1**. Этот документ описывает
каждое критическое изменение, внесённое в линейке Gradle 9.x и затронувшее данный плагин, конкретные
изменения кода для их устранения, матрицу версий и набор API, устаревших в Gradle 9.x, но ещё не
удалённых — актуальных для будущей миграции на Gradle 10.

Минимальная поддерживаемая версия Gradle проверяется во время выполнения в
`src/main/groovy/info/solidsoft/gradle/pitest/internal/GradleVersionEnforcer.groovy` и объявлена
как публичная константа в `PitestPlugin`:

```groovy
// PitestPlugin.groovy, строка 60
public static final GradleVersion MINIMAL_SUPPORTED_GRADLE_VERSION = GradleVersion.version("8.4")
```

---

## Критические изменения в Gradle 9.0

### Удаление Convention API

**Проблема Gradle:** `Project.getConvention()` и весь Convention API были удалены в Gradle 9.0.

**Статус плагина:** Уже решено в **v1.15.0** (запись в CHANGELOG, строка 65). Плагин перешёл на
`project.extensions.create()` и Provider API задолго до выпуска версии 9.0. Никаких действий
в рамках работы по совместимости с 9.x не потребовалось.

---

### Удаление `Project.exec()` и `Project.javaexec()`

**Проблема Gradle:** Удобные методы `Project.exec()` и `Project.javaexec()` были удалены в
Gradle 9.0.

**Статус плагина:** Неприменимо. `PitestTask` напрямую расширяет `JavaExec`
(`PitestTask.groovy`, строка 51) и переопределяет `exec()`, чтобы передавать аргументы во время
выполнения (`PitestTask.groovy`, строки 348–353). Вызовов `project.exec()` или
`project.javaexec()` нет нигде в производственной кодовой базе.

---

### Удаление `Project.buildDir`

**Проблема Gradle:** `Project.buildDir` и `Project.setBuildDir()` были удалены в Gradle 9.0.

**Статус плагина:** Уже решено до 1.19.0. Плагин повсеместно использует ленивый
Provider API `project.layout.buildDirectory`:

```groovy
// PitestPlugin.groovy, строки 200–209
task.additionalClasspathFile.set(
    project.layout.buildDirectory.file(PIT_ADDITIONAL_CLASSPATH_DEFAULT_FILE_NAME)
)
// ...
task.defaultFileForHistoryData.set(
    project.layout.buildDirectory.file(PIT_HISTORY_DEFAULT_FILE_NAME)
)
```

---

### Удаление репозитория `jcenter()`

**Проблема Gradle:** Встроенный репозиторий `jcenter()` был удалён в Gradle 9.0.

**Статус плагина:** Неприменимо. `build.gradle` (строка 39) использует исключительно `mavenCentral()`
для разрешения производственных зависимостей. `mavenLocal()` и `gradlePluginPortal()` присутствуют
только для toolchain сборки.

---

### Groovy 4 встроен в Gradle 9

Gradle 9 поставляется с Groovy 4 в качестве встроенной среды выполнения скриптов. Это привело к
двум конкретным проблемам для данного плагина.

#### Требование abstract-класса для задач с методами `@Inject`

**Проблема:** Groovy 4 требует, чтобы класс, содержащий абстрактные методы (в том числе унаследованные
от суперкласса и аннотированные `@Inject`), сам был объявлен `abstract`. Задача `JavaExec` Gradle
объявляет несколько абстрактных методов с `@Inject`. В Groovy 3 и ранее неабстрактный подкласс мог
быть создан без ошибок; Groovy 4 вызывает ошибку компиляции или создания экземпляра.

**Применённое исправление:** `PitestTask` изменён на `abstract class` в `src/main/groovy/info/solidsoft/gradle/pitest/PitestTask.groovy`, строка 51:

```groovy
// До (совместимость с Groovy 3)
class PitestTask extends JavaExec {

// После (требуется Groovy 4)
abstract class PitestTask extends JavaExec {
```

Это соответствует собственной рекомендации документации Gradle объявлять все пользовательские типы
задач как `abstract`.

#### Более строгое приведение типов

**Проблема:** Groovy 4 применяет более строгое приведение типов при вызове методов, тип возврата
которых является параметризованным дженериком. В `PitestPlugin.groovy` вызов:

```groovy
project.configurations.named(PITEST_CONFIGURATION_NAME).get()
```

возвращает `NamedDomainObjectProvider<Configuration>`, и Groovy 3 молча приводил результат `.get()`
к `Configuration` в вызове `setFrom()`. Groovy 4 вызывает ошибку типа. Исправление делает вызов
`.get()` явным там, где разрешённый `Configuration` используется непосредственно как `Callable`:

```groovy
// PitestPlugin.groovy, строки 217–219
task.launchClasspath.setFrom({
    project.configurations.named(PITEST_CONFIGURATION_NAME).get()
} as Callable<Configuration>)
```

---

### Аннотации допустимости null JSpecify

**Проблема Gradle:** Gradle 9.0 ввёл аннотации допустимости null JSpecify (`@Nullable`, `@NonNull`)
на публичных типах API, что может приводить к предупреждениям в инструментах IDE и процессорах
аннотаций.

**Статус плагина:** Производственный код плагина повсеместно использует `@CompileStatic` и не
полагается на аннотированный API Gradle способом, конфликтующим с JSpecify. Изменений исходного
кода не потребовалось. Задача `validatePlugins` (`build.gradle`, строка 129) с
`enableStricterValidation = true` выполняется чисто на API 9.x.

---

## Исправления устареваний в Gradle 9.1+

### Удаление `Configuration.visible`

**Проблема Gradle:** `Configuration.visible` был объявлен устаревшим в Gradle 9.1 с планируемым
удалением в Gradle 10.0. Свойство не оказывало поведенческого эффекта начиная с Gradle 9.0
(неявное поведение, при котором `visible = true` инициировало создание артефакта, было удалено в 9.0).

**Применённое исправление:** Строки `visible = false` были удалены из обоих классов плагинов.

`src/main/groovy/info/solidsoft/gradle/pitest/PitestPlugin.groovy`, строки 100–106 — комментарий
в строке 102 документирует удаление:

```groovy
private Configuration createConfiguration() {
    return project.configurations.maybeCreate(PITEST_CONFIGURATION_NAME).with { configuration ->
        //visible = false удалено: устарело в Gradle 9.1 (без эффекта с 9.0)
        description = "The PIT libraries to be used for this project."
        return configuration
    }
}
```

`src/main/groovy/info/solidsoft/gradle/pitest/PitestAggregatorPlugin.groovy`, строки 50–56 — такой
же комментарий документирует удаление в строке 52.

---

### Замена `ReportingExtension.file()` на `baseDirectory.dir()`

**Проблема Gradle:** `ReportingExtension.file(String)` был объявлен устаревшим в Gradle 9.1.
Замена — `ReportingExtension.baseDirectory.dir(String)`, которая возвращает `Provider<Directory>`
и участвует в ленивой конфигурации.

**Дополнительная проблема:** Предыдущая реализация использовала `@CompileDynamic` для обхода
`ClassNotFoundException: org.gradle.api.file.FileSystemLocationProperty` в Gradle 5.x. Поскольку
минимальная поддерживаемая версия Gradle теперь 8.4, этот обходной путь стал мёртвым кодом и
был удалён.

**Исправление в `PitestPlugin.groovy`:** Метод `setupReportDirInExtensionWithProblematicTypeForGradle5`
переименован в `setupDefaultReportDir`, а его аннотация `@CompileDynamic` удалена. Реализация
в строке 133 теперь использует полностью ленивый `baseDirectory.dir()`:

```groovy
// PitestPlugin.groovy, строки 132–134
private void setupDefaultReportDir() {
    extension.reportDir.set(project.extensions.getByType(ReportingExtension).baseDirectory.dir(PITEST_REPORT_DIRECTORY_NAME))
}
```

**Исправление в `PitestAggregatorPlugin.groovy`:** Метод `getReportBaseDirectory()` в строках 108–113
теперь возвращает `Provider<Directory>` в обеих ветках вместо немедленного разрешения в `File`:

```groovy
// PitestAggregatorPlugin.groovy, строки 108–113
private Provider<Directory> getReportBaseDirectory() {
    if (project.extensions.findByType(ReportingExtension)) {
        return project.extensions.getByType(ReportingExtension).baseDirectory
    }
    return project.layout.buildDirectory.dir("reports")
}
```

Место вызова в строке 71 связывает `.map { Directory dir -> dir.dir(...) }`, чтобы полное
разрешение оставалось ленивым до выполнения задачи.

---

### Замена замыкания `afterSuite` на интерфейс `TestListener`

**Проблема Gradle:** Методы регистрации событий на основе замыканий в задаче `Test`, включая
`afterSuite(Closure)`, были объявлены устаревшими в Gradle 9.4 с планируемым удалением в Gradle 10.0.

**Применённое исправление:** `build.gradle`, строки 114–126. Вызов замыкания `afterSuite { suite, result -> }`
заменён на `addTestListener(new TestListener() { ... })`. Три необходимых импорта добавлены
в начало `build.gradle` (строки 1–3):

```groovy
// build.gradle, строки 1-3
import org.gradle.api.tasks.testing.TestListener
import org.gradle.api.tasks.testing.TestDescriptor
import org.gradle.api.tasks.testing.TestResult

// build.gradle, строки 106–127
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

---

## Изменения в Gradle 9.4

### `java-gradle-plugin` переносит `gradleApi()` в `compileOnlyApi`

**Проблема Gradle:** В Gradle 9.4 плагин `java-gradle-plugin` изменил область видимости неявной
зависимости `gradleApi()` с `api` на `compileOnlyApi`. Это означает, что наборы источников, не
зарегистрированные как тестовые под `gradlePlugin.testSourceSets`, больше автоматически не получают
`gradleApi()` в runtime classpath.

**Влияние:** Набор источников `funcTest` использует `nebula.test.functional.GradleRunner`, которому
требуются классы Gradle API во время выполнения. Без явной регистрации функциональные тесты завершались
бы с `ClassNotFoundException` во время выполнения.

**Применённое исправление:** Два изменения в `build.gradle`:

1. Набор источников `funcTest` зарегистрирован в `gradlePlugin.testSourceSets` (строки 49–51), что
   является каноническим решением, рекомендованным командой Gradle. Это заставляет `java-gradle-plugin`
   автоматически предоставлять `gradleApi()` в classpath компиляции и выполнения funcTest:

```groovy
// build.gradle, строки 48–51
//Gradle 9.4+ переносит gradleApi() в compileOnlyApi; регистрируем funcTest для автоматического доступа к gradleApi()
gradlePlugin {
    testSourceSets sourceSets.funcTest
}
```

2. Явная зависимость `testImplementation gradleApi()` (строка 63) добавлена для юнит-тестов,
   использующих `ProjectBuilder`, поскольку изменение области видимости также затрагивает classpath
   юнит-тестов в некоторых случаях:

```groovy
// build.gradle, строка 63
//Gradle 9.4+ переносит gradleApi() в compileOnlyApi; тестам нужно это во время выполнения для ProjectBuilder
testImplementation gradleApi()
```

---

## Матрица версий

Таблица ниже показывает, какие комбинации версии Gradle, версии JDK и статуса плагина охвачены
функциональным набором тестов в
`src/funcTest/groovy/info/solidsoft/gradle/pitest/functional/PitestPluginGradleVersionFunctionalSpec.groovy`.

| Версия Gradle | JDK 17 | JDK 21 | JDK 24 | JDK 25 | Примечания |
|----------------|--------|--------|--------|--------|-------|
| 8.4            | OK     | OK     | --     | --     | Минимальная поддерживаемая версия |
| 8.5 – 8.7      | OK     | OK     | --     | --     | |
| 8.8 – 8.9      | OK     | OK     | --     | --     | |
| 8.10 – 8.11    | OK     | OK     | OK     | --     | JDK 23 требует Gradle 8.10+ |
| 8.12 – 8.13    | OK     | OK     | OK     | --     | |
| 8.14.x         | OK     | OK     | OK     | --     | JDK 24 требует Gradle 8.14+ |
| 9.0.0          | OK     | OK     | OK     | --     | Первый выпуск Gradle 9 |
| 9.1.0 – 9.2.0  | OK     | OK     | OK     | --     | |
| 9.3.0          | OK     | OK     | OK     | --     | |
| 9.4.0          | OK     | OK     | OK     | --     | Изменение области `gradleApi()` |
| 9.4.1          | OK     | OK     | OK     | OK     | JDK 25 требует Gradle 9.4.1+ |

**Обозначения:**
- `OK` — охвачено регрессионным функциональным набором тестов
- `--` — данная версия JDK не поддерживается этой версией Gradle согласно официальной матрице совместимости

**Ограничение версии PIT на JDK 25:** Версии PIT ниже 1.19.0 используют ASM 9.7, который не
поддерживает формат class-файла версии 69 (JDK 25). Функциональный набор тестов автоматически
пропускает эти версии PIT на JDK 25+ (см. `PitestPluginGradleVersionFunctionalSpec.groovy`,
`applyJavaCompatibilityAdjustment`).

Карта MINIMAL_GRADLE_VERSION_FOR_JAVA_VERSION (строки 37–50 в `PitestPluginGradleVersionFunctionalSpec.groovy`)
фиксирует эти ограничения:

```groovy
private static final Map<JavaVersion, GradleVersion> MINIMAL_GRADLE_VERSION_FOR_JAVA_VERSION = [
    (JavaVersion.VERSION_15): GradleVersion.version("6.7"),
    (JavaVersion.VERSION_16): GradleVersion.version("7.0.2"),
    (JavaVersion.VERSION_17): GradleVersion.version("7.2"),
    (JavaVersion.VERSION_21): GradleVersion.version("8.4"),
    (JavaVersion.VERSION_22): GradleVersion.version("8.7"),
    (JavaVersion.VERSION_23): GradleVersion.version("8.10"),
    (JavaVersion.VERSION_24): GradleVersion.version("8.14"),
    (JavaVersion.VERSION_25): GradleVersion.version("9.4.1"),
]
```

---

## Блок-схема миграции

Диаграмма ниже показывает процесс принятия решений при оценке каждого критического изменения
Gradle 9.x применительно к кодовой базе плагина.

```kroki-mermaid
flowchart TD
    A[Критическое изменение Gradle 9.x] --> B{Затрагивает плагин?}

    B -- Нет --> C[Документировать как неприменимо]
    B -- Да --> D{Уже исправлено\nв предыдущем выпуске?}

    D -- Да --> E[Документировать как ранее существующее исправление]
    D -- Нет --> F{Тип изменения}

    F -- API удалён --> G[Convention API\nProject.exec\nProject.buildDir\njcenter]
    F -- API устарел --> H{Версия Gradle\nустаревания}
    F -- Изменение поведения --> I[Правила компилятора\nGroovy 4]

    G --> J[Проверить неиспользование\nили выполнение миграции]
    J --> K{Используется?}
    K -- Нет --> C
    K -- Да --> L[Мигрировать на новый API]

    H -- 9.1 --> M[Configuration.visible\nReportingExtension.file\ncanBeConsumed/canBeResolved]
    H -- 9.4 --> N[замыкание afterSuite\nобласть gradleApi\nDomainObjectCollection.findAll]

    M --> O{Удаление в\nGradle 10?}
    O -- Да, срочно --> P[Исправить сейчас]
    O -- Мониторинг --> Q[Отслеживать для Gradle 10]

    N --> P

    I --> R[abstract class\nдля подкласса JavaExec]
    R --> S[PitestTask → abstract]

    P --> T[Реализовать исправление]
    T --> U[Запустить ./gradlew build\n--warning-mode=all]
    U --> V{Предупреждения?}
    V -- Да --> T
    V -- Нет --> W[Убедиться в 0 предупреждений об устаревании\n142 юнит-теста проходят\n22 функциональных теста проходят]
```

---

## API, устаревшие в Gradle 9.x — подготовка к Gradle 10

Перечисленные ниже API **ещё не удалены**, но объявлены устаревшими в Gradle 9.x и запланированы
к удалению в Gradle 10.0. Код, их использующий, будет выдавать предупреждения об устаревании при
сборке с `--warning-mode=all` в Gradle 9.x. Плагин в настоящее время выдаёт **ноль предупреждений
об устаревании** с Gradle 9.4.1.

| API | Устарел в | Планируемое удаление | Затронутый файл | Текущий статус |
|-----|--------------|-----------------|---------------|----------------|
| Прямой сеттер `Configuration.canBeConsumed` | Gradle 9.x | Gradle 10.0 | `PitestAggregatorPlugin.groovy`, строка 53 | Используется; отслеживать для руководства по миграции на Gradle 10 |
| Прямой сеттер `Configuration.canBeResolved` | Gradle 9.x | Gradle 10.0 | `PitestAggregatorPlugin.groovy`, строка 54 | Используется; отслеживать для руководства по миграции на Gradle 10 |
| `DomainObjectCollection.findAll(Closure)` | Gradle 9.4 | Gradle 10.0 | НЕ используется в плагине | Неприменимо — вызовы `findAll` в плагине используют Groovy/Java `Collection.findAll`, не Gradle `DomainObjectCollection.findAll` |
| Методы замыканий задачи `Test` (напр. `afterSuite`) | Gradle 9.4 | Gradle 10.0 | `build.gradle` | **Исправлено** — заменено интерфейсом `TestListener` |
| `ReportingExtension.file(String)` | Gradle 9.1 | Gradle 10.0 | `PitestPlugin.groovy`, `PitestAggregatorPlugin.groovy` | **Исправлено** — заменено `baseDirectory.dir()` |
| `Configuration.visible` | Gradle 9.1 | Gradle 10.0 | `PitestPlugin.groovy`, `PitestAggregatorPlugin.groovy` | **Исправлено** — удалено |

### Детали `canBeConsumed` / `canBeResolved`

Эти сеттеры используются в `PitestAggregatorPlugin.groovy` для пометки конфигурации `pitestReport`
как только для потребителя (не потребляемой, разрешаемой):

```groovy
// PitestAggregatorPlugin.groovy, строки 50–56
Configuration pitestReportConfiguration = project.configurations.create(PITEST_REPORT_AGGREGATE_CONFIGURATION_NAME).with { configuration ->
    attributes.attribute(Usage.USAGE_ATTRIBUTE, (Usage) project.objects.named(Usage, Usage.JAVA_RUNTIME))
    //visible = false удалено: устарело в Gradle 9.1 (без эффекта с 9.0)
    canBeConsumed = false
    canBeResolved = true
    return configuration
}
```

Замещающий API в Gradle 10 предположительно будет использовать методы-фабрики на основе ролей
(напр. `resolvable()` / `consumable()`). Это будет решено, когда опубликуется руководство по
миграции на Gradle 10.

### `DomainObjectCollection.findAll(Closure)` — почему это неприменимо

Вызовы `.findAll { }` в исходном коде плагина выполняются на стандартных Groovy/Java коллекциях,
а не на `DomainObjectCollection`:

- `PitestAggregatorPlugin.groovy`, строка 116: `project.allprojects.findAll { ... }` — `allprojects`
  возвращает обычный `Set<Project>`, поэтому вызывается Groovy `Collection.findAll`, а не Gradle.
- `PitestPlugin.groovy`, строка 190: лямбда внутри цепочки провайдера `zip()`, работающая на
  `List<FileSystemLocation>`.
- `PitestTask.groovy`, строка 436: `map.findAll { ... }` на обычной `Map`.

Ни одна из них не вызывает устаревший Gradle API.

---

## См. также

- [Руководство по обновлению Gradle 9.0](https://docs.gradle.org/9.0/userguide/upgrading_version_8.html)
- [Примечания к выпуску Gradle 9.4](https://docs.gradle.org/9.4/release-notes.html)
- [CHANGELOG.md](../../CHANGELOG.md) — записи для v1.15.0, v1.19.0-rc.1, v1.19.0-rc.2
- [CHANGES.md](../../CHANGES.md) — подробный журнал изменений спринта совместимости с Gradle 9.x
- `src/funcTest/groovy/info/solidsoft/gradle/pitest/functional/PitestPluginGradleVersionFunctionalSpec.groovy` — полная матрица версий и режимы регрессионного тестирования
