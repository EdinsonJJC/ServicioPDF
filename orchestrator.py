from typing import List, Set
from openpyxl import load_workbook
from config import (
    CLIENT_ID,
    DOC_ENDPOINT, DOC_KEY,
    EXTENSIONES_VALIDAS, EXCEL_OUTPUT_NAME,
    CARPETA_RAIZ,
)
from logger import get_logger
from modules.onedrive_client   import OneDriveClient
from modules.invoice_extractor import InvoiceExtractor
from modules.excel_writer      import generar_excel
from modules.transformer       import aplicar_todas

log = get_logger()


def _leer_procesados(excel_bytes) -> Set[str]:
    if excel_bytes is None:
        return set()
    try:
        wb = load_workbook(excel_bytes)
        ws = wb.active
        headers = [cell.value for cell in ws[1]]
        if "Archivo" not in headers:
            return set()
        col_idx = headers.index("Archivo") + 1
        return {
            ws.cell(row=row, column=col_idx).value
            for row in range(2, ws.max_row + 1)
            if ws.cell(row=row, column=col_idx).value
        }
    except Exception:
        return set()


def _leer_datos_existentes(excel_bytes) -> List[dict]:
    if excel_bytes is None:
        return []
    try:
        excel_bytes.seek(0)
        wb = load_workbook(excel_bytes)
        ws = wb.active
        headers = [cell.value for cell in ws[1]]
        filas = [
            dict(zip(headers, row))
            for row in ws.iter_rows(min_row=2, values_only=True)
            if any(row)
        ]
        for i, fila in enumerate(filas, start=1):
            if "ID" not in fila or not fila["ID"]:
                fila["ID"] = i
        return filas
    except Exception:
        return []


def _normalizar_filas(datos: List[dict]) -> List[dict]:
    if not datos:
        return datos
    otras_keys = list(dict.fromkeys(
        k for d in datos for k in d.keys() if k != "ID"
    ))
    todas_keys = ["ID"] + otras_keys
    return [
        {k: d.get(k, None) for k in todas_keys}
        for d in datos
    ]


class Orchestrator:
    def __init__(self):
        self.onedrive  = OneDriveClient(CLIENT_ID)
        self.extractor = InvoiceExtractor(DOC_ENDPOINT, DOC_KEY)

    def procesar_carpeta(self, carpeta: str) -> int:
        log.info(f"📁  Carpeta: {carpeta}")

        excel_existente  = self.onedrive.descargar_excel(carpeta, EXCEL_OUTPUT_NAME)
        ya_procesados    = _leer_procesados(excel_existente)
        datos_existentes = _leer_datos_existentes(excel_existente)

        if ya_procesados:
            log.info(f"   📋  {len(ya_procesados)} factura(s) en Excel")

        try:
            archivos = self.onedrive.listar_archivos(carpeta, EXTENSIONES_VALIDAS)
        except Exception as e:
            log.error(f"   No se pudo listar la carpeta '{carpeta}': {e}")
            return 0

        nombres_en_carpeta = {a["name"] for a in archivos}

        eliminados = ya_procesados - nombres_en_carpeta
        if eliminados:
            log.info(f"   🗑️  {len(eliminados)} factura(s) eliminada(s) — se quitan del Excel")
            datos_existentes = [
                d for d in datos_existentes
                if d.get("Archivo") not in eliminados
            ]

        archivos_nuevos = [a for a in archivos if a["name"] not in ya_procesados]

        if not archivos_nuevos and not eliminados:
            log.info(f"   ✅  Sin cambios en '{carpeta}'")
            return 0

        log.info(f"   {len(archivos_nuevos)} archivo(s) nuevo(s) encontrado(s)")

        nuevas: List[dict] = []
        errores = 0
        contador_id = len(datos_existentes) + 1

        for archivo in archivos_nuevos:
            nombre = archivo["name"]
            log.info(f"   📄  {nombre}")
            try:
                contenido = self.onedrive.descargar(archivo["id"])
                datos = self.extractor.extraer(contenido, nombre, carpeta)
                datos = aplicar_todas(datos)
                for d in datos:
                    d["ID"] = contador_id
                    contador_id += 1
                nuevas.extend(datos)
                log.info(f"       ✓  {len(datos)} factura(s) extraída(s)")
            except Exception as e:
                log.error(f"       ✗  Error en '{nombre}': {e}")
                errores += 1

        todos = _normalizar_filas(datos_existentes + nuevas)

        if not todos:
            log.warning(f"   Sin datos para guardar en '{carpeta}'")
            return 0

        try:
            excel_bytes = generar_excel(todos, carpeta)
        except Exception as e:
            log.error(f"   Error generando Excel: {e}")
            return 0

        try:
            ok = self.onedrive.subir(carpeta, EXCEL_OUTPUT_NAME, excel_bytes)
            if ok:
                log.info(f"   ✅  Excel sincronizado: {len(todos)} fila(s) — {carpeta}/{EXCEL_OUTPUT_NAME}")
            else:
                log.error(f"   ✗  No se pudo subir el Excel a '{carpeta}'")
        except Exception as e:
            log.error(f"   Error subiendo Excel: {e}")
            return 0

        if errores:
            log.warning(f"   {errores} archivo(s) con error")
        return len(nuevas)

    def generar_excel_maestro(self) -> None:
        log.info("📊  Generando Excel maestro...")

        try:
            subcarpetas = self.onedrive.listar_subcarpetas(CARPETA_RAIZ)
        except Exception as e:
            log.error(f"   Error listando subcarpetas: {e}")
            return

        todos = []
        for carpeta in subcarpetas:
            excel = self.onedrive.descargar_excel(carpeta, EXCEL_OUTPUT_NAME)
            if excel is None:
                continue
            datos = _leer_datos_existentes(excel)
            todos.extend(datos)

        if not todos:
            log.warning("   Sin datos para el Excel maestro")
            return

        todos = _normalizar_filas(todos)

        try:
            excel_bytes = generar_excel(todos, CARPETA_RAIZ)
        except Exception as e:
            log.error(f"   Error generando Excel maestro: {e}")
            return

        try:
            ok = self.onedrive.subir(CARPETA_RAIZ, EXCEL_OUTPUT_NAME, excel_bytes)
            if ok:
                log.info(f"   ✅  Excel maestro: {len(todos)} fila(s) — {CARPETA_RAIZ}/{EXCEL_OUTPUT_NAME}")
            else:
                log.error("   ✗  No se pudo subir el Excel maestro")
        except Exception as e:
            log.error(f"   Error subiendo Excel maestro: {e}")

    def procesar_todo(self, carpetas: List[str]) -> None:
        log.info("=" * 50)
        log.info("🚀  Iniciando extracción de facturas")
        log.info("=" * 50)

        try:
            subcarpetas = self.onedrive.listar_subcarpetas(CARPETA_RAIZ)
            if subcarpetas:
                log.info(f"   {len(subcarpetas)} subcarpeta(s) encontrada(s) en '{CARPETA_RAIZ}'")
                carpetas = carpetas + subcarpetas
        except Exception as e:
            log.warning(f"   No se pudieron listar subcarpetas: {e}")

        total_global = 0
        for carpeta in carpetas:
            total_global += self.procesar_carpeta(carpeta)

        self.generar_excel_maestro()

        log.info("=" * 50)
        log.info(f"✅  Proceso terminado — {total_global} factura(s) nuevas procesadas")
        log.info("=" * 50)