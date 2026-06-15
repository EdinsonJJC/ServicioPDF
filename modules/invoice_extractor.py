from io import BytesIO
from typing import List, Dict, Any

from azure.ai.formrecognizer import DocumentAnalysisClient
from azure.core.credentials import AzureKeyCredential


class InvoiceExtractor:
    def __init__(self, endpoint: str, key: str):
        self.client = DocumentAnalysisClient(
            endpoint=endpoint,
            credential=AzureKeyCredential(key),
        )

    def extraer(self, contenido: BytesIO, nombre_archivo: str, carpeta: str = "") -> List[Dict[str, Any]]:
        poller = self.client.begin_analyze_document("prebuilt-invoice", contenido)
        result = poller.result()

        facturas = []
        for doc in result.documents:

            # DEBUG — muestra todos los campos extraídos
            #print("\n===== CAMPOS EXTRAÍDOS =====")
            #for nombre, campo in doc.fields.items():
            #    print(f"  {nombre}: {campo.value}")
            #print("============================\n")

            def get(campo_api):
                if campo_api is None:
                    return None
                campo = doc.fields.get(campo_api)
                return campo.value if campo else None

            # Extraer moneda del primer item
            moneda = None
            items = doc.fields.get("Items")
            if items and items.value:
                primer_item = items.value[0].value
                for campo_moneda in ["Amount", "UnitPrice", "Tax"]:
                    field = primer_item.get(campo_moneda)
                    if field and field.value and hasattr(field.value, "code") and field.value.code:
                        moneda = field.value.code
                        break

            facturas.append({
                "ID"               : None,
                "Archivo"          : nombre_archivo,
                "Carpeta"          : carpeta.split("/")[-1],
                "Banco"            : None,
                "RUC emisor"       : get("VendorTaxId"),
                "Razón social"     : get("VendorAddressRecipient"),
                "Tipo documento"   : "FAC",
                "Número documento" : get("InvoiceId"),
                "Fecha emisión"    : get("InvoiceDate"),
                "Moneda"           : moneda,
                "Importe total"    : get("InvoiceTotal"),
                "Glosa"            : None,
                "Check"         : None,
            })
        return facturas