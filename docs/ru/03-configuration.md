---
id: configuration
title: Справочник конфигурации
sidebar_label: Справочник конфигурации
---

# Справочник конфигурации

![Gradle](https://img.shields.io/badge/Gradle-8.4%2B-blue)
![PIT](https://img.shields.io/badge/PIT-1.23.0%20default-green)
![Java](https://img.shields.io/badge/Java-17%2B-orange)

Этот документ является полным справочником для DSL-расширения `pitest { }`, предоставляемого
плагином `info.solidsoft.pitest`. Каждое свойство напрямую соответствует аргументу командной строки
PIT, если не указано, что оно специфично для Gradle-плагина.

---

## Базовое использование

### Groovy DSL

```groovy
// build.gradle
plugins {
    id 'java'
    id 'info.solidsoft.pitest' version '1.15.0'
}

pitest {
    pitestVersion = '1.23.0'
    targetClasses = ['com.example.*']
    threads      = 4
    outputFormats = ['HTML', 'XML']
    mutationThreshold = 80
}
```

### Kotlin DSL

```kotlin
// build.gradle.kts
plugins {
    java
    id("info.solidsoft.pitest") version "1.15.0"
}

pitest {
    pitestVersion.set("1.23.0")
    targetClasses.set(setOf("com.example.*"))
    threads.set(4)
    outputFormats.set(setOf("HTML", "XML"))
    mutationThreshold.set(80)
}
```

> **Примечание по Kotlin DSL:** Все свойства используют `.set()` — прямое присваивание (`=`) не
> поддерживается для типов `Property<T>` Gradle. Подробнее см. раздел
> [Особенности Kotlin DSL](#особенности-kotlin-dsl).

---

## Справочник свойств

### Основные

Эти свойства управляют базовым выполнением PIT.

| Свойство | Тип | По умолчанию | Описание |
|---|---|---|---|
| `pitestVersion` | `Property<String>` | `1.23.0` | Версия PIT для разрешения из Maven Central. Переопределяет версию, встроенную в плагин. |
| `targetClasses` | `SetProperty<String>` | Производится из `project.group` (напр., `com.example.*`) | Glob-паттерны для производственных классов, подлежащих мутации. **Обязательно** при незаданном `project.group`. |
| `targetTests` | `SetProperty<String>` | Зеркало `targetClasses` | Glob-паттерны для тестовых классов для запуска. Возвращается к разрешённому значению `targetClasses` при незаданном значении. |
| `threads` | `Property<Integer>` | `null` (по умолчанию PIT: 1) | Количество параллельных потоков мутационного тестирования. |
| `mutationEngine` | `Property<String>` | `null` (по умолчанию PIT: `gregor`) | Используемый движок мутаций. Альтернативы включают `descartes` (требует плагин). |
| `failWhenNoMutations` | `Property<Boolean>` | `null` (по умолчанию PIT: `true`) | Завершать сборку с ошибкой, если PIT не находит мутаций для тестирования. Установите `false` в проектах без изменяемого кода (напр., чисто интерфейсные модули). |
| `skipFailingTests` | `Property<Boolean>` | `null` (по умолчанию PIT: `false`) | Пропускать тесты, уже падающие до мутации. Полезно для получения оценки мутаций при сломанном базовом состоянии. |
| `fullMutationMatrix` | `Property<Boolean>` | `null` (по умолчанию PIT: `false`) | Тестировать каждого мутанта против каждого теста. Значительно увеличивает время выполнения. |
| `verbosity` | `Property<String>` | `NO_SPINNER` | Уровень детализации вывода. Одно из: `QUIET`, `QUIET_WITH_PROGRESS`, `DEFAULT`, `NO_SPINNER`, `VERBOSE_NO_SPINNER`, `VERBOSE`. |
| `verbose` | `Property<Boolean>` | `null` | **Устарело с 1.9.11.** Используйте `verbosity` вместо него. |

#### Пример

```groovy
pitest {
    pitestVersion    = '1.23.0'
    targetClasses    = ['com.example.service.*', 'com.example.domain.*']
    targetTests      = ['com.example.**.*Test', 'com.example.**.*Spec']
    threads          = Runtime.runtime.availableProcessors()
    failWhenNoMutations = false
    verbosity        = 'NO_SPINNER'
}
```

---

### Отчётность

| Свойство | Тип | По умолчанию | Описание |
|---|---|---|---|
| `reportDir` | `DirectoryProperty` | `$buildDir/reports/pitest` | Директория, в которую PIT записывает результаты. Автоматически задаётся из `ReportingExtension` Gradle. |
| `outputFormats` | `SetProperty<String>` | `null` (по умолчанию PIT: `HTML`) | Форматы генерируемых отчётов. Распространённые значения: `HTML`, `XML`, `CSV`. Можно указать несколько форматов одновременно. |
| `timestampedReports` | `Property<Boolean>` | `null` (по умолчанию PIT: `true`) | Добавлять временную метку к имени директории отчёта. Установите `false`, чтобы всегда перезаписывать ту же директорию — удобно для CI. |
| `exportLineCoverage` | `Property<Boolean>` | `null` (по умолчанию PIT: `false`) | Экспортировать данные о покрытии строк вместе с результатами мутаций. Предназначено для отладки. |
| `inputCharset` | `Property<Charset>` | `null` (по умолчанию PIT: платформенный) | Кодировка для чтения исходных файлов. Псевдоним: `inputEncoding` (устарело, сохранено для совместимости с Maven-плагином). |
| `outputCharset` | `Property<Charset>` | `null` (по умолчанию PIT: платформенный) | Кодировка для записи отчётов. Псевдоним: `outputEncoding` (устарело). |

#### Пример

```groovy
pitest {
    outputFormats      = ['HTML', 'XML']
    timestampedReports = false
    reportDir          = file("$buildDir/reports/pitest")
    inputCharset       = java.nio.charset.Charset.forName('UTF-8')
    outputCharset      = java.nio.charset.Charset.forName('UTF-8')
}
```

---

### Мутации

| Свойство | Тип | По умолчанию | Описание |
|---|---|---|---|
| `mutators` | `SetProperty<String>` | `null` (по умолчанию PIT: `DEFAULTS`) | Группы мутаторов или имена отдельных мутаторов для применения. Распространённые группы: `DEFAULTS`, `STRONGER`, `ALL`. Полный список см. в [документации мутаторов PIT](https://pitest.org/quickstart/mutators/). |
| `excludedMethods` | `SetProperty<String>` | `null` | Glob-паттерны для имён методов, исключаемых из мутации. Сопоставляется только с простым именем метода (без префикса класса). |
| `excludedClasses` | `SetProperty<String>` | `null` | Glob-паттерны для производственных классов, исключаемых из мутации. |
| `excludedTestClasses` | `SetProperty<String>` | `null` | Glob-паттерны для тестовых классов, исключаемых из выполнения во время мутации. Экспериментально. |
| `avoidCallsTo` | `SetProperty<String>` | `null` | Полные имена классов/пакетов. Вызовы к ним не мутируются (напр., фреймворки логирования). |
| `detectInlinedCode` | `Property<Boolean>` | `null` (по умолчанию PIT: `false`) | Обнаруживать и обрабатывать встроенный код, генерируемый компилятором (напр., конкатенация строк). |
| `mutationThreshold` | `Property<Integer>` | `null` | Минимальный процент мутаций, которые должны быть уничтожены. Сборка завершается с ошибкой при падении ниже этого значения (0–100). |
| `coverageThreshold` | `Property<Integer>` | `null` | Минимальный процент кода, который должен быть покрыт тестами. Сборка завершается с ошибкой ниже этого значения (0–100). |
| `testStrengthThreshold` | `Property<Integer>` | `null` | Минимальный процент силы тестов. Сборка завершается с ошибкой ниже этого значения (0–100). |
| `maxSurviving` | `Property<Integer>` | `null` | Максимальное количество выживших мутантов до завершения сборки с ошибкой. Альтернатива `mutationThreshold` для абсолютных подсчётов. |
| `timeoutFactor` | `Property<BigDecimal>` | `null` (по умолчанию PIT: `1.25`) | Множитель, применяемый к нормальному времени выполнения теста для вычисления таймаута мутационных запусков. |
| `timeoutConstInMillis` | `Property<Integer>` | `null` (по умолчанию PIT: `4000`) | Константа, добавляемая к вычисленному таймауту в миллисекундах, в дополнение к вычислению `timeoutFactor`. |
| `features` | `ListProperty<String>` | `null` | Включение или отключение именованных функций PIT и плагинов. Префикс `+` для включения, `-` для отключения (напр., `+EXPORT`, `-FEWMUTANTS`). Экспериментально. |

#### Пример

```groovy
pitest {
    mutators         = ['DEFAULTS', 'REMOVE_CONDITIONALS']
    excludedClasses  = ['com.example.generated.*', '*.dto.*']
    excludedMethods  = ['toString', 'hashCode', 'equals']
    avoidCallsTo     = ['java.util.logging', 'org.slf4j', 'org.apache.log4j']
    mutationThreshold   = 80
    coverageThreshold   = 90
    testStrengthThreshold = 75
    timeoutFactor    = 2.0
    timeoutConstInMillis = 5000
    features         = ['+EXPORT']
}
```

---

### Тестирование

| Свойство | Тип | По умолчанию | Описание |
|---|---|---|---|
| `junit5PluginVersion` | `Property<String>` | `null` | Версия `org.pitest:pitest-junit5-plugin` для автоматического добавления в качестве зависимости. При задании также настраивает `testPlugin = 'junit5'`, если `testPlugin` явно не задан иначе. |
| `addJUnitPlatformLauncher` | `Property<Boolean>` | `true` | Автоматически добавлять `junit-platform-launcher` в `testRuntimeOnly`, когда в `testImplementation` найден `junit-platform-engine` или `junit-platform-commons`. Требуется для `pitest-junit5-plugin` 1.2.0+. Экспериментально. |
| `includedGroups` | `SetProperty<String>` | `null` | Категории JUnit 4 или тег-выражения JUnit 5 для включения. Во время мутации запускаются только тесты, соответствующие этим группам. |
| `excludedGroups` | `SetProperty<String>` | `null` | Категории JUnit 4 или тег-выражения JUnit 5 для исключения. |
| `includedTestMethods` | `SetProperty<String>` | `null` | Glob-паттерны для включаемых имён методов тестов. Добавлено в PIT 1.3.2. |
| `testSourceSets` | `SetProperty<SourceSet>` | `[sourceSets.test]` | Наборы источников Gradle, рассматриваемые как тестовый код. Переопределяйте при использовании пользовательских наборов источников (напр., интеграционные тесты). Специфично для Gradle-плагина. |
| `mainSourceSets` | `SetProperty<SourceSet>` | `[sourceSets.main]` | Наборы источников Gradle, рассматриваемые как производственный код для мутации. Специфично для Gradle-плагина. |
| `testPlugin` | `Property<String>` | `null` | **Устарело с GPP 1.7.4.** Не используется PIT 1.6.7+. |

#### Пример: проект JUnit 5

```groovy
dependencies {
    testImplementation 'org.junit.jupiter:junit-jupiter:5.10.0'
}

pitest {
    junit5PluginVersion = '1.2.1'
    // addJUnitPlatformLauncher = true (по умолчанию — действия не требуются)
    includedGroups = ['fast', 'unit']
    excludedGroups = ['slow', 'integration']
}
```

#### Пример: пользовательские наборы источников

```groovy
pitest {
    mainSourceSets = [sourceSets.main, sourceSets.customModule]
    testSourceSets = [sourceSets.test, sourceSets.integrationTest]
}
```

---

### Дополнительные настройки

| Свойство | Тип | По умолчанию | Описание |
|---|---|---|---|
| `jvmArgs` | `ListProperty<String>` | `null` | Аргументы JVM, передаваемые **дочерним (minion) процессам**, выполняющим мутации тестов. |
| `mainProcessJvmArgs` | `ListProperty<String>` | `null` | Аргументы JVM, передаваемые **главному процессу PIT**, запускаемому Gradle. При задании переопределяет стандартные `jvmArgs`, унаследованные от `JavaExec`. |
| `pluginConfiguration` | `MapProperty<String, String>` | `null` | Пары ключ/значение, передаваемые плагинам PIT как `--pluginConfiguration=key=value`. Каждая запись становится отдельным аргументом CLI. |
| `jvmPath` | `RegularFileProperty` | `null` (использует JVM toolchain Gradle) | Явный путь к исполняемому файлу `java`, используемому для запуска дочерних процессов PIT. |
| `additionalMutableCodePaths` | `SetProperty<File>` | `null` | Дополнительные директории или JAR-файлы, содержащие производственный код для включения в мутационный анализ. Полезно при мутации классов из выходного JAR другого подпроекта. Специфично для Gradle-плагина. |

#### Пример

```groovy
pitest {
    jvmArgs = ['-Xmx512m', '-XX:+UseG1GC']
    mainProcessJvmArgs = ['-Xmx1g']
    pluginConfiguration = [
        'arcmutate.license.key': 'YOUR-KEY',
        'gregor.mutate.static.initialisers': 'true'
    ]
}
```

---

### Файлы

| Свойство | Тип | По умолчанию | Описание |
|---|---|---|---|
| `historyInputLocation` | `RegularFileProperty` | `null` | Файл, из которого PIT читает предыдущие результаты мутаций для инкрементального анализа. Когда `enableDefaultIncrementalAnalysis` равно `true`, по умолчанию `$buildDir/pitHistory.txt`. |
| `historyOutputLocation` | `RegularFileProperty` | `null` | Файл, в который PIT записывает результаты мутаций для будущих инкрементальных запусков. Зеркалирует `historyInputLocation` при `enableDefaultIncrementalAnalysis = true`. |
| `enableDefaultIncrementalAnalysis` | `Property<Boolean>` | `null` | Включить инкрементальный анализ с использованием файла истории по умолчанию `$buildDir/pitHistory.txt`. Псевдоним: `withHistory` (сохранено для миграции с Maven-плагина). |
| `useClasspathFile` | `Property<Boolean>` | `true` | Записывать classpath во временный файл и передавать `--classPathFile` в PIT вместо длинного аргумента `--classPath`. Включено по умолчанию с 1.19.0. Позволяет избежать ограничений длины командной строки в Windows. Экспериментально. |
| `useClasspathJar` | `Property<Boolean>` | `null` | Упаковывать classpath в манифест JAR и передавать его как одну запись. Альтернатива `useClasspathFile` для окружений со строгими ограничениями длины пути. Требует PIT 1.4.2+. Экспериментально. |
| `fileExtensionsToFilter` | `ListProperty<String>` | `['pom', 'so', 'dll', 'dylib']` | Расширения файлов для удаления из classpath перед передачей в PIT. PIT завершается с ошибкой на нативных библиотеках и не-Java записях classpath. При необходимости добавляйте специфичные для проекта расширения. Специфично для Gradle-плагина. Экспериментально. |

#### Пример

```groovy
pitest {
    enableDefaultIncrementalAnalysis = true
    // historyInputLocation и historyOutputLocation задаются автоматически

    useClasspathFile = true

    // Добавить расширения к встроенным значениям по умолчанию:
    fileExtensionsToFilter.addAll('xml', 'orbit')
}
```

> **Примечание:** Оператор `+=` для `fileExtensionsToFilter` не поддерживается из-за ограничения
> Gradle ([gradle#10475](https://github.com/gradle/gradle/issues/10475)). Всегда используйте
> `.addAll(...)` для расширения списка по умолчанию.

---

## Конфигурация плагина-агрегатора

Плагин `info.solidsoft.pitest.aggregator` регистрирует задачу `pitestReportAggregate`, объединяющую
отчёты PIT из всех подпроектов в единый HTML-отчёт. Он объявляется отдельно и, как правило,
применяется к корневому проекту.

### Подключение плагина

```groovy
// root build.gradle
plugins {
    id 'info.solidsoft.pitest.aggregator' version '1.15.0'
}
```

### Блок `reportAggregator { }`

Когда плагин-агрегатор применяется вместе с `info.solidsoft.pitest`, расширение `pitest { }`
предоставляет вложенный блок `reportAggregator { }`, управляющий порогами качества сборки,
применяемыми к **агрегированному** результату.

| Свойство | Тип | По умолчанию | Описание |
|---|---|---|---|
| `mutationThreshold` | `Property<Integer>` | `null` | Минимальный процент оценки мутаций для агрегированного отчёта (0–100). Сборка завершается с ошибкой ниже этого значения. |
| `testStrengthThreshold` | `Property<Integer>` | `null` | Минимальный процент силы тестов для агрегированного отчёта. |
| `maxSurviving` | `Property<Integer>` | `null` | Максимальное количество выживших мутантов во всех подпроектах. |

```groovy
// Groovy DSL
pitest {
    reportAggregator {
        mutationThreshold     = 75
        testStrengthThreshold = 70
        maxSurviving          = 10
    }
}
```

```kotlin
// Kotlin DSL
pitest {
    reportAggregator {
        mutationThreshold.set(75)
        testStrengthThreshold.set(70)
        maxSurviving.set(10)
    }
}
```

### Структура многомодульного проекта

```groovy
// settings.gradle
rootProject.name = 'my-app'
include 'core', 'api', 'web'
```

```groovy
// root build.gradle
plugins {
    id 'info.solidsoft.pitest.aggregator' version '1.15.0'
}

pitest {
    reportAggregator {
        mutationThreshold = 75
    }
}
```

```groovy
// core/build.gradle, api/build.gradle, web/build.gradle (одинаково для каждого)
plugins {
    id 'java'
    id 'info.solidsoft.pitest' version '1.15.0'
}

pitest {
    pitestVersion = '1.23.0'
    targetClasses = ["com.example.${project.name}.*"]
    outputFormats = ['XML']   // XML обязателен для агрегации
    exportLineCoverage = true // покрытие строк обязательно для агрегации
    timestampedReports = false
}
```

Запуск агрегации:

```bash
./gradlew pitestReportAggregate
```

Задача автоматически запускается после всех задач `pitest` через `mustRunAfter`. Для запуска
всего в одной команде:

```bash
./gradlew pitest pitestReportAggregate
```

---

## Примеры конфигурации

### Минимальная

Подходит для простого одномодульного проекта с уже заданным `project.group`.

```groovy
pitest {
    junit5PluginVersion = '1.2.1'
    outputFormats       = ['HTML']
    mutationThreshold   = 70
}
```

`targetClasses` выводится автоматически из `project.group` (напр., если `group = 'com.example'`,
то `targetClasses = ['com.example.*']`).

---

### Типовая

Реалистичная конфигурация для приложения Spring Boot с JUnit 5.

```groovy
pitest {
    pitestVersion       = '1.23.0'
    junit5PluginVersion = '1.2.1'

    targetClasses = ['com.example.service.*', 'com.example.domain.*']
    excludedClasses = [
        'com.example.**.*Config',
        'com.example.**.*Application'
    ]
    excludedMethods = ['toString', 'hashCode', 'equals', 'canEqual']
    avoidCallsTo    = ['org.slf4j', 'org.springframework.util.Assert']

    threads          = 4
    outputFormats    = ['HTML', 'XML']
    timestampedReports = false
    mutationThreshold  = 80

    enableDefaultIncrementalAnalysis = true

    jvmArgs = ['-Xmx512m']
}
```

---

### Расширенная

Полная конфигурация для производительного CI-конвейера с пользовательскими порогами, инкрементальным
анализом и интеграцией плагинов.

```groovy
pitest {
    pitestVersion       = '1.23.0'
    junit5PluginVersion = '1.2.1'

    targetClasses = ['com.example.*']
    excludedClasses = [
        'com.example.**.generated.**',
        'com.example.**.*Dto',
        'com.example.**.*Mapper'
    ]
    excludedMethods    = ['toString', 'hashCode', 'equals', 'canEqual', 'builder']
    excludedTestClasses = ['com.example.**.*IT']
    avoidCallsTo       = ['org.slf4j', 'org.apache.commons.logging']

    threads          = 8
    outputFormats    = ['HTML', 'XML', 'CSV']
    timestampedReports = false

    mutators         = ['STRONGER']
    mutationThreshold   = 85
    coverageThreshold   = 90
    testStrengthThreshold = 80
    maxSurviving        = 0

    timeoutFactor       = 2.0
    timeoutConstInMillis = 8000

    enableDefaultIncrementalAnalysis = true

    useClasspathFile = true
    fileExtensionsToFilter.addAll('xml', 'yaml', 'properties')

    jvmArgs         = ['-Xmx768m', '-XX:+UseG1GC', '-XX:MaxGCPauseMillis=200']
    mainProcessJvmArgs = ['-Xmx2g']

    features        = ['+EXPORT']
    pluginConfiguration = [
        'gregor.mutate.static.initialisers': 'true'
    ]

    inputCharset  = java.nio.charset.Charset.forName('UTF-8')
    outputCharset = java.nio.charset.Charset.forName('UTF-8')
}
```

---

## Особенности Kotlin DSL

При использовании `build.gradle.kts` есть несколько отличий от Groovy DSL.

### Все присваивания свойств используют `.set()`

```kotlin
// Правильно
pitest {
    pitestVersion.set("1.23.0")
    targetClasses.set(setOf("com.example.*"))
    threads.set(4)
    timestampedReports.set(false)
}

// Неправильно — не компилируется
pitest {
    pitestVersion = "1.23.0"   // ошибка компиляции
}
```

### Свойства-коллекции используют типизированные фабричные функции

```kotlin
pitest {
    targetClasses.set(setOf("com.example.*"))     // SetProperty
    outputFormats.set(setOf("HTML", "XML"))        // SetProperty
    jvmArgs.set(listOf("-Xmx512m"))               // ListProperty
    mutators.set(setOf("DEFAULTS"))                // SetProperty
    features.set(listOf("+EXPORT"))               // ListProperty
}
```

### Расширение списков по умолчанию с помощью `addAll`

```kotlin
pitest {
    fileExtensionsToFilter.addAll("xml", "orbit")
}
```

### `pluginConfiguration` требует явного типа Map

```kotlin
pitest {
    pluginConfiguration.set(
        mapOf(
            "arcmutate.license.key" to "YOUR-KEY",
            "gregor.mutate.static.initialisers" to "true"
        )
    )
}
```

### Вложенный блок `reportAggregator`

```kotlin
pitest {
    reportAggregator {
        mutationThreshold.set(75)
        testStrengthThreshold.set(70)
    }
}
```

### Свойства файлов

```kotlin
pitest {
    reportDir.set(layout.buildDirectory.dir("reports/pitest").get())
    historyInputLocation.set(layout.buildDirectory.file("pitHistory.txt").get())
    jvmPath.set(file("/usr/lib/jvm/java-17/bin/java"))
}
```

### `mainSourceSets` и `testSourceSets`

```kotlin
pitest {
    mainSourceSets.set(setOf(sourceSets["main"], sourceSets["generatedSources"]))
    testSourceSets.set(setOf(sourceSets["test"], sourceSets["integrationTest"]))
}
```

---

## См. также

- [Справочник мутаторов PIT](https://pitest.org/quickstart/mutators/)
- [Плагин PIT JUnit 5](https://github.com/szpak/gradle-pitest-plugin#junit5)
- [gradle-pitest-plugin на GitHub](https://github.com/szpak/gradle-pitest-plugin)
- [Gradle Provider API](https://docs.gradle.org/current/userguide/lazy_configuration.html)
