# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

import logging
from functools import wraps

MODULE_NAME = "upm"

logger = logging.getLogger(MODULE_NAME)
CALL_TRACER = True


def setup_logger(level: str = "info"):
    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter("[upm] %(levelname)s %(message)s"))
    logger.addHandler(handler)

    if level == "info":
        logger.setLevel(logging.INFO)
    elif level == "debug":
        logger.setLevel(logging.DEBUG)
    elif level == "error":
        logger.setLevel(logging.ERROR)
    elif level == "warning":
        logger.setLevel(logging.WARNING)
    elif level == "critical":
        logger.setLevel(logging.CRITICAL)
    else:
        logger.setLevel(logging.INFO)


def log_entry_exit(func):
    if not CALL_TRACER:
        return func

    @wraps(func)
    def wrapper(*args, **kwargs):
        logger.debug("Entering %s", func.__qualname__)
        try:
            return func(*args, **kwargs)
        finally:
            logger.debug("Exiting %s", func.__qualname__)

    return wrapper
