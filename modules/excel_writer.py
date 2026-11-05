from io import BytesIO
from typing import List, Dict, Any
from datetime import datetime
from openpyxl.worksheet.table import Table, TableStyleInfo
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter


HEADER_COLOR  = "4F46E5"
HEADER_FONT   = "FFFFFF"

CAMPOS_MANUALES = {"Check"}


def _estilo_header(ws, headers):
    fill   = PatternFill("solid", fgColor=HEADER_COLOR)
    font   = Font(bold=True, color=HEADER_FONT, size=11)
    border = Border(bottom=Side(style="thin", color="CCCCCC"))
    for col, _ in enumerate(headers, start=1):
        cell = ws.cell(row=1, column=col)
        cell.fill      = fill
        cell.font      = font
        cell.border    = border
        cell.alignment = Alignment(horizontal="center", vertical="center")


def _estilo_manual(ws, headers, n_filas):
    fill   = PatternFill("solid", fgColor="FFF3CD")
    border = Border(
        left=Side(style="thin", color="FFC107"),
        right=Side(style="thin", color="FFC107"),
    )
    for col, header in enumerate(headers, start=1):
        if header in CAMPOS_MANUALES:
            for row in range(2, n_filas + 2):
                cell = ws.cell(row=row, column=col)
                cell.fill   = fill
                cell.border = border


def _autofit(ws):
    for col in ws.columns:
        max_len    = 0
        col_letter = get_column_letter(col[0].column)
        for cell in col:
            try:
                max_len = max(max_len, len(str(cell.value or "")))
            except Exception:
                pass
        ws.column_dimensions[col_letter].width = min(max_len + 4, 50)


def generar_excel(datos: List[Dict[str, Any]], carpeta: str) -> bytes:
    wb = Workbook()
    ws = wb.active
    ws.title = "Facturas"

    if not datos:
        ws.append(["Sin facturas procesadas"])
        buf = BytesIO(); wb.save(buf); return buf.getvalue()

    headers = list(datos[0].keys())
    ws.append(headers)
    _estilo_header(ws, headers)
    ws.freeze_panes = "A2"

    for fila in datos:
        ws.append([
            str(v) if v is not None else ""
            for v in fila.values()
        ])

    _estilo_manual(ws, headers, len(datos))

    # Formato tabla con filtros
    ultima_col = get_column_letter(len(headers))
    ultima_fila = len(datos) + 1
    tabla = Table(
        displayName="Facturas",
        ref=f"A1:{ultima_col}{ultima_fila}"
    )
    tabla.tableStyleInfo = TableStyleInfo(
        name="TableStyleMedium2",
        showFirstColumn=False,
        showLastColumn=False,
        showRowStripes=True,
        showColumnStripes=False,
    )
    ws.add_table(tabla)

    # Hoja resumen
    ws_meta = wb.create_sheet("Resumen")
    ws_meta.append(["Campo",          "Valor"])
    ws_meta.append(["Carpeta",        carpeta])
    ws_meta.append(["Facturas",       len(datos)])
    ws_meta.append(["Generado el",    datetime.now().strftime("%Y-%m-%d %H:%M:%S")])
    ws_meta.append(["Campos manuales","Banco, Tipo documento, Glosa"])

    _autofit(ws)
    _autofit(ws_meta)

    buf = BytesIO()
    wb.save(buf)
    return buf.getvalue()