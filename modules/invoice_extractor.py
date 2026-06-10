from io import BytesIO
from typing import List, Dict, Any

from azure.ai.formrecognizer import DocumentAnalysisClient
from azure.core.credentials import AzureKeyCredential


CAMPOS = {
    "Archivo"           : None,
    "Banco"             : None,
    "RUC emisor"        : "VendorTaxId",
    "Razón social"      : "VendorName",
    "Tipo documento"    : None,
    "Número documento"  : "InvoiceId",
    "Fecha emisión"     : "InvoiceDate",
    "Moneda"            : "CurrencyCode",
    "Importe total"     : "InvoiceTotal",
    "Glosa"             : None,
}


class InvoiceExtractor:
    def __init__(self, endpoint: str, key: str):
        self.client = DocumentAnalysisClient(
            endpoint=endpoint,
            credential=AzureKeyCredential(key),
        )

    def extraer(self, contenido: BytesIO, nombre_archivo: str) -> List[Dict[str, Any]]:
        poller = self.client.begin_analyze_document("prebuilt-invoice", contenido)
        result = poller.result()

        facturas = []
        for doc in result.documents:
            
            # consola todos los datos
            # print("\n===== CAMPOS EXTRAÍDOS =====")
            # for nombre, campo in doc.fields.items():
            #     print(f"  {nombre}: {campo.value}")
            # print("============================\n")

            def get(campo_api):
                if campo_api is None:
                    return None
                campo = doc.fields.get(campo_api)
                return campo.value if campo else None

            facturas.append({
                "ID"               : None,
                "Archivo"          : nombre_archivo,
                "Banco"            : None,
                "RUC"               : get("VendorTaxId"),
                "Razón social"     : get("VendorAddressRecipient"),
                "Tipo documento"   : None,
                "Número documento" : get("InvoiceId"),
                "Fecha emisión"    : get("InvoiceDate"),
                "Moneda"           : get("Currency"),
                "Importe total"    : get("InvoiceTotal"),
                "Glosa"            : get("description"),
            })
        return facturas