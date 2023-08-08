#### Task tracker

- Таск-трекер должен быть отдельным дашбордом и доступен всем сотрудникам компании UberPopug Inc.

    `Actor:` Account, `Command:` GetTasksInfo, `Data:` Task, `Event:` ?

- Авторизация в таск-трекере должна выполняться через общий сервис авторизации UberPopug Inc (у нас там инновационная система авторизации на основе формы клюва).

    `Actor:` Account, `Command:` Authorize, `Data:` ?, `Event:` Account.Authorized

- В таск-трекере должны быть только задачи. Проектов, скоупов и спринтов нет, потому что они не умещаются в голове попуга. Новые таски может создавать кто угодно (администратор, начальник, разработчик, менеджер и любая другая роль). У задачи должны быть описание, статус (выполнена или нет) и рандомно выбранный попуг (кроме менеджера и администратора), на которого заассайнена задача.

    `Actor:` Account (Role), `Command:` CreateTask, `Data:` Task/Description/Status/Assignee, `Event:` Task.Created

- Менеджеры или администраторы должны иметь кнопку «заассайнить задачи», которая возьмёт все открытые задачи и рандомно заассайнит каждую на любого из сотрудников (кроме менеджера и администратора) . Не успел закрыть задачу до реассайна — сорян, делай следующую.

    `Actor:` Account (Role), `Command:` ReassignTasks, `Data:` ?Tasks? (Mutate), `Event:` ReasignTasks.Started (Done?)

- Каждый сотрудник должен иметь возможность видеть в отдельном месте список заассайненных на него задач и отметить задачу выполненной.

    `Actor:` Account (Role), `Command:` DoneTask, `Data:` ?Tasks? (Mutate), `Event:` Task.Done

#### Аккаунтинг: кто сколько денег заработал

- Аккаунтинг должен быть в отдельном дашборде и доступным только для администраторов и бухгалтеров.
a) у обычных попугов доступ к аккаунтингу тоже должен быть. Но только к информации о собственных счетах (аудит лог + текущий баланс). У админов и бухгалтеров должен быть доступ к общей статистике по деньгами заработанным (количество заработанных топ-менеджментом за сегодня денег + статистика по дням).

    `Actor:` Account (Role), `Command:` GetAccountInfo/GetAccountsInfo, `Data:` Accounts, `Event:` ?

- Авторизация в дешборде аккаунтинга должна выполняться через общий сервис аутентификации UberPopug Inc.

    `Actor:` Account (Role), `Command:` Authorize, `Data:` ?, `Event:` Account.Authorized

- У каждого из сотрудников должен быть свой счёт, который показывает, сколько за сегодня он получил денег. У счёта должен быть аудитлог того, за что были списаны или начислены деньги, с подробным описанием каждой из задач.

    `Actor:` ?, `Command:` ?, `Data:` ? `Event:` ?

- деньги списываются сразу после ассайна на сотрудника, а начисляются после выполнения задачи.

    `Actor:` ReassignTasks event, `Command:` TaskFee, `Data:` Account.Balance, `Event:` Account.BalanceChanged

- отрицательный баланс переносится на следующий день. Единственный способ его погасить - закрыть достаточное количество задач в течение дня.

    `Actor:` Nextday event, `Command:` CheckBalance, `Data:` Account.Balance, `Event:` ?

В конце дня необходимо:
a) считать сколько денег сотрудник получил за рабочий день
b) отправлять на почту сумму выплаты. После выплаты баланса (в конце дня) он должен обнуляться, и в аудитлоге всех операций аккаунтинга должно быть отображено, что была выплачена сумма.

    `Actor:` Nextday event, `Command:` CheckBalance/SendSalary/WriteAudit, `Data:` Account.Balance/Auditlog, `Event:` Account.SalarySent

#### Аналитика

- Аналитика — это отдельный дашборд, доступный только админам.

    `Actor:` Account (Role), `Command:` GetStats, `Data:` Statistics, `Event:` ?

- Нужно указывать, сколько заработал топ-менеджмент за сегодня и сколько попугов ушло в минус.

    `Actor:` AccountBalanceChanged event, `Command:` ChangeStats, `Data:` Statistics.Topmsalary, `Event:` Statistics.Changed

- Нужно показывать самую дорогую задачу за день, неделю или месяц.

    `Actor:` Task.Done event, `Command:` CheckStatsMaxprice, `Data:` Statistics.Maxprice, `Event:` Statistics.Changed