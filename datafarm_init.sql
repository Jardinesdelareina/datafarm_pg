\connect postgres

DROP DATABASE IF EXISTS datafarm;
CREATE DATABASE datafarm;

\connect datafarm

CREATE SCHEMA market;

CREATE EXTENSION IF NOT EXISTS pgcrypto;


--
-- МОДЕЛИ ДАННЫХ
--


-- Валидация email
CREATE DOMAIN market.valid_email AS VARCHAR(128)
    CHECK (VALUE ~* '^[A-Za-z0-9._+%-]+@[A-Za-z0-9.-]+[.][A-Za-z]+$');


-- Тикеры криптовалют
CREATE TABLE market.currencies
(
    symbol VARCHAR(20) PRIMARY KEY
);


-- Рыночные ордера
CREATE TABLE market.tickers
(
    fk_symbol VARCHAR(20) REFERENCES market.currencies(symbol),
    t_time TIMESTAMPTZ NOT NULL,
    t_price FLOAT8 NOT NULL
);


-- Пользователи
CREATE TABLE market.users
(
    email market.valid_email CHECK (
        email ~* '^[A-Za-z0-9._+%-]+@[A-Za-z0-9.-]+[.][A-Za-z]+$'
    ) PRIMARY KEY,
    password VARCHAR(100) NOT NULL
);


-- Портфели пользователей
CREATE TABLE market.portfolios
(
    id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title VARCHAR(128) UNIQUE NOT NULL,
    is_published BOOLEAN DEFAULT TRUE,
    fk_user_email market.valid_email REFERENCES market.users(email)
);


-- Транзакции (покупка/продажа тикера в портфеле)
CREATE TABLE market.transactions
(
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    action_type VARCHAR(4) CHECK (action_type IN ('BUY', 'SELL')) DEFAULT 'BUY',
    quantity REAL NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    fk_portfolio_id INT REFERENCES market.portfolios(id),
    fk_currency_symbol VARCHAR(20) REFERENCES market.currencies(symbol)
);


--
-- ХРАНИМЫЕ ПРОЦЕДУРЫ
--


-- Создание пользователя
CREATE OR REPLACE PROCEDURE market.create_user(
    input_email VARCHAR(128), 
    input_password VARCHAR(100)
    ) AS $$
    INSERT INTO market.users(email, password)
    VALUES(input_email, crypt(input_password, gen_salt('md5')));
$$ LANGUAGE sql;


-- Создание портфеля
CREATE OR REPLACE PROCEDURE market.create_portfolio(
    input_title VARCHAR(200), 
    input_is_published BOOLEAN,
    input_user_email market.valid_email
    ) AS $$
    INSERT INTO market.portfolios(title, is_published, fk_user_email)
    VALUES(input_title, input_is_published, input_user_email);
$$ LANGUAGE sql;


-- Изменение параметров портфеля
CREATE OR REPLACE PROCEDURE market.update_portfolio(
    input_portfolio_id INT,
    input_portfolio_title VARCHAR(200),
    input_is_published BOOLEAN
    ) AS $$
    UPDATE market.portfolios
    SET title = input_portfolio_title,
        is_published = input_is_published
    WHERE id = input_portfolio_id;
$$ LANGUAGE sql;


-- Создание транзакции
CREATE OR REPLACE PROCEDURE market.create_transaction(
    input_action_type VARCHAR(4),
    input_quantity REAL,
    input_portfolio_id INT,
    input_currency_symbol VARCHAR(20)
    ) AS $$
    INSERT INTO market.transactions(action_type, quantity, fk_portfolio_id, fk_currency_symbol)
    VALUES(input_action_type, input_quantity, input_portfolio_id, input_currency_symbol);
$$ LANGUAGE sql;


--
-- ФУНКЦИИ
--


-- Получение последней котировки определенного тикера
--
CREATE OR REPLACE FUNCTION market.get_price(input_symbol VARCHAR(20)) 
RETURNS REAL AS $$
    SELECT t_price AS last_price 
    FROM market.tickers
    WHERE fk_symbol = input_symbol
    ORDER BY t_time DESC 
    LIMIT 1;
$$ LANGUAGE sql VOLATILE;


-- Получение нужной котировки по выбранному тикеру в выбранный момент времени
CREATE OR REPLACE FUNCTION market.get_price_with_time(
    input_symbol VARCHAR(20),
    input_time TIMESTAMPTZ
) RETURNS FLOAT8 AS $$
    SELECT t_price AS current_price
    FROM market.tickers
    WHERE fk_symbol = input_symbol AND t_time = input_time
$$ LANGUAGE sql IMMUTABLE;


-- Вывод списка портфелей определенного пользователя
CREATE OR REPLACE FUNCTION market.get_portfolios(input_user_email market.valid_email) 
RETURNS TABLE(title VARCHAR(200), is_published BOOLEAN) AS $$
BEGIN
    RETURN QUERY SELECT p.title, p.is_published
                FROM market.portfolios p
                WHERE fk_user_email = input_user_email;
END;
$$ LANGUAGE plpgsql STABLE;


-- Расчет объема транзакции в usdt
CREATE OR REPLACE FUNCTION market.get_value_transaction(input_transaction_id UUID) 
RETURNS REAL AS $$
DECLARE qty_transaction REAL;
BEGIN
    WITH qty_currency AS (
        SELECT t.created_at, t.quantity, t.fk_currency_symbol AS curr
        FROM market.transactions t
        WHERE t.id = input_transaction_id
    )
    SELECT quantity * market.get_price_with_time(curr, created_at)
	INTO qty_transaction
    FROM qty_currency;
    RETURN qty_transaction;
END;
$$ LANGUAGE plpgsql IMMUTABLE;


-- Вывод баланса портфеля в usdt
CREATE OR REPLACE FUNCTION market.get_balance_portfolio(input_portfolio_id INT)
RETURNS REAL AS $$
DECLARE total_quantity REAL := 0;
BEGIN
    SELECT SUM(
        CASE WHEN t.action_type = 'BUY' THEN t.quantity ELSE -t.quantity END
    ) * market.get_price(t.fk_currency_symbol)
    INTO total_quantity
    FROM market.transactions t
    WHERE t.fk_portfolio_id = input_portfolio_id
	GROUP BY fk_currency_symbol, t.created_at;
    IF total_quantity < 0 THEN 
        total_quantity = 0;
	END IF;
    RETURN total_quantity;
END;
$$ LANGUAGE plpgsql VOLATILE;


-- Вывод криптовалют, их количества и балансов в портфеле
CREATE OR REPLACE FUNCTION market.get_balance_ticker_portfolio(input_portfolio_id INT) 
RETURNS TABLE(symbol VARCHAR(20), qty_currency REAL, usdt_qty_currency REAL) AS $$
BEGIN
    RETURN QUERY SELECT DISTINCT 
                    fk_currency_symbol AS symbol, 
                    SUM(
                        CASE WHEN t.action_type = 'BUY' THEN t.quantity ELSE -t.quantity END
                    ) AS qty_currency, 
                    SUM(
                        CASE WHEN t.action_type = 'BUY' THEN t.quantity ELSE -t.quantity END
                    ) * market.get_price(fk_currency_symbol) AS usdt_qty_currency
                FROM market.transactions t
                JOIN market.currencies c ON t.fk_currency_symbol = c.symbol
                WHERE t.fk_portfolio_id = input_portfolio_id
                GROUP BY fk_currency_symbol;
END;
$$ LANGUAGE plpgsql VOLATILE;


-- Вывод совокупного баланса пользователя
CREATE OR REPLACE FUNCTION market.get_total_balance_user(input_user_email market.valid_email) 
RETURNS REAL AS $$
DECLARE total_balance REAL := 0;
        portfolio_id INT;
BEGIN
    FOR portfolio_id IN (
        SELECT id 
        FROM market.portfolios 
        WHERE fk_user_email = input_user_email
    ) 
    LOOP
        total_balance := total_balance + market.get_balance_portfolio(portfolio_id);
    END LOOP;
    RETURN total_balance;
END;
$$ LANGUAGE plpgsql VOLATILE;


--
-- ТРИГГЕРЫ
--


-- Запись в лог о добавлении новой транзакции
CREATE OR REPLACE FUNCTION market.alert_new_transaction() RETURNS TRIGGER AS $$
BEGIN
    RAISE NOTICE 'Добавлена новая транзакция';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER alert_new_transaction_trigger
AFTER INSERT ON market.transactions
FOR EACH ROW EXECUTE FUNCTION market.alert_new_transaction();