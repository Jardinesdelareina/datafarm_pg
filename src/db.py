import environs
import psycopg2

env = environs.Env()
env.read_env('.env')

DB_USER = env('DB_USER')
DB_PASS = env('DB_PASS')
DB_HOST = env('DB_HOST')
DB_NAME = env('DB_NAME')

try:
    connection = psycopg2.connect(
        host=DB_HOST,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASS
    )
    cursor = connection.cursor()
except (Exception, psycopg2.Error) as error:
    print("[ERROR] Ошибка подключения к базе данных:", error)