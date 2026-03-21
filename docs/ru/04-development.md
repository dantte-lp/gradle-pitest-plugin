---
id: 04-development
title: Руководство по разработке
sidebar_label: Разработка
---

# Руководство по разработке

![Gradle](https://img.shields.io/badge/Gradle-9.4.1-02303A?logo=gradle)
![GraalVM](https://img.shields.io/badge/GraalVM-17%20%7C%2021%20%7C%2025-E2231A?logo=oracle)
![Groovy](https://img.shields.io/badge/Groovy-4.0-4298B8?logo=apachegroovy)
![Oracle Linux](https://img.shields.io/badge/Oracle%20Linux-10-F80000?logo=oracle)
![License](https://img.shields.io/badge/License-Apache%202.0-blue)

Это руководство охватывает настройку локальной среды разработки, запуск конвейера сборки и
тестирования, а также соглашения по коду, которых ожидают от вкладчиков.

**Все команды сборки и тестирования должны выполняться внутри dev-контейнера.** Не запускайте
Gradle, инструменты контроля качества или функциональные тесты непосредственно на хост-машине.

---

## Предварительные требования

| Инструмент | Минимальная версия | Назначение |
|------|----------------|---------|
| [Podman](https://podman.io/) | 4.x | OCI-совместимая среда выполнения контейнеров для dev-окружения |
| [Git](https://git-scm.com/) | 2.x | Контроль версий и клонирование репозитория |

JDK, Gradle и прочие инструменты качества не требуют установки на хосте. Всё работает внутри контейнера.

---

## Настройка dev-контейнера

### Сборка образа

Из корня репозитория соберите образ для разработки один раз:

```bash
podman build -f deployment/containerfiles/Containerfile.dev -t pitest-plugin:dev .
```

Ожидаемый вывод заканчивается строками:

```
All tools installed
Successfully tagged localhost/pitest-plugin:dev
```

Первая сборка занимает примерно 5 минут (загружает SDKMAN, дистрибутивы GraalVM и все бинарные файлы сканеров).

### Запуск интерактивного сеанса

```bash
podman run --rm -it -v .:/workspace:Z pitest-plugin:dev
```

Рабочая директория внутри контейнера — `/workspace`, которая монтируется из корня репозитория.
Флаг `:Z` устанавливает корректную SELinux-метку на хостах Linux.

### Запуск одной команды без интерактивного режима

```bash
podman run --rm -v .:/workspace:Z pitest-plugin:dev bash scripts/quality.sh full
```

---

## Содержимое контейнера

Образ основан на **Oracle Linux 10** и устанавливает все инструменты через SDKMAN и прямую загрузку
бинарных файлов. После сборки образа доступ в интернет не требуется.

### JDK и инструмент сборки

| Компонент | Версия | Примечания |
|-----------|---------|-------|
| Oracle Linux | 10 | Базовая ОС |
| GraalVM JDK 17 | 17.0.12-graal | Целевая версия toolchain Gradle |
| GraalVM JDK 21 | 21.0.10-graal | Целевая версия toolchain Gradle |
| GraalVM JDK 25 | 25.0.2-graal | JVM по умолчанию, `JAVA_HOME` |
| Gradle | 9.4.1 | Через SDKMAN, `GRADLE_HOME` |

GraalVM 25 — активная JVM при запуске контейнера. Механизм toolchain Gradle автоматически выбирает
GraalVM 17 или 21, когда тестовый проект запрашивает конкретную версию Java.

### Сканеры безопасности и качества

| Инструмент | Категория | Версия |
|------|----------|---------|
| [Semgrep](https://semgrep.dev/) | SAST | Последняя через pip |
| [Trivy](https://trivy.dev/) | Сканер уязвимостей | Последняя |
| [Gitleaks](https://github.com/gitleaks/gitleaks) | Обнаружение секретов | 8.27.2 |
| [Grype](https://github.com/anchore/grype) | Уязвимости SCA | Последняя |
| [Syft](https://github.com/anchore/syft) | Генератор SBOM | Последняя |
| [ShellCheck](https://www.shellcheck.net/) | Линтер shell-скриптов | 0.11.0 |
| [Hadolint](https://github.com/hadolint/hadolint) | Линтер Containerfile | 2.12.0 |
| [OWASP Dependency-Check](https://owasp.org/www-project-dependency-check/) | Аудит SCA | 12.1.0 |

JVM настроена с учётом ограничений памяти контейнера:

```
-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError
```

Параллельные сборки Gradle и кэширование сборки включены по умолчанию через `GRADLE_OPTS`.

---

## Предварительное требование: nebula-test 12.0.0

nebula-test 12.0.0 **не опубликован в Maven Central**. Перед запуском функциональных тестов
(`funcTest`) необходимо собрать его из исходного кода, применить патч для совместимости со
Spock 2.x и опубликовать в локальный Maven-кэш контейнера.

### Зачем нужен патч

nebula-test 12.0.0 вызывает `testMethodName` через правило JUnit 4 `TestName`. В Spock 2.x,
запущенном на JUnit Platform, этот метод возвращает `null`, вызывая NPE при настройке директории
тестов. Патч добавляет запасной метод `resolveMethodName()`, читающий из `specificationContext`,
когда правило JUnit возвращает null.

### Сборка и установка nebula-test

Выполните внутри контейнера (или как неинтерактивный `podman run`):

```bash
source /root/.sdkman/bin/sdkman-init.sh
cd /tmp
git clone --depth 1 --branch v12.0.0 https://github.com/nebula-plugins/nebula-test.git
cd nebula-test

# Патч BaseIntegrationSpec — исправление NPE testMethodName под Spock 2.x + JUnit Platform
cat > src/main/groovy/nebula/test/BaseIntegrationSpec.groovy << 'PATCH1'
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

# Патч IntegrationSpec — то же исправление NPE
cat > src/main/groovy/nebula/test/IntegrationSpec.groovy << 'PATCH2'
package nebula.test
import groovy.transform.CompileStatic
@CompileStatic
@Deprecated(forRemoval = true)
abstract class IntegrationSpec extends BaseIntegrationSpec implements Integration {
    def setup() { Integration.super.initialize(getClass(), resolveMethodName()) }
}
PATCH2

# Отключить подпись и опубликовать в локальный Maven-репозиторий
cat > /tmp/no-sign.gradle << 'NOSIGN'
allprojects { tasks.withType(Sign) { enabled = false } }
NOSIGN

./gradlew publishToMavenLocal -x test -x javadoc \
    -Prelease.version=12.0.0 --no-scan -I /tmp/no-sign.gradle
```

Ожидаемый вывод заканчивается строкой `BUILD SUCCESSFUL`.

**Важно:** Локальный репозиторий Maven (`~/.m2/repository`) является эфемерным внутри контейнера —
он существует только в течение текущего сеанса контейнера. Шаги по сборке nebula-test и шаги
по запуску `funcTest` должны выполняться в одном сеансе контейнера, либо необходимо использовать
том для сохранения `~/.m2`.

---

## Команды сборки

Все команды должны выполняться из `/workspace` внутри контейнера.

### Основные задачи

```bash
# Компиляция + юнит-тесты + CodeNarc + validatePlugins (стандартная проверка CI)
./gradlew build

# Только юнит-тесты
./gradlew test

# Функциональные тесты (на основе Nebula, запускает реальные сборки Gradle)
./gradlew funcTest

# Функциональные тесты — быстрый режим (только последняя версия Gradle)
PITEST_REGRESSION_TESTS=latestOnly ./gradlew funcTest

# Функциональные тесты — полная матрица (Gradle 6.x до 9.4.1)
PITEST_REGRESSION_TESTS=full ./gradlew funcTest

# Только статический анализ CodeNarc
./gradlew codenarc

# Валидация метаданных плагина Gradle
./gradlew validatePlugins

# Показать все предупреждения об устаревании (должен давать нулевой вывод для производственного кода)
./gradlew build --warning-mode=all
```

### Полная проверка

```bash
# Полная проверка, идентичная CI-шлюзу
./gradlew clean build funcTest
```

Ожидаемые результаты:
- Юнит-тесты: 142/142 проходят
- Функциональные тесты: 22 проходят, 4 пропущены (ограничения PIT/ASM на JDK 25 — не баги плагина)
- CodeNarc: 0 нарушений
- `validatePlugins`: 0 предупреждений
- Предупреждения об устаревании: 0

---

## Конвейер качества

`scripts/quality.sh` управляет полным конвейером качества в четырёх режимах. Запускайте внутри контейнера:

```bash
bash scripts/quality.sh <режим>
```

Или в неинтерактивном режиме:

```bash
podman run --rm -v .:/workspace:Z pitest-plugin:dev bash scripts/quality.sh full
```

### Режимы

| Режим | Выполняемые инструменты | Приблизительная продолжительность |
|------|---------------|---------------------|
| `quick` | `./gradlew build` + ShellCheck + Hadolint | ~30 секунд |
| `full` | `build` + `test` + `funcTest` + `codenarc` + Semgrep + Trivy + Gitleaks | 5–10 минут |
| `security` | Semgrep + Trivy + Gitleaks + OWASP Dependency-Check | 3–5 минут |
| `lint` | ShellCheck + Hadolint + `codenarc` (через Gradle) | ~1 минута |

Скрипт выводит сводку с количеством успешных/неудачных/предупрежденческих результатов и завершается
ненулевым кодом при неудаче любой проверки.

---

## Рабочий процесс разработки

```kroki-mermaid
flowchart TD
    A([Редактировать исходный код]) --> B[./gradlew build]
    B --> C{Сборка успешна?}
    C -- Нет --> A
    C -- Да --> D[./gradlew test]
    D --> E{Тесты проходят?}
    E -- Нет --> A
    E -- Да --> F[./gradlew codenarc]
    F --> G{Нет нарушений?}
    G -- Нет --> A
    G -- Да --> H[./gradlew funcTest]
    H --> I{funcTest проходит?}
    I -- Нет --> A
    I -- Да --> J[bash scripts/quality.sh full]
    J --> K{Шлюз качества пройден?}
    K -- Нет --> A
    K -- Да --> L([Готово к коммиту])

    style A fill:#4a4a6a,color:#fff
    style L fill:#2d6a2d,color:#fff
    style C fill:#6a2d2d,color:#fff
    style E fill:#6a2d2d,color:#fff
    style G fill:#6a2d2d,color:#fff
    style I fill:#6a2d2d,color:#fff
    style K fill:#6a2d2d,color:#fff
```

Рекомендуемый внутренний цикл в процессе разработки — `build`, затем `test`. Запускайте `funcTest`
только перед отправкой изменений, так как каждый вызов функционального теста запускает несколько
реальных сборок Gradle и занимает значительно больше времени.

---

## Соглашения по коду

Весь производственный Groovy-код должен соответствовать следующим соглашениям. CodeNarc применяет
эти правила автоматически через `config/codenarc/codenarc.xml`.

### Статическая компиляция

Все производственные классы должны использовать `@CompileStatic`. Динамическая диспетчеризация
запрещена в производственном коде:

```groovy
import groovy.transform.CompileStatic

@CompileStatic
class PitestPlugin implements Plugin<Project> {
    // Все вызовы методов разрешаются во время компиляции
}
```

`@CompileDynamic` допускается только в тестовом коде (`src/test/` и `src/funcTest/`).

### Provider API для свойств задач

Все входные и выходные данные задач должны использовать Gradle Provider API. Никогда не храните
сырые значения:

```groovy
// Правильно — ленивое вычисление, совместимо с кэшем конфигурации
abstract class PitestTask extends JavaExec {
    @Input
    abstract Property<String> getPitestVersion()

    @Input
    abstract SetProperty<String> getTargetClasses()

    @OutputDirectory
    abstract DirectoryProperty getReportsDirectory()
}
```

| Тип Provider | Случай использования |
|--------------|----------|
| `Property<T>` | Одиночное скалярное значение |
| `ListProperty<T>` | Упорядоченный список |
| `SetProperty<T>` | Неупорядоченное множество (без дубликатов) |
| `MapProperty<K, V>` | Пары ключ-значение |
| `DirectoryProperty` | Путь выходной/входной директории |
| `RegularFileProperty` | Путь выходного/входного файла |

### Ленивые вычисления

Никогда не разрешайте свойства файлов во время конфигурации. Используйте ленивые провайдеры для
всего разрешения файлов:

```groovy
// Правильно — разрешается во время выполнения
reportsDir = baseDirectory.dir("pitest")

// Неправильно — разрешается во время конфигурации, ломает кэш конфигурации
reportsDir = baseDirectory.asFile.get().toPath().resolve("pitest").toFile()
```

### Регистрация задач

Всегда используйте `tasks.register()` (ленивая) вместо `tasks.create()` (жадная):

```groovy
// Правильно
tasks.register("pitest", PitestTask) { task ->
    task.pitestVersion.convention(DEFAULT_PITEST_VERSION)
}

// Неправильно — настраивает задачу, даже когда она не нужна
tasks.create("pitest", PitestTask)
```

### Абстрактные классы задач

Классы задач, расширяющие `JavaExec`, должны быть объявлены `abstract`. Groovy 4 требует, чтобы
абстрактные методы `@Inject` из `JavaExec` могли быть реализованы только экземпляром Gradle, но не
конкретным подклассом:

```groovy
abstract class PitestTask extends JavaExec {
    // Конструкторы @Inject предоставляются экземпляром Gradle
}
```

### Удалённые API — не использовать

Следующие API были удалены в Gradle 9 и не должны нигде появляться в производственном коде:

| Удалённый API | Замена |
|-------------|-------------|
| `project.exec()` / `project.javaexec()` | Расширять задачу `JavaExec` напрямую |
| `project.getConvention()` (Convention API) | Extension API |
| `project.buildDir` | `project.layout.buildDirectory` |
| `tasks.create()` | `tasks.register()` |
| Репозиторий `jcenter()` | `mavenCentral()` |
| `Configuration.visible = false` | Замена не нужна (удалено в 9.0) |

---

## Структура исходного кода проекта

```
src/
  main/groovy/info/solidsoft/gradle/pitest/
    PitestPlugin.groovy              # Основная точка входа плагина
    PitestPluginExtension.groovy     # DSL-расширение (блок pitest { ... })
    PitestTask.groovy                # Абстрактная задача, расширяющая JavaExec (@CacheableTask)
    PitestAggregatorPlugin.groovy    # Агрегатор отчётов для многомодульных проектов (@Incubating)
    AggregateReportTask.groovy       # Задача Worker API для агрегации отчётов
    AggregateReportGenerator.groovy  # Реализация WorkAction
    internal/
      GradleVersionEnforcer.groovy   # Проверка минимальной версии Gradle
      GradleUtil.groovy              # Внутренние утилиты

  test/groovy/                       # Юнит-тесты (Spock, @CompileDynamic разрешён)
  funcTest/groovy/                   # Функциональные тесты (Nebula Test + Spock)

config/
  codenarc/codenarc.xml             # Конфигурация правил CodeNarc

deployment/
  containerfiles/
    Containerfile.dev               # Определение dev-контейнера

scripts/
  quality.sh                        # Оркестратор конвейера качества в 4 режимах
```

---

## См. также

- `docs/TEST-INSTRUCTIONS.md` — пошаговые инструкции по запуску полного набора тестов для проверки PR
- `CLAUDE.md` — краткий справочник по проекту для разработки с поддержкой AI
- `AGENTS.md` — конфигурация агентов и контрольный список шлюза качества
- `config/codenarc/codenarc.xml` — определения правил CodeNarc
