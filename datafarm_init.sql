\connect postgres

DROP DATABASE IF EXISTS datafarm;
CREATE DATABASE datafarm;

\connect datafarm

CREATE SCHEMA market;


--
-- МОДЕЛИ ДАННЫХ
--


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