---
layout: post
title: Тестирование Android приложений
date: '2018-03-28 11:00:00 +0300'
categories: ru posts
---
Тестирование — одна из важнейших частей разработки качественных программных продуктов. Сегодня мы поговорим о некоторых методологиях и библиотеках, разработанных и используемых нашей командой для написания тестов Android приложений.

<center> {% include image_with_caption.html url="/images/posts/2018-03-28-advanced-android-testing/logo.png" width=520 %} </center>
Начнем с самых базовых вещей, потому более опытные разработчики могут перейти сразу к разделу об инструментах для UI тестирования. Для тех, кому хочется узнать или освежить базовые вещи — приятного чтения.

## Создание первого теста

Создадим небольшой компонент, который и будем тестировать. Он парсит файл с JSON объектом, содержащим имя, и возвращает полученную строку:

```java
public class NameRepository {
  private final File file;

  public NameRepository(File file) {
    this.file = file;
  }

  public String getName() throws IOException {
    Gson gson = new Gson();
    User user = gson.fromJson(readFile(), User.class);
    return user.name;
  }

  public String readFile() throws IOException {
    byte[] bytes = new byte[(int) file.length()];
    try (FileInputStream in = new FileInputStream(file)) {
      in.read(bytes);
    }
    return new String(bytes, Charset.defaultCharset());
  }

  private static final class User {
    String name;
  }
}
```

Тут и в дальнейшем я буду приводить сокращенную версию кода. Полную версию можно посмотреть в [репозитории](https://github.com/Monnoroch/android-testing). К каждому сниппету будет приложена ссылка на [полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/main/java/com/testing/user/NameRepository.java).

Теперь напишем первый [JUnit](http://junit.org/junit4/javadoc/4.12/overview-summary.html) тест. JUnit — это Java библиотека для написания тестов. Для того, чтобы JUnit знал, что метод является тестом, нужно добавить к нему аннотацию `@Test`. JUnit содержит в себе класс `Assert`, который позволяет сравнивать фактические значения с ожидаемыми и выводит ошибку, если значения не совпадают. Этот тест будет тестировать корректность нашего компонента, а именно чтения файла, парсинга JSON и получения верного поля:

```java
public class NameRepositoryTest {
  private static final File FILE = new File("test_file");

  NameRepository nameRepository = new NameRepository(FILE);

  @Test
  public void getName_isSasha() throws Exception {
    PrintWriter writer = new PrintWriter(
        new BufferedWriter(
            new OutputStreamWriter(new FileOutputStream(FILE), UTF_8)), true);
    writer.println("{name : Sasha}");
    writer.close();

    String name = nameRepository.getName();
    Assert.assertEquals(name, "Sasha");

    FILE.delete();
  }

  @Test
  public void getName_notMia() throws Exception {
    PrintWriter writer = new PrintWriter(
        new BufferedWriter(
            new OutputStreamWriter(new FileOutputStream(FILE), UTF_8)), true);
    writer.println("{name : Sasha}");
    writer.close();

    String name = nameRepository.getName();
    Assert.assertNotEquals(name, "Mia");

    FILE.delete();
  }
}

```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/test/java/com/testing/user/baseline/NameRepositoryTest.java)</center>

## Библиотеки для написания тестов

Тесты — это тоже код, который надо поддерживать. Более того, код тестов должен быть прост для понимания, чтобы его можно было верифицировать в уме. Потому есть смысл инвестировать в упрощение кода тестов, избавление от дублирования и повышение читабельности. Посмотрим на широко используемые библиотеки, которые помогут нам в этом деле.

Чтобы не дублировать код подготовки в каждом тесте, существуют аннотации `@Before` и `@After`. Методы, помеченные аннотацией `@Before`, будут выполняться перед каждым тестом, а помеченные аннотацией `@After` — после каждого теста. Также есть аннотации `@BeforeClass` и `@AfterClass`, которые выполняются соответственно перед и после всех тестов в классе. Давайте переделаем наш тест, используя такие методы:

```java
public class NameRepositoryTest {
  private static final File FILE = new File("test_file");

  NameRepository nameRepository = new NameRepository(FILE);

  @Before
  public void setUp() throws Exception {
    PrintWriter writer = new PrintWriter(
        new BufferedWriter(
            new OutputStreamWriter(new FileOutputStream(FILE), UTF_8)), true);
    writer.println("{name : Sasha}");
    writer.close();
  }

  @After
  public void tearDown() {
    FILE.delete();
  }

  @Test
  public void getName_isSasha() throws Exception {
    String name = nameRepository.getName();
    Assert.assertEquals(name, "Sasha");
  }

  @Test
  public void getName_notMia() throws Exception {
    String name = nameRepository.getName();
    Assert.assertNotEquals(name, "Mia");
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/test/java/com/testing/user/beforeafter/NameRepositoryTest.java)</center>

Мы смогли убрать дублирование кода настройки каждого теста. Однако, много разных классов с тестами могут потребовать создания файла, и это дублирование тоже хотелось бы убрать. Для этого есть библиотека тестовых правил ([TestRule](https://developer.android.com/reference/android/support/test/rule/package-summary.html)). Тестовое правило выполняет функцию схожую с `@Before` и `@After`. В методе apply() этого класса мы можем выполнить нужные нам действия до и после выполнения каждого или всех тестов. Помимо уменьшения дублирования кода, преимущество такого метода заключается еще и в том, что код выносится из класса тестов, что уменьшает количество кода в тесте и облегчает его чтение. Напишем правило для создания файла:

```java
public class CreateFileRule implements TestRule {
  private final File file;
  private final String text;

  public CreateFileRule(File file, String text) {
    this.file = file;
    this.text = text;
  }

  @Override
  public Statement apply(final Statement s, Description d) {
    return new Statement() {
      @Override
      public void evaluate() throws Throwable {
        PrintWriter writer =
            new PrintWriter(
                new BufferedWriter(
                    new OutputStreamWriter(
                        new FileOutputStream(FILE), UTF_8)), true);
        writer.println(text);
        writer.close();
        try {
          s.evaluate();
        } finally {
          file.delete();
        }
      }
    };
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/test/java/com/testing/rules/CreateFileRule.java)</center>

Используем это правило в нашем тесте. Для того, чтобы действия `TestRule` исполнялись для каждого теста, нужно пометить `TestRule` аннотацией `@Rule`.

```java
public class NameRepositoryTest {
  static final File FILE = new File("test_file");

  @Rule public final CreateFileRule fileRule =
    new CreateFileRule(FILE, "{name : Sasha}");

  NameRepository nameRepository = new NameRepository(new FileReader(FILE));

  @Test
  public void getName_isSasha() throws Exception {
    String name = nameRepository.getName();
    Assert.assertEquals(name, "Sasha");
  }

  ...
}

```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/test/java/com/testing/user/filerule/NameRepositoryTest.java)</center>

Если правило отметить аннотацией `@ClassRule`, то действия будут вызываться не перед каждым тестом, а один раз перед всеми тестами в классе, аналогично аннотациям `@BeforeClass` и `@AfterClass`.

Когда в тестах используется несколько `TestRule`, может понадобиться, чтобы они запускались в определенном порядке, для этого существует [RuleChain](http://junit.org/junit4/javadoc/4.12/org/junit/rules/RuleChain.html) с помощью которого можно определить порядок запуска наших `TestRule`. Создадим правило, которое должно создать папку до того, как будет создан файл:

```java
public class CreateDirRule implements TestRule {
  private final File dir;

  public CreateDirRule(File dir) {
    this.dir = dir;
  }

  @Override
  public Statement apply(final Statement s, Description d) {
    return new Statement() {
      @Override
      public void evaluate() throws Throwable {
        dir.mkdir();
        try {
          s.evaluate();
        } finally {
          dir.delete();
        }
      }
    };
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/test/java/com/testing/rules/CreateDirRule.java)</center>

С этим правилом класс с тестом будет выглядеть следующим образом:

```java
public class NameRepositoryTest {
  static final File DIR = new File("test_dir");
  static final File FILE = Paths.get(DIR.toString(), "test_file").toFile();

  @Rule
  public final RuleChain chain = RuleChain
    .outerRule(new CreateDirRule(DIR))
    .around(new CreateFileRule(FILE, "{name : Sasha}"));

  @Test
  public void getName_isSasha() throws Exception {
    String name = nameRepository.getName();
    Assert.assertEquals(name, "Sasha");
  }

  ...
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/test/java/com/testing/user/rulechain/NameRepositoryTest.java)</center>

Теперь в каждом тесте директория будет создаваться перед созданием файла и удаляться после удаления файла.

[Google Truth](https://github.com/google/truth) — это библиотека для улучшения читабельности кода тестов. Содержит методы assert (аналогично [JUnit Assert](http://junit.sourceforge.net/javadoc/org/junit/Assert.html)), но более читабельные для человека, а также включает гораздо больше вариантов для проверки параметров. Так выглядит предыдущий тест с использование Truth:

```java
@Test
public void getName_isSasha() throws Exception {
  String name = nameRepository.getName();
  assertThat(name).isEqualTo("Sasha");
}

@Test
public void getName_notMia() throws Exception {
  String name = nameRepository.getName();
  assertThat(name).isNotEqualTo("Mia");
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/test/java/com/testing/user/truth/NameRepositoryTest.java)</center>

Видно, что код читается почти как текст на разговорном английском языке.

Наш компонент делает две разных работы: читает файл и парсит его. Чтобы придерживаться принципа единственной ответственности, давайте выделим логику чтения файла в отдельный компонент:

```java
public class FileReader {
  private final File file;

  public FileReader(File file) {
    this.file = file;
  }

  public String readFile() throws IOException {
    byte[] bytes = new byte[(int) file.length()];
    try (FileInputStream in = new FileInputStream(file)) {
      in.read(bytes);
    }
    return new String(bytes, Charset.defaultCharset());
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/main/java/com/testing/common/FileReader.java)</center>

Сейчас мы хотим тестировать именно `NameRepository`, а фактически тестируем и чтение файла в `FileReader`. Чтобы этого избежать и тем самым повысить изоляцию, надежность и скорость выполнения теста, мы можем заменить реальный `FileReader` на его мок.

[Mockito](http://site.mockito.org) — библиотека для для создания заглушек (моков) вместо реальных объектов для использования их в тестах. Некоторые действия, которые можно выполнять с помощью Mockito:
создавать заглушки для классов и интерфейсов;
проверять вызовы метода и значения передаваемые этому методу;
подключение к реальному объекту «шпиона» `spy` для контроля вызова методов.

Создадим мок `FileReader` и настроим его так, чтобы метод `readFile()` возвращал нужную нам строку:

```java
public class NameRepositoryTest {
  FileReader fileReader = mock(FileReader.class);
  NameRepository nameRepository = new NameRepository(fileReader);

  @Before
  public void setUp() throws IOException {
    when(fileReader.readFile()).thenReturn("{name : Sasha}");
  }

  @Test
  public void getName_isSasha() throws Exception {
    String name = nameRepository.getName();
    assertThat(name).isEqualTo("Sasha");
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/test/java/com/testing/user/mockito/NameRepositoryTest.java)</center>

Теперь не происходит никакого чтения файла. Вместо этого, мок отдает настроенное в тесте значение.

Использование моков имеет свои преимущества:

* тесты проверяют только тестируемый класс на ошибки, ошибки других классов на проверку тестируемого класса никак не влияют
* иногда более короткий и читабельный код
* есть возможность проверять вызовы метода и передаваемые значения методам мокированного объекта

и недостатки:

* по умолчанию ненастроенные методы возвращают null, потому все используемые методы нужно настраивать явно.
* если реальный объект имеет состояние, то при каждом его предполагаемом изменении нужно перенастраивать его мок, из-за чего код тестов иногда раздувается.

Существует более простой и удобный способ создания моков — использовать специальную аннотацию `@Mock`:

```java
@Mock File file;
```

Есть три способа инициализировать такие моки:

1. Вызвать [Mockito.initMocks()](https://static.javadoc.io/org.mockito/mockito-core/2.2.28/org/mockito/MockitoAnnotations.html#initMocks(java.lang.Object)):

```java
@Before
public void setUp() {
  Mockito.initMocks(this);
}
```

2. Использовать [MockitoJUnitRunner](https://static.javadoc.io/org.mockito/mockito-core/2.2.28/org/mockito/junit/MockitoJUnitRunner.html) для запуска тестов:

```java
@RunWith(MockitoJUnitRunner.class)
```

3. Добавить в тест правило [MockitoRule](https://static.javadoc.io/org.mockito/mockito-core/2.6.5/org/mockito/junit/MockitoRule.html):

```java
@Rule public final MockitoRule rule = MockitoJUnit.rule();
```

Второй вариант максимально декларативен и компактен, но требует использования специального раннера тестов, что не всегда удобно. Последний вариант лишен этого недостатка и более декларативен, чем использование метода `initMocks()`.

```java
@RunWith(MockitoJUnitRunner.class)
public class NameRepositoryTest {
  @Mock FileReader fileReader;
  NameRepository nameRepository;

  @Before
  public void setUp() throws IOException {
    when(fileReader.readFile()).thenReturn("{name : Sasha}");
    nameRepository = new NameRepository(fileReader);
  }

  @Test
  public void getName_isSasha() throws Exception {
    String name = nameRepository.getName();
    assertThat(name).isEqualTo("Sasha");
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/test/java/com/testing/user/mockitorunner/NameRepositoryTest.java)</center>

## Host Java VM vs Android Java VM

Android тесты можно поделить на два типа: те, что можно запускать на обычной Java VM, и те, что необходимо запускать на Android Java VM. Давайте посмотрим на оба типа тестов.

### Тесты, запускаемые на обычной Java VM

Тесты для кода, не требующего работы компонентов Android API, для работы которых нужен Android-эмулятор или реальное устройство, можно запускать прямо на вашем компьютере и на любой Java-машине. Преимущественно это юнит-тесты бизнес-логики, которые тестируют изолированно отдельно взятый класс. Гораздо реже пишутся интеграционные тесты, так как далеко не всегда есть возможность создать реальные объекты классов, с которыми взаимодействует тестируемый класс.

Чтобы написать класс с Host Java тестами нужно, чтобы java файл имел путь `${moduleName}/src/test/java/...`. Также с помощью `@RunWith` аннотации указать `Runner`, который отвечает за запуск тестов, корректный вызов и обработку всех методов:

```java
@RunWith(MockitoJUnitRunner.class)
public class TestClass {...}
```

Использование этих тестов имеет множество преимуществ:

- не требуют запуска эмулятора или реального устройства, особенно это важно при прохождении тестов в [Continuous integration](https://en.wikipedia.org/wiki/Continuous_integration), где эмулятор может работать очень медленно и нет реального устройства
- очень быстро проходят, так как для этого не нужно запускать приложение, отображать UI и т.д.
- стабильны, так как нет проблем, связанных с тем, что эмулятор может зависнуть и т.д.

с другой стороны, этими тестами:

- нельзя в полной мере протестировать взаимодействие классов с операционной системой
- в частности, нельзя протестировать нажатия на UI элементы и жесты

Для того, чтобы была возможность использовать Android API классы в Host Java тестах, существует библиотека [Robolectric](http://robolectric.org/getting-started/), которая эмулирует среду Android и дает доступ к ее основным функциям. Однако, тестирование классов Android с Roboelectric часто работает нестабильно: нужно время, пока Robolectric будет поддерживать последнее API Android, существуют проблемы с получением ресурсов и т.д. Поэтому реальные классы почти не используются, а используются их моки для юнит-тестирования.

Для запуска тестов с помощью Roboelectric нужно установить кастомный [TestRunner](http://junit.sourceforge.net/junit3.8.1/javadoc/junit/textui/TestRunner.html). В нем можно настроить версию SDK (самая последняя стабильная версия — 23), обозначить основной класс `Application` и другие параметры для эмулированной среды Android.

```java
public class MainApplication extends Application {}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/main/java/com/testing/robolectric/MainApplication.java)</center>

```java
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 21, application = MainApplication.class)
public class MainApplicationTest {
  @Test
  public void packageName() {
    assertThat(RuntimeEnvironment.application)
        .isInstanceOf(MainApplication.class);
  }
}

```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/test/java/com/testing/MainApplicationTest.java)</center>

### Тесты, запускаемые на Android Java VM

Для инструментальных тестов наличие устройства или эмулятора обязательно, так как мы будем тестировать нажатие кнопок, ввод текста, и другие действия.

Чтобы написать тест для Android Java VM нужно положить java файл по пути `${moduleName}/src/androidTest/java/...`, а также с помощью `@RunWith` аннотации указать `AndroidJUnit4`, который позволит запускать тесты на устройстве Android.

```java
@RunWith(AndroidJUnit4.class)
public class TestClass {...}
```

## UI тесты

Для тестирования UI используется фреймворк [Espresso](https://developer.android.com/training/testing/ui-testing/espresso-testing.html), который предоставляет API для тестирования пользовательского интерфейса программы. В Espresso тесты работают в бэкграунд потоке, а взаимодействие с UI элементами в потоке UI. Espresso имеет несколько основных классов для тестирования:

- Espresso — основной класс. Содержит в себе статические методы, такие как нажатия на системные кнопки (Back, Home), вызвать/спрятать клавиатуру, открыть меню, обратится к компоненту.
- ViewMatchers — позволяет найти компонент на экране в текущей иерархии.
- ViewActions — позволяет взаимодействовать с компонентом (click, longClick, doubleClick, swipe, scroll и т.д.).
- ViewAssertions — позволяет проверить состояние компонента.

### Первый UI тест

Напишем простейшее Android-приложение, которое и будем тестировать:

```java
public class MainActivity extends AppCompatActivity {
  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    setContentView(R.layout.main_activity);
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/main/java/com/testing/MainActivity.java)</center>

Протестируем наше приложение. При тестировании UI прежде всего нужно запустить Activity. Для этого существует [ActivityTestRule](https://developer.android.com/reference/android/support/test/rule/ActivityTestRule.html), которое запускает Activity перед каждым тестом и закрывает после:

```java
@Rule public ActivityTestRule<MainActivity> activityTestRule =
    new ActivityTestRule<>(MainActivity.class);
```

Напишем простой тест, проверяющий, что элемент с id `R.id.container` показан на экране:

```java
@RunWith(AndroidJUnit4.class)
public class MainActivityTest {
  @Rule
  public ActivityTestRule<MainActivity> activityTestRule =
      new ActivityTestRule<>(MainActivity.class);

  @Test
  public void checkContainerIsDisplayed() {
    onView(ViewMatchers.withId(R.id.container))
        .check(matches(isDisplayed()));
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/androidTest/java/com/testing/activity/activityrule/MainActivityTest.java)</center>

## Разблокировка и включение экрана

Эмулятор на слабых или загруженных машинах может работать медленно. Поэтому между запуском эмулятора и окончанием билда с установкой приложения на эмулятор может пройти достаточно времени для того, чтобы экран заблокировался от бездействия. Таким образом тест может быть запущен при заблокированном экране, что вызовет ошибку `java.lang.RuntimeException: Could not launch activity within 45 seconds`. Поэтому перед запуском Activity нужно разблокировать и включить экран. Раз это нужно делать в каждом UI тесте, для избежания дублирования кода создадим правило, которое будет разблокировать и включать экран перед тестом:

```java
class UnlockScreenRule<A extends AppCompatActivity> implements TestRule {
  ActivityTestRule<A> activityRule;

  UnlockScreenRule(ActivityTestRule<A> activityRule) {
    this.activityRule = activityRule;
  }

  @Override
  public Statement apply(Statement statement, Description description) {
    return new Statement() {
      @Override
      public void evaluate() throws Throwable {
        activityRule.runOnUiThread(() -> activityRule
            .getActivity()
            .getWindow()
            .addFlags(
                  WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                | WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
                | WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                | WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON));
        statement.evaluate();
      }
    };
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/androidTest/java/com/testing/rules/UnlockScreenRule.java)</center>

Напишем кастомное `ActivityTestRule`, которое разблокирует экран эмулятора и запустит активити перед запуском тестов:

```java
public class ActivityTestRule<A extends AppCompatActivity> implements TestRule {
  private final android.support.test.rule.ActivityTestRule<A> activityRule;
  private final RuleChain ruleChain;

  public ActivityTestRule(Class<A> activityClass) {
    this.activityRule = new ActivityTestRule<>(activityClass, true, true);
    ruleChain = RuleChain
      .outerRule(activityRule)
      .around(new UnlockScreenRule(activityRule));
  }

  public android.support.test.rule.ActivityTestRule<A> getActivityRule() {
    return activityRule;
  }

  public void runOnUiThread(Runnable runnable) throws Throwable {
    activityRule.runOnUiThread(runnable);
  }

  public A getActivity() {
    return activityRule.getActivity();
  }

  @Override
  public Statement apply(Statement statement, Description description) {
    return ruleChain.apply(statement, description);
  }
}

```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/androidTest/java/com/testing/rules/ActivityTestRule.java)</center>

Используя это правило вместо стандартного можно сильно снизить число случайных падений UI тестов в CI.

## Тестирование фрагментов

Обычно верстка и логика UI приложения не кладется вся в активити, а разбивается на окна, для каждого из которых создается фрагмент. Давайте создадим простой фрагмент для вывода на экран имени с помощью `NameRepository`:

```java
public class UserFragment extends Fragment {
  private TextView textView;

  @Override
  public View onCreateView(
      LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
    textView = new TextView(getActivity());
    try {
      textView.setText(createNameRepository().getName());
    } catch (IOException exception) {
      throw new RuntimeException(exception);
    }
    return textView;
  }

  private NameRepository createNameRepository() {
    return new NameRepository(
        new FileReader(
            new File(
                getContext().getFilesDir().getAbsoluteFile()
                    + File.separator
                    + "test_file")));
  }

  @Override
  public void onDestroyView() {
    super.onDestroyView();
    textView = null;
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/main/java/com/testing/user/UserFragment.java)</center>

При открытии фрагмента UI может зависнуть на некоторое время, а если используются анимации переходов между фрагментами, тест может начаться до появления фрагмента. Поэтому нужно не просто открыть фрагмент, а дождаться, когда он будет запущен. Для ожидания результата выполнения действий отлично подходит библиотека [Awaitility](https://github.com/awaitility/awaitility), которая имеет очень простой и понятный синтаксис. Напишем правило, запускающее фрагмент и ожидающее его запуска с помощью этой библиотеки:

```java
class OpenFragmentRule<A extends AppCompatActivity> implements TestRule {
  private final ActivityTestRule<A> activityRule;
  private final Fragment fragment;

  OpenFragmentRule(ActivityTestRule<A> activityRule, Fragment fragment) {
    this.activityRule = activityRule;
    this.fragment = fragment;
  }

  @Override
  public Statement apply(Statement statement, Description description) {
    return new Statement() {
      @Override
      public void evaluate() throws Throwable {
        openFragment(fragment);
        await().atMost(5, SECONDS).until(fragment::isResumed);
        statement.evaluate();
      }
    };
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/androidTest/java/com/testing/rules/OpenFragmentRule.java)</center>

В данном случае выражение означает, что если в течении пяти секунд фрагмент не запустится, то тест не будет пройден. Нужно отметить, что как только фрагмент запустится, тест сразу же продолжит выполнение и не будет ждать все пять секунд.

Аналогично правилу, которое запускает активити, логично создать правило, которое запускает фрагмент:

```java
public class FragmentTestRule<A extends AppCompatActivity, F extends Fragment>
    implements TestRule {
  private ActivityTestRule<A> activityRule;
  private F fragment;
  private RuleChain ruleChain;

  public FragmentTestRule(Class<A> activityClass, F fragment) {
    this.fragment = fragment;
    this.activityRule = new ActivityTestRule<>(activityClass);
    ruleChain = RuleChain
      .outerRule(activityRule)
      .around(new OpenFragmentRule<>(activityRule, fragment));
  }

  public ActivityTestRule<A> getActivityRule() {
    return activityRule;
  }

  public F getFragment() {
    return fragment;
  }

  public void runOnUiThread(Runnable runnable) throws Throwable {
    activityRule.runOnUiThread(runnable);
  }

  public A getActivity() {
    return activityRule.getActivity();
  }

  @Override
  public Statement apply(Statement statement, Description description) {
    return ruleChain.apply(statement, description);
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/androidTest/java/com/testing/rules/FragmentTestRule.java)</center>

Тест фрагмента с использованием этого правила будет выглядеть следующим образом:

```java
@RunWith(AndroidJUnit4.class)
public class UserFragmentTest {
  @Rule
  public final RuleChain rules = RuleChain
    .outerRule(new CreateFileRule(getTestFile(), "{name : Sasha}"))
    .around(new FragmentTestRule<>(MainActivity.class, new UserFragment()));

  @Test
  public void nameDisplayed() {
    onView(withText("Sasha")).check(matches(isDisplayed()));
  }

  private File getTestFile() {
    return new File(
        InstrumentationRegistry.getTargetContext()
            .getFilesDir()
            .getAbsoluteFile() + File.separator + "test_file");
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/androidTest/java/com/testing/user/UserFragmentTest.java)</center>

## Асинхронная загрузка данных во фрагментах

Так как операции с диском, а именно получение имени из файла, может выполняться сравнительно долго, то следует эту операцию выполнять асинхронно. Для асинхронного получения имени из файла используем библиотеку [RxJava](https://github.com/ReactiveX/RxJava). Можно уверенно сказать, что RxJava сейчас используется в большинстве Android приложений. Практически каждая задача, которую нужно выполнить асинхронно, выполняется с помощью RxJava, потому что это пожалуй одна из самых удобных и понятных библиотек для асинхронного выполнения кода.

Изменим наш репозиторий так, чтобы он работал асинхронно:

```java
public class NameRepository {
  ...

  public Single<String> getName() {
    return Single.create(
        emitter -> {
          Gson gson = new Gson();
          emitter.onSuccess(
              gson.fromJson(fileReader.readFile(), User.class).getName());
        });
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/main/java/com/testing/user/rx/NameRepository.java)</center>

Для тестирования RX-кода существует специальный класс `TestObserver`, который автоматически подпишется на `Observable` и мгновенно получит результат. Тест репозитория будет выглядеть следующим образом:

```java
@RunWith(MockitoJUnitRunner.class)
public class NameRepositoryTest {
 ...

 @Test
 public void getName() {
   TestObserver<String> observer = nameRepository.getName().test();
   observer.assertValue("Sasha");
 }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/test/java/com/testing/user/rx/NameRepositoryTest.java)</center>

Обновим наш фрагмент, используя новый реактивный репозиторий:

```java
public class UserFragment extends Fragment {
  ...

  @Override
  public View onCreateView(
      LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
    textView = new TextView(getActivity());
    createNameRepository()
        .getName()
        .subscribeOn(Schedulers.io())
        .observeOn(AndroidSchedulers.mainThread())
        .subscribe(name -> textView.setText(name));
    return textView;
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/main/java/com/testing/user/awaitility/UserFragment.java)</center>

Так как теперь имя получается асинхронно, то для проверки результата работы нужно дождаться завершения асинхронного действия с помощью Awaitility:

```java
@RunWith(AndroidJUnit4.class)
public class UserFragmentTest {
  ...

  @Test
  public void nameDisplayed() {
    await()
        .atMost(5, SECONDS)
        .ignoreExceptions()
        .untilAsserted(
            () ->
                onView(ViewMatchers.withText("Sasha"))
                    .check(matches(isDisplayed())));
  }
}

```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/androidTest/java/com/testing/user/awaitility/UserFragmentTest.java)</center>

Когда во фрагменте или активити выполняются асинхронные действия, в данном случае — чтение имени из файла, нужно иметь ввиду, что фрагмент может быть закрыт пользователем до того, как асинхронное действие выполнится. В текущей версии фрагмента допущена ошибка, так как если при выполнении асинхронной операции фрагмент будет уже закрыт, то `textView` будет уже удален и равен `null`. Чтобы не допустить краша приложения с `NullPointerException` при доступе к `textView` в `subscribe()`, остановим асинхронное действие при закрытии фрагмента:

```java
public class UserFragment extends Fragment {

  private TextView textView;
  private Disposable disposable;

  @Override
  public View onCreateView(
      LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
    textView = new TextView(getActivity());
    disposable =
        createNameRepository()
            .getName()
            .subscribeOn(Schedulers.io())
            .observeOn(AndroidSchedulers.mainThread())
            .subscribe(name -> textView.setText(name));
    return textView;
  }

  @Override
  public void onDestroyView() {
    super.onDestroyView();
    disposable.dispose();
    textView = null;
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/main/java/com/testing/user/async/UserFragment.java)</center>

Для тестирования подобных ошибок, связанных с асинхронными действиям во фрагменте, нужно закрыть фрагмент сразу же после его открытия. Это можно сделать просто заменив его на другой фрагмент. Тогда при завершении асинхронного действия `onCreateView` в закрытом фрагменте `textView` будет `null` и если допустить ошибку и не отменить подписку, приложение упадет. Напишем правило для тестирования на эту ошибку:

```java
public class FragmentAsyncTestRule<A extends AppCompatActivity>
    implements TestRule {
  private final ActivityTestRule<A> activityRule;
  private final Fragment fragment;

  public FragmentAsyncTestRule(Class<A> activityClass, Fragment fragment) {
    this.activityRule = new ActivityTestRule<>(activityClass);
    this.fragment = fragment;
  }

  @Override
  public Statement apply(Statement base, Description description) {
    return new Statement() {
      @Override
      public void evaluate() throws Throwable {
        try {
          base.evaluate();
        } finally {
          activityRule.launchActivity(new Intent());
          openFragment(fragment);
          openFragment(new Fragment());
        }
      }
    };
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/androidTest/java/com/testing/rules/FragmentAsyncTestRule.java)</center>

Добавим это правило в класс тестов фрагмента:

```java
@RunWith(AndroidJUnit4.class)
public class UserFragmentTest {
  @ClassRule
  public static TestRule asyncRule =
      new FragmentAsyncTestRule<>(MainActivity.class, new UserFragment());

  ...
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/androidTest/java/com/testing/user/async/UserFragmentTest.java)</center>

Теперь тест упадет, если асинхронные действия будут обращаться к полям фрагмента после его завершения.

## Юнит-тестирование Rx кода

Создадим презентер, куда мы вынесем логику подписки на возвращаемый репозиторием `Observable` из фрагмента, а также добавим `timeout` для получения имени из файла:

```java
public class UserPresenter {
  public interface Listener {
    void onUserNameLoaded(String name);
    void onGettingUserNameError(String message);
  }

  private final Listener listener;
  private final NameRepository nameRepository;

  public UserPresenter(Listener listener, NameRepository nameRepository) {
    this.listener = listener;
    this.nameRepository = nameRepository;
  }

  public void getUserName() {
    nameRepository
        .getName()
        .timeout(2, SECONDS)
        .subscribeOn(Schedulers.io())
        .observeOn(AndroidSchedulers.mainThread())
        .subscribe(
            listener::onUserNameLoaded,
            error -> listener.onGettingUserNameError(error.getMessage()));
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/main/java/com/testing/user/rx/timeout/UserPresenter.java)</center>

В данном случае при тестировании презентера уже нужно протестировать конечный результат подписки, которая получает данные асинхронно. Напишем наивную версию такого теста:

```java
@RunWith(RobolectricTestRunner.class)
public class UserPresenterTest {
  @Rule public final MockitoRule rule = MockitoJUnit.rule();

  @Mock UserPresenter.Listener listener;
  @Mock NameRepository nameRepository;
  UserPresenter presenter;

  @Before
  public void setUp() {
    when(nameRepository.getName()).thenReturn(Observable.just("Sasha"));
    presenter = new UserPresenter(listener, nameRepository);
  }

  @Test
  public void getUserName() {
    presenter.getUserName();
    verifyNoMoreInteractions(listener);
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/test/java/com/testing/user/rx/timeout/withoutrule/UserPresenterTest.java)</center>

В данном тесте презентер не вызовет никакой метод объекта `listener`, так как тест проходит прежде, чем выполняется асинхронное действие. В тестах на эмуляторе Awaitility решает эту проблему. В юнит-тестах тестирование асинхронной природы кода не совсем к месту, а потому в них можно заменить стандартные RxJava `Schedulers` на синхронные. Используем для этого [TestScheduler](http://reactivex.io/RxJava/javadoc/io/reactivex/schedulers/TestScheduler.html), который позволяет произвольно установить время, которое якобы прошло с момента подписки на `Observable`, чтобы протестировать корректную установку таймаута. Как обычно, напишем для этого правило:

```java
public class RxImmediateSchedulerRule implements TestRule {

  private static final TestScheduler TEST_SCHEDULER = new TestScheduler();
  private static final Scheduler IMMEDIATE_SCHEDULER = new Scheduler() {
    @Override
    public Disposable scheduleDirect(Runnable run, long delay, TimeUnit unit) {
      return super.scheduleDirect(run, 0, unit);
    }

    @Override
    public Worker createWorker() {
      return new ExecutorScheduler.ExecutorWorker(Runnable::run);
    }
  };

  @Override
  public Statement apply(Statement base, Description description) {
    return new Statement() {
      @Override
      public void evaluate() throws Throwable {
        RxJavaPlugins.setIoSchedulerHandler(scheduler -> TEST_SCHEDULER);
        RxJavaPlugins.setComputationSchedulerHandler(
            scheduler -> TEST_SCHEDULER);
        RxJavaPlugins.setNewThreadSchedulerHandler(
            scheduler -> TEST_SCHEDULER);
        RxAndroidPlugins.setMainThreadSchedulerHandler(
            scheduler -> IMMEDIATE_SCHEDULER);
        try {
          base.evaluate();
        } finally {
          RxJavaPlugins.reset();
          RxAndroidPlugins.reset();
        }
      }
    };
  }

  public TestScheduler getTestScheduler() {
    return TEST_SCHEDULER;
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/test/java/com/testing/rules/RxImmediateSchedulerRule.java)</center>

Тест презентера с новым правилом будет выглядеть следующим образом:

```java
@RunWith(RobolectricTestRunner.class)
public class UserPresenterTest {
  static final int TIMEOUT_SEC = 2;
  static final String NAME = "Sasha";

  @Rule public final MockitoRule rule = MockitoJUnit.rule();
  @Rule public final RxImmediateSchedulerRule timeoutRule =
      new RxImmediateSchedulerRule();

  @Mock UserPresenter.Listener listener;
  @Mock NameRepository nameRepository;
  PublishSubject<String> nameObservable = PublishSubject.create();
  UserPresenter presenter;

  @Before
  public void setUp() {
    when(nameRepository.getName()).thenReturn(nameObservable.firstOrError());
    presenter = new UserPresenter(listener, nameRepository);
  }

  @Test
  public void getUserName() {
    presenter.getUserName();
    timeoutRule.getTestScheduler().advanceTimeBy(TIMEOUT_SEC - 1, SECONDS);
    nameObservable.onNext(NAME);
    verify(listener).onUserNameLoaded(NAME);
  }

  @Test
  public void getUserName_timeout() {
    presenter.getUserName();
    timeoutRule.getTestScheduler().advanceTimeBy(TIMEOUT_SEC + 1, SECONDS);
    nameObservable.onNext(NAME);
    verify(listener).onGettingUserNameError(any());
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/test/java/com/testing/user/rx/timeout/UserPresenterTest.java)</center>

## Тестирование кода, использующего Dagger 2

Для облегчения работы с графом зависимостей объектов отлично подходит паттерн **Dependency Injection**. [Dagger 2](https://google.github.io/dagger/) — это библиотека, которая поможет в реализации этого паттерна. Поэтому в большинстве наших Android приложений все компоненты предоставляются с помощью Dagger. Об использовании и преимуществах этой библиотеки можно написать отдельную статью, а тут мы рассмотрим, как тестировать приложения, её использующие.

Начнем с того, что практически всегда при использовании Dagger существует `ApplicationComponent`, который предоставляет все основные зависимости приложения, и инициализируется в классе приложения `Application`, который, в свою очередь, имеет метод для получения этого компонента.

```java
@Singleton
@Component(modules = {ContextModule.class})
public interface ApplicationComponent {
  UserComponent createUserComponent();
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/main/java/com/testing/ApplicationComponent.java)</center>

```java
public class MainApplication extends Application {
  private ApplicationComponent component;

  @Override
  public void onCreate() {
    super.onCreate();
    component = DaggerApplicationComponent.builder()
      .contextModule(new ContextModule(this))
      .build();
  }

  public ApplicationComponent getComponent() {
    return component;
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/main/java/com/testing/MainApplication.java)</center>

Также создадим Dagger модуль, который будет предоставлять репозиторий:

```java
@Module
public class UserModule {
  @Provides
  NameRepository provideNameRepository(@Private FileReader fileReader) {
    return new NameRepository(fileReader);
  }

  @Private
  @Provides
  FileReader provideFileReader(@Private File file) {
    return new FileReader(file);
  }

  @Private
  @Provides
  File provideFile(Context context) {
    return new File(context.getFilesDir().getAbsoluteFile()
        + File.separator
        + "test_file");
  }

  @Qualifier
  @Retention(RetentionPolicy.RUNTIME)
  private @interface Private {}
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/main/java/com/testing/user/UserModule.java)</center>

Изменим фрагмент следующим образом, чтобы репозиторий получать с помощью Dagger:

```java
public class UserFragment extends Fragment {
  ...

  @Inject NameRepository nameRepository;

  @Override
  public View onCreateView(
      LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
    ((MainApplication) getActivity().getApplication())
        .getComponent()
        .createUserComponent()
        .injectsUserFragment(this);
    textView = new TextView(getActivity());
    disposable = nameRepository
        .getName()
        .subscribeOn(Schedulers.io())
        .observeOn(AndroidSchedulers.mainThread())
        .subscribe(name -> textView.setText(name));
    return textView;
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/main/java/com/testing/user/dagger/UserFragment.java)</center>

Помимо функциональных тестов UI хорошо иметь и unit-тесты с замоканными зависимостями. Чтобы предоставлять мокированные объекты с помощью Dagger, нужно заменить `ApplicationComponent` на специально созданный компонент для тестов. В первую очередь создадим метод для подмены основного компонента в `Application`:

```java
public void setComponentForTest(ApplicationComponent component) {
  this.component = component;
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/main/java/com/testing/MainApplication.java)</center>

Чтобы не заменять компонент в каждом классе с тестами фрагментов, создадим для этого правило:

```java
class TestDaggerComponentRule<A extends AppCompatActivity> implements TestRule {
  private final ActivityTestRule<A> activityRule;
  private final ApplicationComponent component;

  TestDaggerComponentRule(
      ActivityTestRule<A> activityRule, ApplicationComponent component) {
    this.activityRule = activityRule;
    this.component = component;
  }

  @Override
  public Statement apply(Statement statement, Description description) {
    return new Statement() {
      @Override
      public void evaluate() throws Throwable {
        MainApplication application =
            ((MainApplication) activityRule.getActivity().getApplication());
        ApplicationComponent originalComponent = application.getComponent();
        application.setComponentForTest(component);
        try {
          statement.evaluate();
        } finally {
          application.setComponentForTest(originalComponent);
        }
      }
    };
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/androidTest/java/com/testing/rules/TestDaggerComponentRule.java)</center>

Отметим, что нужно вернуть оригинальный компонент после теста, так как Application создается один для всех тестов и стоит возвращать его к дефолтному состоянию после каждого. Теперь создадим правило, которое будет проводить все подготовки к тестированию фрагмента описанные выше. Перед каждым тестом будет разблокирован экран, запущено активити, открыт нужный нам фрагмент и установлен тестовый Dagger компонент, предоставляющий моки зависимостей.

```java
public class FragmentTestRule<A extends AppCompatActivity, F extends Fragment>
    implements TestRule {
  private ActivityTestRule<A> activityRule;
  private F fragment;
  private RuleChain ruleChain;

  public FragmentTestRule(
      Class<A> activityClass, F fragment, ApplicationComponent component) {
    this.fragment = fragment;
    this.activityRule = new ActivityTestRule<>(activityClass);
    ruleChain = RuleChain
        .outerRule(activityRule)
        .around(new TestDaggerComponentRule<>(activityRule, component))
        .around(new OpenFragmentRule<>(activityRule, fragment));
  }

  ...
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/androidTest/java/com/testing/rules/FragmentTestRule.java)</center>

Установим тестовый компонент в тесте нашего фрагмента:

```java
@RunWith(AndroidJUnit4.class)
public class UserFragmentTest {
  ...

  @Rule
  public final FragmentTestRule<MainActivity, UserFragment> fragmentRule =
      new FragmentTestRule<>(
          MainActivity.class,
          new UserFragment(),
          createTestApplicationComponent());

  private ApplicationComponent createTestApplicationComponent() {
    ApplicationComponent component = mock(ApplicationComponent.class);
    when(component.createUserComponent())
        .thenReturn(DaggerUserFragmentTest_TestUserComponent.create());
    return component;
  }

  @Singleton
  @Component(modules = {TestUserModule.class})
  interface TestUserComponent extends UserComponent {}

  @Module
  static class TestUserModule {
    @Provides
    public NameRepository provideNameRepository() {
      NameRepository nameRepository = mock(NameRepository.class);
      when(nameRepository.getName()).thenReturn(
          Single.fromCallable(() -> "Sasha"));
      return nameRepository;
    }
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/androidTest/java/com/testing/user/dagger/UserFragmentTest.java)</center>

## Тесты запускаемые только для Debug приложения

Бывает, что необходимо добавить логику иди элементы UI, которые нужны разработчикам для более удобного тестирования и должны отображаться только если приложение собирается в режиме debug. Давайте для примера сделаем, чтобы в debug сборке презентер не только передавал имя подписчику, но и выводил его в лог:

```java
class UserPresenter {
  ...

  public void getUserName() {
    nameRepository
        .getName()
        .timeout(TIMEOUT_SEC, SECONDS)
        .subscribeOn(Schedulers.io())
        .observeOn(AndroidSchedulers.mainThread())
        .subscribe(
            name -> {
              listener.onUserNameLoaded(name);
              if (BuildConfig.DEBUG) {
                logger.info(String.format("Name loaded: %s", name));
              }
            }, error -> listener.onGettingUserNameError(error.getMessage()));
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/main/java/com/testing/user/debug/UserPresenter.java)</center>

Эту логику тоже нужно тестировать, но тесты должны запускаться только при соответствующем типе сборки приложения. Напишем правило `DebugTestRule`, которое будет проверять тип сборки приложения и запускать тесты только для дебаг версии:

```java
public class DebugRule implements TestRule {
  @Override
  public Statement apply(Statement base, Description description) {
    return new Statement() {
      @Override
      public void evaluate() throws Throwable {
        if (BuildConfig.DEBUG) {
          base.evaluate();
        }
      }
    };
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/test/java/com/testing/rules/DebugRule.java)</center>

Тест с этим правилом будет выглядеть следующим образом:

```java
class UserPresenterDebugTest {
  ...

  @Rule public final DebugTestsRule debugRule = new DebugTestsRule();

  @Test
  public void userNameLogged() {
    presenter.getUserName();
    timeoutRule.getTestScheduler().triggerActions();
    nameObservable.onNext(NAME);
    verify(logger).info(contains(NAME));
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/testing/src/test/java/com/testing/user/debug/UserPresenterDebugTest.java)</center>

## Заключение

В этой статье мы разобрались с базовыми библиотеками для написания тестов и разработали набор инструментов, основанных на [TestRule](https://developer.android.com/reference/android/support/test/rule/package-summary.html) и предназначенных для решения проблем запуска активити и фрагментов, работой с асинхронным кодом, даггером, отладочным кодом и эмулятором андроида. Применение этих инструментов позволило протестировать неочевидные проблемы, снизить дублирование кода и в целом повысить читабельность тестов.

Полный пример приложения и тестов, использующих все вышеперечисленные библиотеки и утилиты.

```java
public class NameRepository {
  private final FileReader fileReader;

  public NameRepository(FileReader fileReader) {
    this.fileReader = fileReader;
  }

  public Single<String> getName() {
    return Single.create(
        emitter -> {
          Gson gson = new Gson();
          emitter.onSuccess(
              gson.fromJson(fileReader.readFile(), User.class).name);
        });
  }

  private static final class User {
    String name;
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/example/src/main/java/com/example/user/NameRepository.java)</center>

```java
@RunWith(MockitoJUnitRunner.class)
public class NameRepositoryTest {
  @Mock FileReader fileReader;
  NameRepository nameRepository;

  @Before
  public void setUp() throws IOException {
    when(fileReader.readFile()).thenReturn("{name : Sasha}");
    nameRepository = new NameRepository(fileReader);
  }

  @Test
  public void getName() {
    TestObserver<String> observer = nameRepository.getName().test();
    observer.assertValue("Sasha");
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/example/src/test/java/com/example/user/NameRepositoryTest.java)</center>

```java
public class UserPresenter {
  public interface Listener {
    void onUserNameLoaded(String name);
    void onGettingUserNameError(String message);
  }

  private final Listener listener;
  private final NameRepository nameRepository;
  private final Logger logger;
  private Disposable disposable;

  public UserPresenter(
      Listener listener, NameRepository nameRepository, Logger logger) {
    this.listener = listener;
    this.nameRepository = nameRepository;
    this.logger = logger;
  }

  public void getUserName() {
    disposable =
        nameRepository
            .getName()
            .timeout(2, SECONDS)
            .subscribeOn(Schedulers.io())
            .observeOn(AndroidSchedulers.mainThread())
            .subscribe(
                name -> {
                  listener.onUserNameLoaded(name);
                  if (BuildConfig.DEBUG) {
                    logger.info(String.format("Name loaded: %s", name));
                  }
                },
                error -> listener.onGettingUserNameError(error.getMessage()));
  }

  public void stopLoading() {
    disposable.dispose();
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/example/src/main/java/com/example/user/UserPresenter.java)</center>

```java
@RunWith(RobolectricTestRunner.class)
public class UserPresenterTest {
  static final int TIMEOUT_SEC = 2;
  static final String NAME = "Sasha";

  @Rule public final MockitoRule rule = MockitoJUnit.rule();
  @Rule public final RxImmediateSchedulerRule timeoutRule =
      new RxImmediateSchedulerRule();

  @Mock UserPresenter.Listener listener;
  @Mock NameRepository nameRepository;
  @Mock Logger logger;
  PublishSubject<String> nameObservable = PublishSubject.create();
  UserPresenter presenter;

  @Before
  public void setUp() {
    when(nameRepository.getName()).thenReturn(nameObservable.firstOrError());
    presenter = new UserPresenter(listener, nameRepository, logger);
  }

  @Test
  public void getUserName() {
    presenter.getUserName();
    timeoutRule.getTestScheduler().advanceTimeBy(TIMEOUT_SEC - 1, SECONDS);
    nameObservable.onNext(NAME);
    verify(listener).onUserNameLoaded(NAME);
  }

  @Test
  public void getUserName_timeout() {
    presenter.getUserName();
    timeoutRule.getTestScheduler().advanceTimeBy(TIMEOUT_SEC + 1, SECONDS);
    nameObservable.onNext(NAME);
    verify(listener).onGettingUserNameError(any());
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/example/src/test/java/com/example/user/UserPresenterTest.java)</center>

```java
@RunWith(RobolectricTestRunner.class)
public class UserPresenterDebugTest {
  private static final String NAME = "Sasha";
  @Rule public final DebugRule debugRule = new DebugRule();
  @Rule public final MockitoRule mockitoRule = MockitoJUnit.rule();
  @Rule public final RxImmediateSchedulerRule timeoutRule =
      new RxImmediateSchedulerRule();

  @Mock UserPresenter.Listener listener;
  @Mock NameRepository nameRepository;
  @Mock Logger logger;
  PublishSubject<String> nameObservable = PublishSubject.create();
  UserPresenter presenter;

  @Before
  public void setUp() {
    when(nameRepository.getName()).thenReturn(nameObservable.firstOrError());
    presenter = new UserPresenter(listener, nameRepository, logger);
  }

  @Test
  public void userNameLogged() {
    presenter.getUserName();
    timeoutRule.getTestScheduler().triggerActions();
    nameObservable.onNext(NAME);
    verify(logger).info(contains(NAME));
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/example/src/test/java/com/example/user/UserPresenterDebugTest.java)</center>

```java
public class UserFragment extends Fragment implements UserPresenter.Listener {
  private TextView textView;
  @Inject UserPresenter userPresenter;

  @Override
  public View onCreateView(
      LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
    ((MainApplication) getActivity().getApplication())
        .getComponent()
        .createUserComponent(new UserModule(this))
        .injectsUserFragment(this);
    textView = new TextView(getActivity());
    userPresenter.getUserName();
    return textView;
  }

  @Override
  public void onUserNameLoaded(String name) {
    textView.setText(name);
  }

  @Override
  public void onGettingUserNameError(String message) {
    textView.setText(message);
  }

  @Override
  public void onDestroyView() {
    super.onDestroyView();
    userPresenter.stopLoading();
    textView = null;
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/example/src/main/java/com/example/user/UserFragment.java)</center>

```java
@RunWith(AndroidJUnit4.class)
public class UserFragmentIntegrationTest {
  @ClassRule
  public static TestRule asyncRule =
      new FragmentAsyncTestRule<>(MainActivity.class, new UserFragment());

  @Rule
  public final RuleChain rules = RuleChain
      .outerRule(new CreateFileRule(getTestFile(), "{name : Sasha}"))
      .around(new FragmentTestRule<>(MainActivity.class, new UserFragment()));

  @Test
  public void nameDisplayed() {
    await()
        .atMost(5, SECONDS)
        .ignoreExceptions()
        .untilAsserted(
            () ->
                onView(ViewMatchers.withText("Sasha"))
                    .check(matches(isDisplayed())));
  }

  private static File getTestFile() {
    return new File(
        InstrumentationRegistry.getTargetContext()
            .getFilesDir()
            .getAbsoluteFile() + File.separator + "test_file");
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/example/src/androidTest/java/com/example/user/UserFragmentIntegrationTest.java)</center>

```java
@RunWith(AndroidJUnit4.class)
public class UserFragmentTest {

  @ClassRule
  public static TestRule asyncRule =
      new FragmentAsyncTestRule<>(MainActivity.class, new UserFragment());

  @Rule
  public final FragmentTestRule<MainActivity, UserFragment> fragmentRule =
      new FragmentTestRule<>(
          MainActivity.class,
          new UserFragment(),
          createTestApplicationComponent());

  @Test
  public void getNameMethodCalledOnCreate() {
    verify(fragmentRule.getFragment().userPresenter).getUserName();
  }

  private ApplicationComponent createTestApplicationComponent() {
    ApplicationComponent component = mock(ApplicationComponent.class);
    when(component.createUserComponent(any(UserModule.class)))
        .thenReturn(DaggerUserFragmentTest_TestUserComponent.create());
    return component;
  }

  @Singleton
  @Component(modules = {TestUserModule.class})
  interface TestUserComponent extends UserComponent {}

  @Module
  static class TestUserModule {
    @Provides
    public UserPresenter provideUserPresenter() {
      return mock(UserPresenter.class);
    }
  }
}
```
<center>[Полный код](https://github.com/Monnoroch/android-testing/blob/master/example/src/androidTest/java/com/example/user/UserFragmentTest.java)</center>

## Благодарности
Статья написана в коллаборации с [Evgeny Aseev](https://github.com/AseevEIDev). Он же написал значительную часть кода наших библиотек. Спасибо за ревью текста статьи и кода — [Andrei Tarashkevich](https://github.com/andrewtar), [Ruslan Login](https://www.linkedin.com/in/ruslan-login-68bb2676/). Спасибо спонсору проекта, компании [AURA Devices](https://auraband.io).
