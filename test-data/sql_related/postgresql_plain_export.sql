--
-- PostgreSQL database dump (plain SQL)
-- Generated for Decent Bench import testing
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET search_path = public, pg_catalog;

CREATE TABLE public.customers (
    customer_id integer PRIMARY KEY,
    full_name text NOT NULL,
    email text,
    created_at timestamp without time zone,
    is_active boolean DEFAULT true
);

CREATE TABLE public.orders (
    order_id integer PRIMARY KEY,
    customer_id integer NOT NULL REFERENCES public.customers(customer_id),
    order_date date NOT NULL,
    total_amount numeric(12,2) NOT NULL,
    status text NOT NULL
);

INSERT INTO public.customers (customer_id, full_name, email, created_at, is_active) VALUES
(1, 'Alice Carter', 'alice@example.com', '2025-01-14 09:15:00', true),
(2, 'Bob Smith', 'bob@example.com', '2024-11-02 16:45:00', true),
(3, 'Carla Gomez', 'carla@example.com', '2023-06-28 12:00:00', false);

INSERT INTO public.orders (order_id, customer_id, order_date, total_amount, status) VALUES
(1001, 1, '2026-03-01', 199.95, 'paid'),
(1002, 2, '2026-03-02', 89.50, 'pending'),
(1003, 1, '2026-03-03', 18.25, 'paid'),
(1004, 3, '2026-03-04', 1200.00, 'refunded');

CREATE VIEW public.order_summary AS
SELECT c.full_name,
       COUNT(o.order_id) AS order_count,
       COALESCE(SUM(o.total_amount), 0) AS total_spend
FROM public.customers c
LEFT JOIN public.orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.full_name;

CREATE TABLE public.event_log (
    event_id integer PRIMARY KEY,
    level text NOT NULL,
    message text NOT NULL,
    created_utc timestamp without time zone NOT NULL
);

COPY public.event_log (event_id, level, message, created_utc) FROM stdin;
1	INFO	Login succeeded	2026-03-11 08:15:00
2	WARN	Password retry	2026-03-11 08:16:12
3	ERROR	Import failed	2026-03-11 08:18:03
\.
