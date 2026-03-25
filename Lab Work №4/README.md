# Лабораторная работа №4

## Тема
Проектирование REST API

## Цель работы
Получить опыт проектирования программного интерфейса.

## Выбранный сервис
Для лабораторной работы выбран сервис инспекции и предложений в системе приема бывшей в употреблении электроники.

Сервис отвечает за следующие бизнес-сценарии:
- регистрация устройства клиента;
- проведение инспекции устройства;
- формирование денежного предложения;
- подтверждение предложения клиентом;
- выплата клиенту;
- передача устройства партнеру по переработке или перепродаже;
- управление справочником типов устройств.

---

## Принятые проектные решения

1. **Использование REST-архитектуры.**  
   Для каждого бизнес-объекта выделен отдельный ресурс: `devices`, `inspection`, `offers`, `payments`, `transfers`, `device-types`. Это делает API предсказуемым и понятным.

2. **Версионирование через `/api/v1`.**  
   Версия API включена в URL, чтобы в дальнейшем можно было выпустить новую версию без поломки уже существующих клиентов.

3. **Единый формат данных JSON.**  
   Все запросы и ответы передаются в формате `application/json; charset=utf-8`, что упрощает интеграцию с Postman, браузерными клиентами и внешними системами.

4. **Разделение чтения и изменения состояния.**  
   Для получения данных используются `GET`, для создания сущностей `POST`, для изменения справочника типов устройств `PUT`, для удаления справочника `DELETE`.

5. **Явная идентификация ресурсов через ID.**  
   Все основные сущности используют числовые идентификаторы, например `GET /devices/{id}` или `POST /offers/{id}/confirm`.

6. **Явный жизненный цикл устройства.**  
   Для устройства введены статусы `CREATED`, `INSPECTED`, `OFFER_CONFIRMED`, `PAID`, `TRANSFERRED`. Это позволяет контролировать допустимые переходы между этапами.

7. **Разделение инспекции и денежного предложения.**  
   Инспекция и предложение оформлены как отдельные бизнес-этапы. После инспекции создается отдельная сущность `offer`, которую клиент затем подтверждает.

8. **Валидация входных данных на уровне API.**  
   Сервер проверяет обязательные поля, существование клиента, существование типа устройства, а также корректность текущего состояния сущности перед операцией.

9. **Использование стандартных HTTP-кодов.**  
   Для успешных запросов применяются `200` и `201`, для пустого `OPTIONS` ответа `204`, для ошибок валидации `400`, для отсутствующих ресурсов `404`, для конфликтов бизнес-логики `409`.

10. **Защита справочника типов устройств от неконсистентных изменений.**  
    Удаление типа устройства запрещено, если он уже связан с существующими устройствами. Это предотвращает нарушение ссылочной целостности в модели данных.

11. **Настраиваемый порт запуска.**  
    Сервер запускается параметром `-Port`, что удобно для локальной отладки, Postman и GitHub Actions, особенно если `8080` уже занят другим сервисом.

12. **Автоматизация регрессионной проверки.**  
    Для API добавлен отдельный интеграционный тестовый скрипт и workflow GitHub Actions, чтобы после каждого изменения быстро видеть, что ключевые сценарии не сломаны.

---

## Документация по API

### Общие настройки

- Базовый URL: `http://localhost:8090/api/v1`
- Формат запросов: `application/json; charset=utf-8`
- Формат ответов: `application/json; charset=utf-8`
- Авторизация: не требуется
- Кодировка: UTF-8

### Запуск сервера

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Lab Work №4\src\api-server.ps1" -Port 8090
```

### Основные сущности

**Устройство (`device`)**

```json
{
  "id": 3,
  "clientId": 1,
  "deviceTypeId": 1,
  "brand": "Samsung",
  "model": "Galaxy S21",
  "status": "CREATED",
  "createdAt": "2026-03-26T00:00:00Z"
}
```

**Инспекция (`inspection`)**

```json
{
  "id": 2,
  "deviceId": 3,
  "condition": "GOOD",
  "screenState": "OK",
  "batteryHealth": 91,
  "comment": "Automated inspection",
  "createdAt": "2026-03-26T00:05:00Z"
}
```

**Предложение (`offer`)**

```json
{
  "id": 2,
  "deviceId": 3,
  "amount": 35000,
  "currency": "RUB",
  "status": "CREATED",
  "createdAt": "2026-03-26T00:05:00Z"
}
```

**Платеж (`payment`)**

```json
{
  "id": 1,
  "offerId": 2,
  "amount": 35000,
  "paymentMethod": "CARD",
  "status": "PAID",
  "createdAt": "2026-03-26T00:10:00Z"
}
```

**Передача партнеру (`transfer`)**

```json
{
  "id": 1,
  "deviceId": 3,
  "partnerName": "Recycle Hub",
  "status": "TRANSFERRED",
  "createdAt": "2026-03-26T00:15:00Z"
}
```

**Тип устройства (`deviceType`)**

```json
{
  "id": 3,
  "name": "Premium Tablet",
  "updatedAt": "2026-03-26T00:20:00Z"
}
```

### Жизненный цикл устройства

```text
CREATED -> INSPECTED -> OFFER_CONFIRMED -> PAID -> TRANSFERRED
```

### Общий формат ошибки

```json
{
  "error": {
    "message": "Device not found."
  }
}
```

---

## Endpoint 1. Создание устройства

**Метод:** `POST`  
**URL:** `/devices`

**Назначение:**  
Регистрирует новое устройство в системе и создает заявку на дальнейшую обработку.

**Заголовки:**
- `Content-Type: application/json`

**Тело запроса:**
- `clientId` - идентификатор клиента, число, обязательно;
- `deviceTypeId` - идентификатор типа устройства, число, обязательно;
- `brand` - бренд устройства, строка, обязательно;
- `model` - модель устройства, строка, обязательно.

**Пример запроса:**

```json
{
  "clientId": 1,
  "deviceTypeId": 1,
  "brand": "Samsung",
  "model": "Galaxy S21"
}
```

**Успешный ответ:** `201 Created`

```json
{
  "id": 3,
  "clientId": 1,
  "deviceTypeId": 1,
  "brand": "Samsung",
  "model": "Galaxy S21",
  "status": "CREATED",
  "createdAt": "2026-03-26T00:00:00Z"
}
```

**Возможные ошибки:**
- `400 Bad Request` - отсутствует обязательное поле;
- `404 Not Found` - клиент или тип устройства не найдены.

---

## Endpoint 2. Получение устройства по ID

**Метод:** `GET`  
**URL:** `/devices/{id}`

**Назначение:**  
Возвращает карточку устройства по его идентификатору.

**Параметры пути:**
- `id` - идентификатор устройства.

**Пример запроса:**

```text
GET /api/v1/devices/3
```

**Успешный ответ:** `200 OK`

```json
{
  "id": 3,
  "clientId": 1,
  "deviceTypeId": 1,
  "brand": "Samsung",
  "model": "Galaxy S21",
  "status": "CREATED",
  "createdAt": "2026-03-26T00:00:00Z"
}
```

**Возможные ошибки:**
- `404 Not Found` - устройство не найдено.

---

## Endpoint 3. Проведение инспекции

**Метод:** `POST`  
**URL:** `/inspection`

**Назначение:**  
Фиксирует результаты инспекции устройства и формирует денежное предложение.

**Заголовки:**
- `Content-Type: application/json`

**Тело запроса:**
- `deviceId` - идентификатор устройства, число, обязательно;
- `condition` - состояние устройства (`EXCELLENT`, `GOOD`, `FAIR`, другое), строка, обязательно;
- `screenState` - состояние экрана, строка, обязательно;
- `batteryHealth` - процент состояния аккумулятора, число, обязательно;
- `comment` - комментарий инспектора, строка, необязательно.

**Пример запроса:**

```json
{
  "deviceId": 3,
  "condition": "GOOD",
  "screenState": "OK",
  "batteryHealth": 91,
  "comment": "Automated inspection"
}
```

**Успешный ответ:** `201 Created`

```json
{
  "inspection": {
    "id": 2,
    "deviceId": 3,
    "condition": "GOOD",
    "screenState": "OK",
    "batteryHealth": 91,
    "comment": "Automated inspection",
    "createdAt": "2026-03-26T00:05:00Z"
  },
  "offer": {
    "id": 2,
    "deviceId": 3,
    "amount": 35000,
    "currency": "RUB",
    "status": "CREATED",
    "createdAt": "2026-03-26T00:05:00Z"
  }
}
```

**Возможные ошибки:**
- `400 Bad Request` - отсутствуют обязательные поля;
- `404 Not Found` - устройство не найдено;
- `409 Conflict` - инспекция для устройства уже проведена.

---

## Endpoint 4. Получение предложения по устройству

**Метод:** `GET`  
**URL:** `/offers/{deviceId}`

**Назначение:**  
Возвращает сформированное предложение для указанного устройства.

**Параметры пути:**
- `deviceId` - идентификатор устройства.

**Пример запроса:**

```text
GET /api/v1/offers/3
```

**Успешный ответ:** `200 OK`

```json
{
  "id": 2,
  "deviceId": 3,
  "amount": 35000,
  "currency": "RUB",
  "status": "CREATED",
  "createdAt": "2026-03-26T00:05:00Z"
}
```

**Возможные ошибки:**
- `404 Not Found` - устройство или предложение не найдены.

---

## Endpoint 5. Подтверждение предложения

**Метод:** `POST`  
**URL:** `/offers/{id}/confirm`

**Назначение:**  
Подтверждает предложение, после чего устройство переводится в статус `OFFER_CONFIRMED`.

**Параметры пути:**
- `id` - идентификатор предложения.

**Пример запроса:**

```text
POST /api/v1/offers/2/confirm
```

**Успешный ответ:** `200 OK`

```json
{
  "id": 2,
  "status": "CONFIRMED",
  "confirmedAt": "2026-03-26T00:07:00Z"
}
```

**Возможные ошибки:**
- `404 Not Found` - предложение не найдено;
- `409 Conflict` - предложение уже подтверждено.

---

## Endpoint 6. Выплата клиенту

**Метод:** `POST`  
**URL:** `/payments`

**Назначение:**  
Фиксирует выплату по подтвержденному предложению.

**Заголовки:**
- `Content-Type: application/json`

**Тело запроса:**
- `offerId` - идентификатор предложения, число, обязательно;
- `paymentMethod` - способ выплаты (`CARD`, `CASH`, `TRANSFER`), строка, обязательно.

**Пример запроса:**

```json
{
  "offerId": 2,
  "paymentMethod": "CARD"
}
```

**Успешный ответ:** `201 Created`

```json
{
  "id": 1,
  "offerId": 2,
  "amount": 35000,
  "paymentMethod": "CARD",
  "status": "PAID",
  "createdAt": "2026-03-26T00:10:00Z"
}
```

**Возможные ошибки:**
- `400 Bad Request` - отсутствуют обязательные поля;
- `404 Not Found` - предложение не найдено;
- `409 Conflict` - выплата допустима только для подтвержденного предложения.

---

## Endpoint 7. Передача устройства партнеру

**Метод:** `POST`  
**URL:** `/transfers`

**Назначение:**  
Передает выкупленное устройство партнеру.

**Заголовки:**
- `Content-Type: application/json`

**Тело запроса:**
- `deviceId` - идентификатор устройства, число, обязательно;
- `partnerName` - название партнера, строка, обязательно.

**Пример запроса:**

```json
{
  "deviceId": 3,
  "partnerName": "Recycle Hub"
}
```

**Успешный ответ:** `201 Created`

```json
{
  "id": 1,
  "deviceId": 3,
  "partnerName": "Recycle Hub",
  "status": "TRANSFERRED",
  "createdAt": "2026-03-26T00:15:00Z"
}
```

**Возможные ошибки:**
- `400 Bad Request` - отсутствуют обязательные поля;
- `404 Not Found` - устройство не найдено;
- `409 Conflict` - устройство можно передать только после выплаты.

---

## Endpoint 8. Изменение типа устройства

**Метод:** `PUT`  
**URL:** `/device-types/{id}`

**Назначение:**  
Обновляет наименование типа устройства.

**Параметры пути:**
- `id` - идентификатор типа устройства.

**Заголовки:**
- `Content-Type: application/json`

**Тело запроса:**
- `name` - новое наименование типа устройства, строка, обязательно.

**Пример запроса:**

```json
{
  "name": "Premium Tablet"
}
```

**Успешный ответ:** `200 OK`

```json
{
  "id": 3,
  "name": "Premium Tablet",
  "updatedAt": "2026-03-26T00:20:00Z"
}
```

**Возможные ошибки:**
- `400 Bad Request` - отсутствует поле `name`;
- `404 Not Found` - тип устройства не найден;
- `409 Conflict` - тип устройства с таким именем уже существует.

---

## Endpoint 9. Удаление типа устройства

**Метод:** `DELETE`  
**URL:** `/device-types/{id}`

**Назначение:**  
Удаляет тип устройства из справочника, если он не связан с уже существующими устройствами.

**Параметры пути:**
- `id` - идентификатор типа устройства.

**Пример запроса:**

```text
DELETE /api/v1/device-types/3
```

**Успешный ответ:** `200 OK`

```json
{
  "id": 3,
  "status": "DELETED",
  "deletedAt": "2026-03-26T00:25:00Z"
}
```

**Возможные ошибки:**
- `404 Not Found` - тип устройства не найден;
- `409 Conflict` - тип устройства связан с уже существующими устройствами.

---

## Дополнительные служебные endpoint'ы

В реализации также присутствуют два вспомогательных endpoint'а, которые используются для локальной диагностики и автоматических тестов:

- `GET /health` - проверка доступности сервиса;
- `GET /devices` - получение списка устройств.

---

## Тестирование API

### Подготовка к тестированию в Postman

1. Запустить сервер:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Lab Work №4\src\api-server.ps1" -Port 8090
```

2. В Postman создать переменную окружения:

```text
baseUrl = http://localhost:8090/api/v1
```

3. Для каждого сценария ниже сделать три скриншота:
- вкладки `Params` / `Headers` / `Body`;
- вкладок `Body` и `Headers` ответа;
- вкладки `Test Results`.

4. Код из блоков `Tests` вставляется во вкладку `Tests` соответствующего запроса в Postman.

### Endpoint 1. POST /devices

**Сценарий 1.1. Успешное создание устройства**
- Тестируемое API: `POST {{baseUrl}}/devices`
- Метод: `POST`
- Строка запроса: `{{baseUrl}}/devices`
- Headers: `Content-Type: application/json`
- Body:

```json
{
  "clientId": 1,
  "deviceTypeId": 1,
  "brand": "Samsung",
  "model": "Galaxy S21"
}
```

- Ожидаемый результат: `201 Created`, в ответе `status = CREATED`

```javascript
pm.test("Status code is 201", function () {
    pm.response.to.have.status(201);
});

const json = pm.response.json();

pm.test("Device status is CREATED", function () {
    pm.expect(json.status).to.eql("CREATED");
});

pm.collectionVariables.set("createdDeviceId", json.id);
```

- Скриншоты: запрос, ответ, `Test Results`

**Сценарий 1.2. Ошибка валидации при отсутствии brand**
- Тестируемое API: `POST {{baseUrl}}/devices`
- Метод: `POST`
- Строка запроса: `{{baseUrl}}/devices`
- Headers: `Content-Type: application/json`
- Body:

```json
{
  "clientId": 1,
  "deviceTypeId": 1,
  "model": "Galaxy S21"
}
```

- Ожидаемый результат: `400 Bad Request`, сообщение содержит `brand`

```javascript
pm.test("Status code is 400", function () {
    pm.response.to.have.status(400);
});

const json = pm.response.json();

pm.test("Validation error mentions brand", function () {
    pm.expect(json.error.message).to.include("brand");
});
```

- Скриншоты: запрос, ответ, `Test Results`

### Endpoint 2. GET /devices/{id}

**Сценарий 2.1. Получение существующего устройства**
- Тестируемое API: `GET {{baseUrl}}/devices/{{createdDeviceId}}`
- Метод: `GET`
- Строка запроса: `{{baseUrl}}/devices/{{createdDeviceId}}`
- Headers: без специальных заголовков
- Ожидаемый результат: `200 OK`, возвращается устройство с сохраненным ID

```javascript
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});

const json = pm.response.json();

pm.test("Returned device has expected id", function () {
    pm.expect(json.id).to.eql(Number(pm.collectionVariables.get("createdDeviceId")));
});
```

- Скриншоты: запрос, ответ, `Test Results`

**Сценарий 2.2. Запрос несуществующего устройства**
- Тестируемое API: `GET {{baseUrl}}/devices/999`
- Метод: `GET`
- Строка запроса: `{{baseUrl}}/devices/999`
- Ожидаемый результат: `404 Not Found`

```javascript
pm.test("Status code is 404", function () {
    pm.response.to.have.status(404);
});

const json = pm.response.json();

pm.test("Error message is present", function () {
    pm.expect(json.error.message).to.exist;
});
```

- Скриншоты: запрос, ответ, `Test Results`

### Endpoint 3. POST /inspection

**Сценарий 3.1. Успешная инспекция**
- Тестируемое API: `POST {{baseUrl}}/inspection`
- Метод: `POST`
- Строка запроса: `{{baseUrl}}/inspection`
- Headers: `Content-Type: application/json`
- Body:

```json
{
  "deviceId": {{createdDeviceId}},
  "condition": "GOOD",
  "screenState": "OK",
  "batteryHealth": 91,
  "comment": "Automated inspection"
}
```

- Ожидаемый результат: `201 Created`, создаются `inspection` и `offer`

```javascript
pm.test("Status code is 201", function () {
    pm.response.to.have.status(201);
});

const json = pm.response.json();

pm.test("Inspection and offer are returned", function () {
    pm.expect(json.inspection).to.exist;
    pm.expect(json.offer).to.exist;
});

pm.collectionVariables.set("createdOfferId", json.offer.id);
```

- Скриншоты: запрос, ответ, `Test Results`

**Сценарий 3.2. Повторная инспекция уже обработанного устройства**
- Тестируемое API: `POST {{baseUrl}}/inspection`
- Метод: `POST`
- Строка запроса: `{{baseUrl}}/inspection`
- Headers: `Content-Type: application/json`
- Body:

```json
{
  "deviceId": {{createdDeviceId}},
  "condition": "GOOD",
  "screenState": "OK",
  "batteryHealth": 91
}
```

- Ожидаемый результат: `409 Conflict`

```javascript
pm.test("Status code is 409", function () {
    pm.response.to.have.status(409);
});

const json = pm.response.json();

pm.test("Conflict message is present", function () {
    pm.expect(json.error.message).to.exist;
});
```

- Скриншоты: запрос, ответ, `Test Results`

### Endpoint 4. GET /offers/{deviceId}

**Сценарий 4.1. Получение предложения для существующего устройства**
- Тестируемое API: `GET {{baseUrl}}/offers/{{createdDeviceId}}`
- Метод: `GET`
- Строка запроса: `{{baseUrl}}/offers/{{createdDeviceId}}`
- Ожидаемый результат: `200 OK`, ID предложения совпадает с `createdOfferId`

```javascript
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});

const json = pm.response.json();

pm.test("Returned offer has expected id", function () {
    pm.expect(json.id).to.eql(Number(pm.collectionVariables.get("createdOfferId")));
});
```

- Скриншоты: запрос, ответ, `Test Results`

**Сценарий 4.2. Получение предложения для несуществующего устройства**
- Тестируемое API: `GET {{baseUrl}}/offers/999`
- Метод: `GET`
- Строка запроса: `{{baseUrl}}/offers/999`
- Ожидаемый результат: `404 Not Found`

```javascript
pm.test("Status code is 404", function () {
    pm.response.to.have.status(404);
});

const json = pm.response.json();

pm.test("Error message is present", function () {
    pm.expect(json.error.message).to.exist;
});
```

- Скриншоты: запрос, ответ, `Test Results`

### Endpoint 5. POST /offers/{id}/confirm

**Сценарий 5.1. Успешное подтверждение предложения**
- Тестируемое API: `POST {{baseUrl}}/offers/{{createdOfferId}}/confirm`
- Метод: `POST`
- Строка запроса: `{{baseUrl}}/offers/{{createdOfferId}}/confirm`
- Headers: без специальных заголовков
- Ожидаемый результат: `200 OK`, статус `CONFIRMED`

```javascript
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});

const json = pm.response.json();

pm.test("Offer is confirmed", function () {
    pm.expect(json.status).to.eql("CONFIRMED");
});
```

- Скриншоты: запрос, ответ, `Test Results`

**Сценарий 5.2. Повторное подтверждение предложения**
- Тестируемое API: `POST {{baseUrl}}/offers/{{createdOfferId}}/confirm`
- Метод: `POST`
- Строка запроса: `{{baseUrl}}/offers/{{createdOfferId}}/confirm`
- Ожидаемый результат: `409 Conflict`

```javascript
pm.test("Status code is 409", function () {
    pm.response.to.have.status(409);
});

const json = pm.response.json();

pm.test("Conflict message is present", function () {
    pm.expect(json.error.message).to.exist;
});
```

- Скриншоты: запрос, ответ, `Test Results`

### Endpoint 6. POST /payments

**Сценарий 6.1. Успешная выплата**
- Тестируемое API: `POST {{baseUrl}}/payments`
- Метод: `POST`
- Строка запроса: `{{baseUrl}}/payments`
- Headers: `Content-Type: application/json`
- Body:

```json
{
  "offerId": {{createdOfferId}},
  "paymentMethod": "CARD"
}
```

- Ожидаемый результат: `201 Created`, статус `PAID`

```javascript
pm.test("Status code is 201", function () {
    pm.response.to.have.status(201);
});

const json = pm.response.json();

pm.test("Payment status is PAID", function () {
    pm.expect(json.status).to.eql("PAID");
});
```

- Скриншоты: запрос, ответ, `Test Results`

**Сценарий 6.2. Попытка выплаты по неподтвержденному предложению**
- Тестируемое API: `POST {{baseUrl}}/payments`
- Метод: `POST`
- Строка запроса: `{{baseUrl}}/payments`
- Headers: `Content-Type: application/json`
- Body:

```json
{
  "offerId": 1,
  "paymentMethod": "CARD"
}
```

- Ожидаемый результат: `409 Conflict`

```javascript
pm.test("Status code is 409", function () {
    pm.response.to.have.status(409);
});

const json = pm.response.json();

pm.test("Conflict message is present", function () {
    pm.expect(json.error.message).to.exist;
});
```

- Скриншоты: запрос, ответ, `Test Results`

### Endpoint 7. POST /transfers

**Сценарий 7.1. Успешная передача партнеру**
- Тестируемое API: `POST {{baseUrl}}/transfers`
- Метод: `POST`
- Строка запроса: `{{baseUrl}}/transfers`
- Headers: `Content-Type: application/json`
- Body:

```json
{
  "deviceId": {{createdDeviceId}},
  "partnerName": "Recycle Hub"
}
```

- Ожидаемый результат: `201 Created`, статус `TRANSFERRED`

```javascript
pm.test("Status code is 201", function () {
    pm.response.to.have.status(201);
});

const json = pm.response.json();

pm.test("Transfer status is TRANSFERRED", function () {
    pm.expect(json.status).to.eql("TRANSFERRED");
});
```

- Скриншоты: запрос, ответ, `Test Results`

**Сценарий 7.2. Попытка передачи неоплаченного устройства**
- Тестируемое API: `POST {{baseUrl}}/transfers`
- Метод: `POST`
- Строка запроса: `{{baseUrl}}/transfers`
- Headers: `Content-Type: application/json`
- Body:

```json
{
  "deviceId": 1,
  "partnerName": "Recycle Hub"
}
```

- Ожидаемый результат: `409 Conflict`

```javascript
pm.test("Status code is 409", function () {
    pm.response.to.have.status(409);
});

const json = pm.response.json();

pm.test("Conflict message is present", function () {
    pm.expect(json.error.message).to.exist;
});
```

- Скриншоты: запрос, ответ, `Test Results`

### Endpoint 8. PUT /device-types/{id}

**Сценарий 8.1. Успешное обновление типа устройства**
- Тестируемое API: `PUT {{baseUrl}}/device-types/3`
- Метод: `PUT`
- Строка запроса: `{{baseUrl}}/device-types/3`
- Headers: `Content-Type: application/json`
- Body:

```json
{
  "name": "Premium Tablet"
}
```

- Ожидаемый результат: `200 OK`, имя обновлено

```javascript
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});

const json = pm.response.json();

pm.test("Device type name is updated", function () {
    pm.expect(json.name).to.eql("Premium Tablet");
});
```

- Скриншоты: запрос, ответ, `Test Results`

**Сценарий 8.2. Попытка обновить несуществующий тип устройства**
- Тестируемое API: `PUT {{baseUrl}}/device-types/999`
- Метод: `PUT`
- Строка запроса: `{{baseUrl}}/device-types/999`
- Headers: `Content-Type: application/json`
- Body:

```json
{
  "name": "Unknown Type"
}
```

- Ожидаемый результат: `404 Not Found`

```javascript
pm.test("Status code is 404", function () {
    pm.response.to.have.status(404);
});

const json = pm.response.json();

pm.test("Error message is present", function () {
    pm.expect(json.error.message).to.exist;
});
```

- Скриншоты: запрос, ответ, `Test Results`

### Endpoint 9. DELETE /device-types/{id}

**Сценарий 9.1. Успешное удаление типа устройства**
- Тестируемое API: `DELETE {{baseUrl}}/device-types/3`
- Метод: `DELETE`
- Строка запроса: `{{baseUrl}}/device-types/3`
- Ожидаемый результат: `200 OK`, статус `DELETED`

```javascript
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});

const json = pm.response.json();

pm.test("Device type is deleted", function () {
    pm.expect(json.status).to.eql("DELETED");
});
```

- Скриншоты: запрос, ответ, `Test Results`

**Сценарий 9.2. Попытка удалить связанный тип устройства**
- Тестируемое API: `DELETE {{baseUrl}}/device-types/1`
- Метод: `DELETE`
- Строка запроса: `{{baseUrl}}/device-types/1`
- Ожидаемый результат: `409 Conflict`

```javascript
pm.test("Status code is 409", function () {
    pm.response.to.have.status(409);
});

const json = pm.response.json();

pm.test("Conflict message is present", function () {
    pm.expect(json.error.message).to.exist;
});
```

- Скриншоты: запрос, ответ, `Test Results`

---

## Автоматизированное тестирование

Кроме сценариев для Postman, в проект добавлены автотесты для локального и CI-прогона.

### Локальный запуск автотестов

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Lab Work №4\tests\api-tests.ps1" -Port 18081
```

Что проверяют автотесты:
- успешные сценарии для `POST`, `GET`, `PUT`, `DELETE`;
- негативные сценарии с `400`, `404`, `409`;
- корректный жизненный цикл устройства от создания до передачи партнеру;
- обновление и удаление типов устройств.

### GitHub Actions

Для автоматического запуска тестов добавлен workflow:

```text
.github/workflows/lab-work-4-api-tests.yml
```

Workflow запускается:
- при `push` в ветки `main` и `master`;
- при `pull_request`.

Внутри workflow выполняется интеграционный сценарий:

```powershell
& "./Lab Work №4/tests/api-tests.ps1" -Port 18081
```

---
