#### Общие замечания

Все запросы в данной версии проекта синхронные, не было попытки сделать что-то асинхронное или завязанное на событиях.

#### Бизнес-события


- `Создание аккаунта для попуга.`

    Может осуществлять только админ при работе с сервисом auth. При создании аккаунта Админ посылает синхронный запрос CreateAccount в сервис auth. Сервис auth хеширует входные данные (описание формы носа попуга), генерирует ID, после чего с синхронным запросом на создание счета идет в accounter с запросом CreateAccount. accounter создает счет, отвечает в auth что всё ок, auth отвечает на создание аккаунта что аккаунт создан.

- `Создание задачи`

    Синхронный запрос пользователя в сервис task_tracker. Таск трекер синхронно идет и проверяет авторизацию в auth. Если всё ок, то сервис создает задачу, рандомит попуга, на которого назначена задача, идет в accaunter, списывает средства, и если все ок, сохраняет в базу созданную задачу.

- `Реассайн задач`

    task_tracker вытаскивает айдишники всех попугов из auth, дальше вытаскивает все существующие задачи из базы, переназначает задачи попугам, производя списания средств запросами в accaunter.

- `Задача выполнена`

    task_tracker идет в auth и чекает авторизацию, далее вытаскивает из базы задачу, проверяет что у данного попуга есть такая задача и она ему назначена и еще не выполнена, после чего идет в accaunter, зачисляет ему на счет деньги и удаляет задачу (либо переводит ее в done, пока что механика хранения сделанных задач не совсем ясна, это детали).

- `Посмотреть дашбоард`

    Для любого сервиса это запрос на чтение данных из базы (с авторизацией в auth) по сути с минимальными преобразованиями (к примеру в analitics данные в базе уже лежат в готовом виде, там будет только что-то типа селекта по выбранным датам)

- `Зачисление/списание средств в accounter`

    accounter проверяет что такой аккаунт есть, изменяет баланс. (С точки зрения безопасности и банковских штук конечно выглядит очень глупо, но в контексте данного курса мы не рассматриваем эти вопросы).

- `Дай балансы по счетам`

    accounter вычитывает балансы всех счетов и отдает списком

#### Спорные вопросы и слабые места

- Непонятно кто должен хранить роли попуг. По идее это не должен делать auth, он только про авторизацию. Но тогда получается каждый сервис сам должден проверять что при некотором запросе пользователь имеет роль, подходящую для запроса. Но тогда каждый сервис должен хранить все роли? - некрасиво. Видимо придется навязать auth еще хранить роли, все равно и так на большинство запросов сервисы ходят в auth за авторизацией, заодно и будут проверять соответствие роли.

- Реассайн задач сделана синхронно и в первом приближении будет работать для некоторого числа аккаунтов/задач. Но если рассматривать большое количество данных, то получается что таск трекер должен выгрузить все задачи, по каждой из них сходить и списать баланс со счета вновь назначенного попуга, по возможности сделать это атомарно (иначе есть риск что пока этот процесс с кучей запросов будет продолжаться, где-то произойдет ошибка и у нас будет в базе часть аккаунтов с новыми балансами, в оперативке висит список вновь назначенных задач в таск трекере, и ждет пока все балансы поменяются чтобы этот список обратно в базу загрузить. На всю эту некрасивую схему можно конечно начать придумывать всякие буфферизации (буффер со стороны таск трекера, буффер со стороны аккаунтера и их сложное взаимодействие, чтобы сохранить консистентность данных в случае ошибок, и не записать в базы этих двух сервисов результаты в случае ошибок. Можно также сделать шаг в сторону асинхронного реассайна задач, чтобы инициатору реассайна сразу был ответ что все ок, а процесс реассайна бул плавным и решался по одной задаче. Но тогда всплывает риск того что мы потеряем незареассайненые задачи если процесс реассайна не завершится и гдето что-то упадет, а у нас остались незареассайненные задачи - тут надо тоже или придумывать где хранить этот "стейт" долгим процессом реассайна. Сюда же добавляем тот факт что реассайн могут дернуть разные пользователи в случайное время, и что тут делать - или воспринимать этот запрос как должный быть идемпотентным, типа если процесс реассайна уже идет то будем считать что ничего делать не надо и это ок - либо мы должны прервать процесс предыдущего реассайна (или дождаться его завершения) и начать новый. Сюда же еще вопрос о том, что если кто-то дернет запрос "Посмотреть дашборд задач" то пока прцоесс реассайна не завершен, дашборд должен показывать старую версию дашборда, или если реассайн идет плавно, то и ответы на "посмотреть дашборд" будут уже с частично измененными данными. Сложна!


