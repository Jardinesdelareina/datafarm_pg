\connect postgres

DROP DATABASE IF EXISTS datafarm;
CREATE DATABASE datafarm;

\connect datafarm

DROP SCHEMA market CASCADE;
CREATE SCHEMA market;


--
-- МОДЕЛИ ДАННЫХ
--


-- Тикеры криптовалют
CREATE TABLE market.currencies
(
    symbol VARCHAR(10) PRIMARY KEY
);


-- Рыночные ордера
CREATE TABLE market.deals
(
    fk_symbol VARCHAR(10) REFERENCES market.currencies(symbol),
    d_time TIMESTAMPTZ NOT NULL,
    d_side VARCHAR(4) CHECK (d_side IN ('BUY', 'SELL')) NOT NULL,
    d_price REAL NOT NULL,
    d_qty REAL NOT NULL
);