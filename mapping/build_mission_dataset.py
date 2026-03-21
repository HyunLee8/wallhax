"""
Converts xmp files into JSON file (transforms.json). 
"""

import os
import json
import shutil
import xml.etree.ElementTree as ET
import argparse
import numpy as np

def parse_xmp(xmp_path):
    """Extracts camera's intrinsics (image width/height, focal point, and optical center) & 4x4 pose matrix from XMP file."""

    tree = ET.parse(xmp_path)
    root = tree.getroot()
