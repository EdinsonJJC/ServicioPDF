import os, sys, datetime
from pathlib import Path
import pyodbc
from dotenv import load_dotenv

PREFIJO = "DWADR"   # servidor donde se ejecuta el SQL (113)
MAX_FILAS_LOG = 20  # filas del resultado que se guardan en el log

BASE = Path(__file__).resolve().parent
load_dotenv(BASE / ".env", override=True)
v = lambda k: os.getenv(f"{PREFIJO}_{k}")


def log(msg):
    linea = f"{datetime.datetime.now():%Y-%m-%d %H:%M:%S}  {msg}"
    print(linea)
    with open(BASE / "log.txt", "a", encoding="utf-8") as f:
        f.write(linea + "\n")


def conectar():
    host = f"{v('SERVER')},{v('PORT')}" if v("PORT") else f"{v('SERVER')}\\{v('INSTANCE')}"
    driver = [d for d in pyodbc.drivers() if "SQL Server" in d][-1]
    auth = f"UID={v('USER')};PWD={v('PASSWORD')};" if v("USER") else "Trusted_Connection=yes;"
    return pyodbc.connect(
        f"DRIVER={{{driver}}};SERVER={host};DATABASE={v('DB')};"
        f"{auth}Encrypt=yes;TrustServerCertificate=yes;",
        timeout=15, autocommit=True)


def ejecutar(nombre):
    archivo = BASE / "sql" / nombre
    log(f"Inicio {nombre}")
    sql = archivo.read_text(encoding="utf-8")

    conn = conectar()
    try:
        cur = conn.cursor()
        cur.execute(sql)
        while True:
            if cur.description:
                log("   " + " | ".join(c[0] for c in cur.description))
                for fila in cur.fetchmany(MAX_FILAS_LOG):
                    log("   " + " | ".join(str(x) for x in fila))
            if not cur.nextset():
                break
    finally:
        conn.close()
    log(f"OK {nombre}")


if __name__ == "__main__":
    ejecutar(sys.argv[1] if len(sys.argv) > 1 else "prueba.sql")