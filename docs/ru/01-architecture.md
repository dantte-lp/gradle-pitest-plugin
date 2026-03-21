---
id: architecture
title: Архитектура
sidebar_label: Архитектура
---

# Архитектура

![Maven Central](https://img.shields.io/maven-central/v/info.solidsoft.gradle.pitest/gradle-pitest-plugin)
[![Gradle Plugin Portal](https://img.shields.io/gradle-plugin-portal/v/info.solidsoft.pitest)](https://plugins.gradle.org/plugin/info.solidsoft.pitest)
![Gradle 8.4+](https://img.shields.io/badge/Gradle-8.4%2B-blue)
![Java 17+](https://img.shields.io/badge/Java-17%2B-blue)
![Groovy @CompileStatic](https://img.shields.io/badge/Groovy-%40CompileStatic-green)

## Обзор

`gradle-pitest-plugin` интегрирует [мутационное тестирование PIT](https://pitest.org/) в сборки Gradle. Плагин связывает модель задач Gradle и интерфейс командной строки PIT: он преобразует конфигурацию DSL в аргументы CLI, формирует корректный classpath и запускает PIT в дочернем процессе JVM через `JavaExec`.

Плагин поставляет два независимых плагина в одном артефакте:

| Идентификатор плагина | Назначение | Входной класс |
|---|---|---|
| `info.solidsoft.pitest` | Мутационный анализ для одного проекта Gradle | `PitestPlugin` |
| `info.solidsoft.pitest.aggregator` | Сводный HTML-отчёт для многомодульных сборок | `PitestAggregatorPlugin` |

Оба плагина при применении проверяют минимальную версию Gradle — **8.4**. Версия PIT по умолчанию — **1.23.0**.

> **Соглашение по Groovy.** Весь производственный код аннотирован `@CompileStatic`. Динамическая диспетчеризация допускается исключительно в тестовом коде. Это устраняет целый класс ошибок типов во время выполнения и делает навигацию в IDE надёжной.

---

## Структура пакетов

```
src/main/groovy/info/solidsoft/gradle/pitest/
├── PitestPlugin.groovy                 # Основной плагин
├── PitestPluginExtension.groovy        # DSL-расширение (pitest { ... })
├── PitestTask.groovy                   # @CacheableTask, расширяет JavaExec
├── PitestAggregatorPlugin.groovy       # Плагин агрегации для многомодульных проектов
├── AggregateReportTask.groovy          # Задача агрегации (Worker API)
├── AggregateReportGenerator.groovy     # Реализация WorkAction
├── AggregateReportWorkParameters.groovy # Интерфейс параметров воркера
├── ReportAggregatorProperties.groovy   # Вложенный DSL-блок для агрегатора
└── internal/
    ├── GradleVersionEnforcer.groovy    # Проверка минимальной версии Gradle
    └── GradleUtil.groovy               # Утилиты для работы со свойствами проекта
```

---

## Архитектура основного плагина

### Последовательность инициализации

`PitestPlugin` применяется к любому проекту Gradle, в котором также применён `JavaPlugin`. Вся настройка выполняется лениво внутри коллбэка `plugins.withType(JavaPlugin)` — расширение и задача не создаются, если проект не использует Java.

```kroki-mermaid
graph TD
    A[build.gradle\napply plugin: 'info.solidsoft.pitest'] --> B[PitestPlugin.apply]
    B --> C[GradleVersionEnforcer\nfailBuild если Gradle < 8.4]
    B --> D[createConfiguration\nконфигурация pitest]
    B --> E{JavaPlugin\nприсутствует?}
    E -->|да, ленивый коллбэк| F[setupExtensionWithDefaults\nсоздаёт PitestPluginExtension]
    E -->|нет| Z[пропуск — задача не регистрируется]
    F --> G[addPitDependencies\norg.pitest:pitest-command-line]
    F --> H[tasks.register 'pitest'\nPitestTask]
    H --> I[configureTaskDefault\nсвязывает цепочки Provider\nрасширение → входные данные задачи]
    G --> J[конфигурация pitest\nразрешается во время выполнения]
    I --> K[PitestTask\n@CacheableTask расширяет JavaExec]
```

### Ответственность компонентов

```kroki-mermaid
graph LR
    subgraph "Фаза конфигурации"
        EXT[PitestPluginExtension\nDSL-блок pitest]
        CFG[конфигурация pitest\nКонтейнер зависимостей Gradle]
    end

    subgraph "Фаза выполнения"
        TASK[PitestTask\nПодпроцесс JavaExec]
        PIT[PIT CLI\norg.pitest...MutationCoverageReport]
        RPT[HTML / XML отчёты\nbuild/reports/pitest/]
    end

    EXT -->|Цепочки Provider\nленивое связывание| TASK
    CFG -->|launchClasspath\nразрешается при выполнении| TASK
    TASK -->|--targetClasses --reportDir\n--classPath ... 30+ аргументов| PIT
    PIT --> RPT
```

---

## Provider API и ленивые вычисления

Плагин повсеместно использует **Provider / Property API** Gradle. Никакие пути к файлам или наборы зависимостей не разрешаются во время конфигурации. Каждое свойство в `PitestPluginExtension` является `Property<T>`, `SetProperty<T>`, `ListProperty<T>`, `MapProperty<K,V>`, `DirectoryProperty` или `RegularFileProperty`.

`PitestPlugin.configureTaskDefault()` связывает свойства расширения с входными данными задачи через цепочки `.set()`:

```groovy
// Прямое связывание скалярного значения
task.threads.set(extension.threads)

// Производный провайдер — вычисляется лениво во время выполнения
task.targetClasses.set(project.providers.provider {
    if (extension.targetClasses.isPresent()) {
        return extension.targetClasses.get()
    }
    if (project.getGroup()) {
        return [project.getGroup().toString() + ".*"] as Set
    }
    return null
} as Provider<Iterable<String>>)

// Связывание коллекции файлов с фильтрацией classpath
task.additionalClasspath.setFrom(
    extension.testSourceSets.zip(extension.fileExtensionsToFilter.orElse([])) { sourceSets, extensions ->
        sourceSets*.runtimeClasspath*.elements*.map { locations ->
            locations.findAll { loc -> !extensions.any { loc.asFile.name.endsWith(".$it") } }
        }
    }
)
```

Регистрация задач использует `tasks.register()` (ленивая), но никогда `tasks.create()`. Расположение файлов выражается через `project.layout.buildDirectory.file(...)`, а не `project.buildDir`.

---

## Модель выполнения PitestTask

`PitestTask` — это `abstract class`, расширяющий `JavaExec`. Модификатор `abstract` требуется в Groovy 4 (встроенном в Gradle 9) для удовлетворения абстрактных методов с аннотацией `@Inject`, унаследованных от `JavaExec`.

`@CacheableTask` включает кэш сборки Gradle: если входные данные не изменились между сборками, закэшированный отчёт восстанавливается вместо повторного запуска PIT.

```kroki-mermaid
sequenceDiagram
    participant G as Движок выполнения Gradle
    participant T as PitestTask.exec()
    participant C as argumentsForPit()
    participant J as JavaExec (дочерний JVM)
    participant P as PIT CLI

    G->>T: выполнить задачу
    T->>C: taskArgumentMap() — собрать 30+ аргументов CLI
    C-->>T: Map[String, String] → List["--key=value"]
    T->>T: записать classpath в файл pitClasspath\n(useClasspathFile=true по умолчанию)
    T->>J: jvmArgs = mainProcessJvmArgs\nclasspath = launchClasspath\nmain = MutationCoverageReport
    J->>P: запустить дочерний JVM с собранными аргументами
    P-->>J: код завершения
    J-->>G: успех / ошибка
```

### Формирование аргументов CLI

`taskArgumentMap()` строит `Map<String, String>` из каждого настроенного свойства, отфильтровывая значения null и пустые значения. Свойства с несколькими значениями (множества, списки) объединяются запятыми. Аргумент `--pluginConfiguration` передаётся как несколько записей `--pluginConfiguration=key=value` через `multiValueArgsAsList()`.

По умолчанию classpath записывается в файл (`build/pitClasspath`), чтобы избежать ограничений длины командной строки в Windows. Это поведение управляется параметром `useClasspathFile` (включён по умолчанию начиная с 1.19.0).

---

## Управление зависимостями

`PitestPlugin` создаёт `Configuration` с именем `pitest` и заполняет её лениво:

| Артефакт | Условие |
|---|---|
| `org.pitest:pitest-command-line:<pitestVersion>` | Всегда добавляется |
| `org.pitest:pitest-junit5-plugin:<junit5PluginVersion>` | Когда задан `junit5PluginVersion` |
| `org.junit.platform:junit-platform-launcher:<version>` | Когда `addJUnitPlatformLauncher=true` (по умолчанию) и в `testImplementation` найден `junit-platform-engine` или `junit-platform-commons` |

Автообнаружение `junit-platform-launcher` транзитивно разрешает `testImplementation` во время конфигурации, чтобы точно совпасть с версией JUnit Platform, уже находящейся в classpath, и избежать рассогласования версий.

---

## PitestPluginExtension — свойства DSL

Блок `pitest { ... }` предоставляет 40+ свойств через `PitestPluginExtension`. Все они типизированы через `Provider` Gradle и по умолчанию имеют значение `notPresent`, если явно не указано иное.

### Значения по умолчанию, устанавливаемые плагином

| Свойство | Значение по умолчанию | Источник |
|---|---|---|
| `pitestVersion` | `1.23.0` | `PitestPlugin.DEFAULT_PITEST_VERSION` |
| `reportDir` | `build/reports/pitest` | `ReportingExtension.baseDirectory` |
| `testSourceSets` | `[sourceSets.test]` | `SourceSetContainer` |
| `mainSourceSets` | `[sourceSets.main]` | `SourceSetContainer` |
| `fileExtensionsToFilter` | `['pom', 'so', 'dll', 'dylib']` | Жёстко заданный список |
| `useClasspathFile` | `true` | Начиная с 1.19.0 |
| `verbosity` | `NO_SPINNER` | Значение по умолчанию плагина |
| `addJUnitPlatformLauncher` | `true` | Начиная с 1.14.0 |

### Сводка типов свойств

| Тип Groovy | Тип Gradle API | Используется для |
|---|---|---|
| `Property<String>` | скалярное значение | `pitestVersion`, `mutationEngine`, `verbosity`, … |
| `Property<Boolean>` | скалярное значение | `failWhenNoMutations`, `timestampedReports`, … |
| `Property<Integer>` | скалярное значение | `threads`, `mutationThreshold`, `maxSurviving`, … |
| `SetProperty<String>` | неупорядоченная коллекция | `targetClasses`, `mutators`, `excludedClasses`, … |
| `ListProperty<String>` | упорядоченная коллекция | `jvmArgs`, `mainProcessJvmArgs`, `features`, … |
| `MapProperty<String, String>` | пары ключ-значение | `pluginConfiguration` |
| `DirectoryProperty` | путь в файловой системе | `reportDir` |
| `RegularFileProperty` | путь к файлу | `historyInputLocation`, `historyOutputLocation`, `jvmPath` |
| `SetProperty<SourceSet>` | наборы источников Gradle | `testSourceSets`, `mainSourceSets` |

Поля `SetProperty` и `ListProperty`, в которых необходимо различать «не задано» и «пустая коллекция», инициализируются провайдером, возвращающим null, через вспомогательные методы `nullSetPropertyOf()` / `nullListPropertyOf()`, а не пустым соглашением.

---

## Архитектура плагина-агрегатора

`PitestAggregatorPlugin` (`@Incubating`) применяется к корневому или агрегирующему проекту. Он не требует `JavaPlugin`. Плагин собирает файлы `mutations.xml` и `linecoverage.xml` из каждого подпроекта, в котором применён `info.solidsoft.pitest`, а затем делегирует генерацию HTML-отчёта Worker API для обеспечения изоляции classloader от JVM сборки.

```kroki-mermaid
graph TD
    subgraph "Корневой проект"
        AGG[PitestAggregatorPlugin.apply]
        CFG2[конфигурация pitestReport\norg.pitest:pitest-aggregator]
        ATASK[AggregateReportTask\n@DisableCachingByDefault]
        WQ[WorkQueue\nclassLoaderIsolation]
        GEN[AggregateReportGenerator\nреализует WorkAction]
        PRA[pitest-aggregator\nReportAggregator API]
    end

    subgraph "Подпроект A"
        PA[PitestTask A]
        RA[mutations.xml\nlinecoverage.xml]
    end

    subgraph "Подпроект B"
        PB[PitestTask B]
        RB[mutations.xml\nlinecoverage.xml]
    end

    PA --> RA
    PB --> RB
    RA -->|collectMutationFiles| ATASK
    RB -->|collectMutationFiles| ATASK
    AGG --> CFG2
    AGG --> ATASK
    CFG2 --> WQ
    ATASK -->|mustRunAfter всех PitestTask| ATASK
    ATASK --> WQ
    WQ --> GEN
    GEN --> PRA
    PRA --> OUT[build/reports/pitest/index.html]
```

### Изоляция через Worker API

`AggregateReportTask` использует `WorkerExecutor.classLoaderIsolation()`. JAR-файл `pitest-aggregator` (разрешённый через конфигурацию `pitestReport`) загружается в отдельный classloader, не допуская внутренние классы PIT в classpath сборки. Параметры передаются через `AggregateReportWorkParameters` (интерфейс `WorkParameters`).

```kroki-mermaid
sequenceDiagram
    participant T as AggregateReportTask.aggregate()
    participant WE as WorkerExecutor
    participant CL as Изолированный ClassLoader\n(pitest-aggregator JAR)
    participant GEN as AggregateReportGenerator.execute()
    participant RA as ReportAggregator\n(PIT API)

    T->>WE: classLoaderIsolation { classpath = pitestReportClasspath }
    WE->>T: WorkQueue
    T->>WE: workQueue.submit(AggregateReportGenerator, params)
    WE->>CL: загрузить AggregateReportGenerator
    CL->>GEN: execute()
    GEN->>RA: builder.addMutationResultsFile()\n.addLineCoverageFile()\n.addSourceCodeDirectory()\n.build()
    RA-->>GEN: AggregationResult
    GEN->>GEN: проверить testStrengthThreshold\nпроверить mutationThreshold\nпроверить maxSurviving
    GEN-->>T: завершено / GradleException при нарушении порога
```

### Стратегия сбора отчётов

`PitestAggregatorPlugin` обнаруживает выходные данные подпроектов, перебирая `project.allprojects` во время конфигурации:

- **Исходные директории** — из `PitestTask.sourceDirs` каждой зарегистрированной `PitestTask`
- **Директории classpath** — из `PitestTask.additionalClasspath`, отфильтрованные до директорий (JAR-файлы исключаются)
- **Файлы мутаций** — `PitestPluginExtension.reportDir` + `mutations.xml` для каждого подпроекта с плагином
- **Файлы покрытия строк** — `PitestPluginExtension.reportDir` + `linecoverage.xml` для каждого подпроекта с плагином

Если `PitestPluginExtension` отсутствует в корневом проекте, агрегатор ищет в подпроектах первое доступное расширение, чтобы прочитать `pitestVersion`, `inputCharset`, `outputCharset` и настройки порогов.

---

## Справочник ключевых классов

| Класс | Пакет | Роль |
|---|---|---|
| `PitestPlugin` | `info.solidsoft.gradle.pitest` | Точка входа плагина; создаёт конфигурацию `pitest`, регистрирует задачу `pitest`, связывает все цепочки Provider от расширения к задаче |
| `PitestPluginExtension` | `info.solidsoft.gradle.pitest` | DSL-блок `pitest { }`; 40+ свойств типа Provider с `@CompileStatic`; используется только во время конфигурации |
| `PitestTask` | `info.solidsoft.gradle.pitest` | `abstract` `@CacheableTask`, расширяющий `JavaExec`; формирует карту аргументов CLI; запускает PIT в дочернем JVM |
| `PitestAggregatorPlugin` | `info.solidsoft.gradle.pitest` | `@Incubating` плагин-агрегатор; собирает выходные данные подпроектов; регистрирует задачу `pitestReportAggregate` |
| `AggregateReportTask` | `info.solidsoft.gradle.pitest` | `@Incubating` `@DisableCachingByDefault` задача; отправляет работу в `WorkerExecutor` с изоляцией classloader |
| `AggregateReportGenerator` | `info.solidsoft.gradle.pitest` | Реализация `WorkAction`; вызывает `ReportAggregator` API PIT; применяет пороговые значения оценки |
| `AggregateReportWorkParameters` | `info.solidsoft.gradle.pitest` | Интерфейс `WorkParameters`, передающий сериализуемые входные данные через границу classloader |
| `ReportAggregatorProperties` | `info.solidsoft.gradle.pitest` | Вложенный DSL-объект для порогов `pitest { reportAggregator { ... } }` |
| `GradleVersionEnforcer` | `info.solidsoft.gradle.pitest.internal` | Читает `GradleVersion.current()`; выбрасывает `GradleException` при версии ниже минимальной; может быть подавлен через `-Pgpp.disableGradleVersionEnforcement` |
| `GradleUtil` | `info.solidsoft.gradle.pitest.internal` | Единственная статическая утилита: `isPropertyNotDefinedOrFalse()` |

---

## Поток данных: от расширения до выполнения PIT

```kroki-mermaid
flowchart LR
    DSL["pitest { ... }\nDSL в build.gradle"]
    EXT["PitestPluginExtension\nПоля Property&lt;T&gt;"]
    WIRE["PitestPlugin\nconfigureTaskDefault()"]
    TINP["PitestTask\nСвойства @Input"]
    ARGM["taskArgumentMap()\nMap&lt;String,String&gt;"]
    ARGV["Список аргументов CLI\n--key=value ..."]
    CPFILE["Файл pitClasspath\nbuild/pitClasspath"]
    JVM["JavaExec\nДочерний процесс JVM"]
    PIT["PIT MutationCoverageReport\norg.pitest.*"]
    RPTH["HTML-отчёт\nbuild/reports/pitest/"]
    RPTX["XML-отчёт\nmutations.xml\nlinecoverage.xml"]

    DSL -->|set| EXT
    EXT -->|цепочка .set provider| WIRE
    WIRE -->|task.prop.set extension.prop| TINP
    TINP -->|exec| ARGM
    ARGM -->|argumentsListFromMap| ARGV
    ARGV -->|useClasspathFile=true| CPFILE
    ARGV --> JVM
    CPFILE --> JVM
    JVM -->|запуск| PIT
    PIT --> RPTH
    PIT --> RPTX
```

Переопределение `exec()` в `PitestTask` — единственная точка, где значения Provider разрешаются в конкретные значения. Это сохраняет проверку актуальности Gradle и совместимость с кэшем конфигурации — никакие пути к файлам или наборы зависимостей не материализуются до начала выполнения.

---

## Поведение кэша сборки

`PitestTask` аннотирован `@CacheableTask`. Gradle отслеживает следующие данные в качестве ключа кэша:

- Все свойства `@Input` (целевые классы, мутаторы, потоки, пороги и т. д.)
- Коллекции `@InputFiles @Classpath`: `additionalClasspath`, `launchClasspath`
- Коллекции `@InputFiles @PathSensitive(RELATIVE)`: `sourceDirs`, `mutableCodePaths`

`@OutputDirectory reportDir` восстанавливается из кэша при попадании. Свойства, помеченные `@Internal` (например, `additionalClasspathFile`, `defaultFileForHistoryData`, `jvmPath`), исключены из ключа кэша; их значения путей предоставляются отдельными геттерами `@Input String`, чтобы удовлетворить требования кэша сборки без возникновения известной проблемы Gradle [#12351](https://github.com/gradle/gradle/issues/12351) при сериализации `RegularFileProperty`.

`AggregateReportTask` аннотирован `@DisableCachingByDefault` до принятия решения о реализации в будущем.

---

## См. также

- [Документация PIT](https://pitest.org/quickstart/commandline/) — полный справочник аргументов CLI
- [Gradle Provider API](https://docs.gradle.org/current/userguide/lazy_configuration.html) — модель ленивой конфигурации
- [Gradle Worker API](https://docs.gradle.org/current/userguide/worker_api.html) — изоляция classloader, используемая агрегатором
- [Gradle Build Cache](https://docs.gradle.org/current/userguide/build_cache.html) — семантика кэширования для `@CacheableTask`
