import time, datetime
from pathlib import Path
from ejecutar import ejecutar, log

BASE = Path(__file__).resolve().parent
DIAS = {"LUN": 0, "MAR": 1, "MIE": 2, "JUE": 3, "VIE": 4, "SAB": 5, "DOM": 6}
avisadas = set()


def leer_programacion():
    tareas = []
    texto = (BASE / "programacion.txt").read_text(encoding="utf-8")
    for n, linea in enumerate(texto.splitlines(), 1):
        linea = linea.split("#")[0].strip()
        if not linea:
            continue
        try:
            archivo, dias, horas = [p.strip() for p in linea.split("|")]
            dias = dias.upper().replace("É", "E").replace("Á", "A")
            dias = set(range(7)) if dias == "TODOS" else {DIAS[d.strip()] for d in dias.split(",")}
            horas = {datetime.datetime.strptime(h.strip(), "%H:%M").strftime("%H:%M")
                     for h in horas.split(",")}
            tareas.append((archivo, dias, horas))
        except Exception:
            if linea not in avisadas:
                avisadas.add(linea)
                log(f"Línea {n} inválida en programacion.txt: {linea}")
    return tareas


log("Programador iniciado")
ultimo_minuto = None
while True:
    ahora = datetime.datetime.now()
    minuto = ahora.strftime("%Y-%m-%d %H:%M")
    if minuto != ultimo_minuto:
        ultimo_minuto = minuto
        try:
            for archivo, dias, horas in leer_programacion():
                if ahora.weekday() in dias and ahora.strftime("%H:%M") in horas:
                    try:
                        ejecutar(archivo)
                    except Exception as e:
                        log(f"ERROR en {archivo}: {e}")
        except Exception as e:
            log(f"ERROR leyendo programacion.txt: {e}")
    time.sleep(20)