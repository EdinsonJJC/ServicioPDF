import logging
import os
from datetime import datetime

def get_logger(name: str = "invoice_bot") -> logging.Logger:
    logger = logging.getLogger(name)

    if logger.handlers:
        return logger  # ya fue configurado

    logger.setLevel(logging.INFO)

    # Formato
    fmt = logging.Formatter(
        "%(asctime)s  %(levelname)-8s  %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
    )

    # Handler: consola
    ch = logging.StreamHandler()
    ch.setFormatter(fmt)
    logger.addHandler(ch)

    # Handler: archivo (en la misma carpeta del script)
    log_dir = os.path.dirname(os.path.abspath(__file__))
    log_file = os.path.join(log_dir, f"invoice_bot_{datetime.now():%Y%m%d}.log")
    fh = logging.FileHandler(log_file, encoding="utf-8")
    fh.setFormatter(fmt)
    logger.addHandler(fh)

    return logger