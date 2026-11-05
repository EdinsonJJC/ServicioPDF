import os
import msal
import requests
from io import BytesIO
from typing import List, Dict, Optional

GRAPH_BASE  = "https://graph.microsoft.com/v1.0"
SCOPES      = ["Files.ReadWrite", "Files.ReadWrite.All"]
CACHE_FILE  = "token_cache.bin"


class OneDriveClient:
    def __init__(self, client_id: str):
        self.client_id = client_id
        self._token: str | None = None

        self._cache = msal.SerializableTokenCache()
        if os.path.exists(CACHE_FILE):
            self._cache.deserialize(open(CACHE_FILE, "r").read())

        self._app = msal.PublicClientApplication(
            self.client_id,
            authority="https://login.microsoftonline.com/common",
            token_cache=self._cache
        )

    def _save_cache(self):
        if self._cache.has_state_changed:
            with open(CACHE_FILE, "w") as f:
                f.write(self._cache.serialize())

    def _get_token(self) -> str:
        accounts = self._app.get_accounts()
        if accounts:
            result = self._app.acquire_token_silent(SCOPES, account=accounts[0])
            if result and "access_token" in result:
                self._save_cache()
                return result["access_token"]

        result = self._app.acquire_token_interactive(
            scopes=SCOPES,
            prompt="select_account"
        )
        if "access_token" not in result:
            raise RuntimeError(f"Error de autenticación: {result.get('error_description')}")
        self._save_cache()
        return result["access_token"]

    def _headers(self) -> Dict:
        if not self._token:
            self._token = self._get_token()
        return {"Authorization": f"Bearer {self._token}"}

    def quien_soy(self):
        url  = f"{GRAPH_BASE}/me"
        resp = requests.get(url, headers=self._headers())
        data = resp.json()
        print(f"DEBUG cuenta: {data.get('userPrincipalName')} — {data.get('displayName')}")

    def listar_archivos(self, carpeta: str, extensiones: tuple) -> List[Dict]:
        url  = f"{GRAPH_BASE}/me/drive/root:/{carpeta}:/children"
        resp = requests.get(url, headers=self._headers())
        resp.raise_for_status()
        items = resp.json().get("value", [])
        return [
            item for item in items
            if item.get("file") and item["name"].lower().endswith(extensiones)
        ]

    def descargar(self, item_id: str) -> BytesIO:
        url  = f"{GRAPH_BASE}/me/drive/items/{item_id}/content"
        resp = requests.get(url, headers=self._headers(), allow_redirects=True)
        resp.raise_for_status()
        return BytesIO(resp.content)

    def descargar_excel(self, carpeta: str, nombre: str) -> Optional[BytesIO]:
        url  = f"{GRAPH_BASE}/me/drive/root:/{carpeta}/{nombre}:/content"
        resp = requests.get(url, headers=self._headers())
        if resp.status_code == 404:
            return None
        resp.raise_for_status()
        return BytesIO(resp.content)

    def subir(self, carpeta: str, nombre: str, contenido: bytes) -> bool:
        url = f"{GRAPH_BASE}/me/drive/root:/{carpeta}/{nombre}:/content"
        headers = {
            **self._headers(),
            "Content-Type": (
                "application/vnd.openxmlformats-officedocument"
                ".spreadsheetml.sheet"
            ),
        }
        resp = requests.put(url, headers=headers, data=contenido)
        return resp.status_code in (200, 201)

    def listar_subcarpetas(self, carpeta: str) -> List[str]:
        url  = f"{GRAPH_BASE}/me/drive/root:/{carpeta}:/children"
        resp = requests.get(url, headers=self._headers())
        resp.raise_for_status()
        items = resp.json().get("value", [])
        return [
            f"{carpeta}/{item['name']}"
            for item in items
            if "folder" in item
        ]

    def archivo_existe(self, carpeta: str, nombre: str) -> bool:
        url  = f"{GRAPH_BASE}/me/drive/root:/{carpeta}/{nombre}:/content"
        resp = requests.head(url, headers=self._headers())
        return resp.status_code == 200