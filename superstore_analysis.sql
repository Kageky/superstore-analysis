-- ============================================================
-- Пет-проект: анализ продаж Sample/Global Superstore
-- SQL-часть (PostgreSQL). Автор: Антон Харламов
-- Таблицы: orders (51 290 строк), returns (1172 строки), people (13 строк)
-- ============================================================


-- 1. ПРОВЕРКА КАЧЕСТВА ДАННЫХ
-- Проверка дублей заказов в таблице returns (важно перед JOIN,
-- иначе дубли вызовут размножение строк при объединении с orders)
SELECT order_id, count(*)
FROM returns
GROUP BY order_id
HAVING count(*) > 1;
-- Результат: дублей нет.


-- 2. ОБЪЕДИНЕНИЕ ТАБЛИЦ (аналог Merge Queries в Power Query)
-- LEFT JOIN, чтобы сохранить все заказы, даже если по ним нет
-- возврата или менеджера региона.
SELECT *
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
LEFT JOIN people p ON p.region = o.region;
-- Результат: 51 290 строк — совпадает с исходной таблицей orders,
-- значит объединение прошло без размножения строк.


-- 3. ОБРАБОТКА NULL ПОСЛЕ JOIN
-- В returns есть только возвращённые заказы, поэтому после LEFT JOIN
-- у остальных заказов returned = NULL. Заменяем на явное 'No'.
SELECT *,
    CASE WHEN returned IS NULL THEN 'No' ELSE 'Yes' END AS return_flag
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
LEFT JOIN people p ON p.region = o.region;


-- 4. ДИНАМИКА ПРОДАЖ И ПРИБЫЛИ ПО ГОДАМ
-- Business-вопрос: как меняются продажи и прибыль по годам?
SELECT
    sum(sales) AS sum_sales,
    sum(profit) AS sum_profit,
    extract(year FROM o.order_date) AS order_year
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
LEFT JOIN people p ON p.region = o.region
GROUP BY extract(year FROM o.order_date);
-- Итог: устойчивый рост 2011 → 2014 (+18%, +27%, +26% год к году).
-- ВАЖНЫЙ БАГ (найден и исправлен): при первом импорте CSV в этом
-- запросе появлялись лишние 2015/2016 год, а суммы не совпадали
-- с Excel. Причина — формат дат в CSV был dd/MM/yyyy (через слэш),
-- а при импорте в DBeaver стоял неверный формат парсинга (dd.MM.yyyy
-- через точку). Исправлено настройкой формата даты в мастере
-- Data Transfer + переимпортом таблицы orders.


-- 5. ПРИБЫЛЬНОСТЬ ПО КАТЕГОРИЯМ И ПОДКАТЕГОРИЯМ
-- Business-вопрос: какие категории/подкатегории самые прибыльные,
-- а какие в минусе?
SELECT category, sub_category, sum(sales) AS sum_sales, sum(profit) AS sum_profit
FROM orders o
GROUP BY category, sub_category
ORDER BY sum(profit) DESC;
-- Лидеры: Copiers, Phones, Bookcases, Appliances, Chairs.
-- Единственная убыточная подкатегория: Tables (profit = -64 083.39).


-- 6. СКИДКА vs ПРИБЫЛЬ
-- Business-вопрос: как скидка влияет на прибыль?
-- Вариант А — условная агрегация через CASE внутри AVG (один запрос,
-- результат в двух столбцах)
SELECT
    avg(CASE WHEN profit > 0 THEN discount END) AS avg_discount_profit_orders,
    avg(CASE WHEN profit < 0 THEN discount END) AS avg_discount_unprofit_orders
FROM orders;

-- Вариант Б — тот же результат через два отдельных запроса,
-- объединённых UNION (результат в двух строках)
SELECT avg(discount) FROM orders WHERE profit > 0
UNION
SELECT avg(discount) FROM orders WHERE profit < 0;
-- Итог: средняя скидка у прибыльных заказов ~4.3%, у убыточных ~45%.
-- Явная связь: избыточное дисконтирование — главная причина убытков.


-- 7. РЕГИОНЫ (с оконной функцией RANK)
-- Business-вопрос: какой регион даёт больше всего выручки и прибыли?
SELECT region, sum(sales) AS sum_sales, sum(profit) AS sum_profit,
    rank() OVER (ORDER BY sum(profit) DESC) AS rn
FROM orders o
GROUP BY region;


-- 8. СЕГМЕНТЫ КЛИЕНТОВ
-- Business-вопрос: какой сегмент клиентов даёт больше всего
-- выручки и прибыли?
SELECT segment, sum(sales) AS sum_sales, sum(profit) AS sum_profit
FROM orders o
GROUP BY segment
ORDER BY sum(profit) DESC;


-- 9. ДОЛЯ ВОЗВРАТОВ ПО КАТЕГОРИЯМ И ПОДКАТЕГОРИЯМ
-- Business-вопрос: какая доля заказов возвращается и в каких
-- категориях возвратов больше?
-- Важный момент: COUNT(*) / COUNT(*) — целочисленное деление даёт 0,
-- поэтому явно приводим к numeric перед делением.
SELECT category, sub_category,
    count(*) AS count_orders,
    count(CASE WHEN returned = 'Yes' THEN 1 END) AS count_returned_orders,
    (count(CASE WHEN returned = 'Yes' THEN 1 END)::numeric
        / count(*)::numeric) * 100 AS share_order
FROM orders o
LEFT JOIN returns r ON r.order_id = o.order_id
GROUP BY category, sub_category
ORDER BY share_order DESC;
-- Лидеры по доле возвратов: Tables (7.78%), Fasteners (7.31%),
-- Appliances/Accessories (~7.1%) — совпадает с находкой в Excel.


-- 10. ПОДЗАПРОС: товары с прибылью выше среднего
SELECT product_name, profit
FROM orders
WHERE profit > (SELECT avg(profit) FROM orders);
-- Результат: 800+ строк — распределение прибыли скошено вправо
-- (небольшое число очень прибыльных заказов тянет среднее вверх),
-- поэтому выше среднего оказывается меньшинство заказов.
