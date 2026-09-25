"""
CDSS Fine-Tuning, Data Re-balancing (SMOTE), Focal Loss & Anatomical Gating Engine
Fixes Dominant Class Bias and Anatomical Disconnect (Ocular vs Respiratory) in CDSS.
"""

from train_cdss_model import train_and_verify_cdss_model

if __name__ == "__main__":
    import sys
    import os
    # Ensure root is in path
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../"))
    if root not in sys.path:
        sys.path.insert(0, root)
    from train_cdss_model import train_and_verify_cdss_model
    train_and_verify_cdss_model()
