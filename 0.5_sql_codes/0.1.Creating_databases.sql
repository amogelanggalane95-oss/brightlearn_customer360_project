-- 1. Databases (create only if missing)
IF DB_ID('stg_Customer360') IS NULL CREATE DATABASE stg_Customer360;

IF DB_ID('dwh_Customer360') IS NULL
    CREATE DATABASE dwh_Customer360;
GO