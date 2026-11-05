import re
from typing import List, Dict

BANCO_POR_RUC: Dict[str, str] = {
    "20100047218": "BCP",
    "20100053455": "IBK",
    "20100130204": "BBVA",
}

MONEDA_POR_CODE: Dict[str, str] = {
    "PEN": "S/.",
    "USD": "$",
    "EUR": "€",
}


def aplicar_banco(datos: List[dict]) -> List[dict]:
    for d in datos:
        ruc = str(d.get("RUC emisor") or "").strip()
        if ruc in BANCO_POR_RUC:
            d["Banco"] = BANCO_POR_RUC[ruc]
    return datos


def aplicar_moneda(datos: List[dict]) -> List[dict]:
    for d in datos:
        code = str(d.get("Moneda") or "").strip().upper()
        if code in MONEDA_POR_CODE:
            d["Moneda"] = MONEDA_POR_CODE[code]
    return datos

def limpiar_importe(datos: List[dict]) -> List[dict]:
    for d in datos:
        importe = str(d.get("Importe total") or "").strip()
        # Quita todo excepto dígitos y puntos
        importe_limpio = re.sub(r"[^\d.]", "", importe)
        # Si hay más de un punto, queda solo el último
        partes = importe_limpio.split(".")
        if len(partes) > 2:
            importe_limpio = "".join(partes[:-1]) + "." + partes[-1]
        d["Importe total"] = float(importe_limpio) if importe_limpio else None
    return datos


def aplicar_todas(datos: List[dict]) -> List[dict]:
    datos = aplicar_banco(datos)
    datos = aplicar_moneda(datos)
    datos = limpiar_importe(datos)
    return datos