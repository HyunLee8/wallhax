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
    """Extracts camera's intrinsics (image width/height, focal point, and principal point) & 4x4 pose matrix from XMP file."""

    tree = ET.parse(xmp_path)
    root = tree.getroot()

    # Namespace directory to use as lookup tags in xmp files
    ns = {
        'rdf': 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',  # rdf means right down forward
        'camera': 'http://wallhax.io/ns/camera/1.0/',
        'pose': 'http://wallhax.io/ns/pose/1.0/',
        'tiff': 'http://ns.adobe.com/tiff/1.0/'
    }

    desc = root.find('.//rdf:Description', ns)
    if desc is None: return None 

    # Parse intrinsics
    intrinsics = {
        "w": float(desc.find('tiff:ImageWidth', ns).text),
        "h": float(desc.find('tiff:ImageLength', ns).text),
        "fl_x": float(desc.find('camera:FocalLengthX', ns).text),
        "fl_y": float(desc.find('camera:FocalLengthY', ns).text),
        "cx": float(desc.find('camera:PrincipalPointX', ns).text),
        "cy": float(desc.find('camera:PrincipalPointY', ns).text)
    }  

    # Parse 4x4 matrix
    matrix_str = desc.find('pose:TransformMatrix', ns).text
    m = [float(x) for x in matrix_str.split()]
    arkit_pose = np.array([
        [m[0], m[1], m[2], m[3]],
        [m[4], m[5], m[6], m[7]],
        [m[8], m[9], m[10], m[11]],
        [m[12], m[13], m[14], m[15]]
    ])

    # Since the AKKit plane's Y-axis is faced up and the Nerfstudio's 
    # Y-axis faced down & the z-axis is reversed, the matrix has to be transformed.
    flip_yz = np.array([
        [1,  0,  0, 0],
        [0, -1,  0, 0],
        [0,  0, -1, 0],
        [0,  0,  0, 1]
    ])
    cv_pose = arkit_pose @ flip_yz

    return intrinsics, cv_pose.tolist()

def main():
    parser = argparse.ArgumentParser(description="Merge WallHax clients into a Nerfstudio dataset.")
    parser.add_argument("--mission", required=True, help="The mission ID folder name in ./data/")
    args = parser.parse_args()

    data_dir = os.path.join("data", args.mission)
    out_dir = os.path.join("processed", args.mission)
    img_out_dir = os.path.join(out_dir, "images")

    if not os.path.exists(data_dir):
        print(f"Error: Mission directory {data_dir} not found.")
        return

    # exist_ok leaves directory unaltered if target directory already exists
    os.makedirs(img_out_dir, exist_ok=True)

    frames_data = []
    global_intrinsics = None  # Assumes every image is taken with same camera lens configuration
    client_dirs = [d for d in os.listdir(data_dir) if os.path.isdir(os.path.join(data_dir, d))]

    print(f"Found {len(client_dirs)} clients in mission {args.mission}. Merging...")

    # Appends client id to frames/images to prevent name collision between people
    for client_id in client_dirs:
        client_path = os.path.join(data_dir, client_id)
        
        for file in sorted(os.listdir(client_path)):
            if file.endswith('.jpg'):
                base = file.replace('.jpg', '')
                jpg_path = os.path.join(client_path, file)
                xmp_path = os.path.join(client_path, f"{base}.xmp")
                
                if os.path.exists(xmp_path):
                    parsed_data = parse_xmp(xmp_path)
                    if not parsed_data: continue
                    
                    intrinsics, transform = parsed_data
                    if not global_intrinsics: global_intrinsics = intrinsics

                    # Format: "clientA_frame_00001.jpg"
                    new_img_name = f"{client_id[:8]}_{file}"
                    new_img_path = os.path.join(img_out_dir, new_img_name)
                    
                    # Copy the image to the new unified folder
                    shutil.copy2(jpg_path, new_img_path)
                    
                    # Append relative path to the images/folder for Nerfstudio
                    frames_data.append({
                        "file_path": f"images/{new_img_name}",
                        "transform_matrix": transform
                    })

    if not frames_data:
        print("Failed to find any valid image/XMP pairs.")
        return

    transforms = {
        "w": global_intrinsics['w'],
        "h": global_intrinsics['h'],
        "fl_x": global_intrinsics['fl_x'],
        "fl_y": global_intrinsics['fl_y'],
        "cx": global_intrinsics['cx'],
        "cy": global_intrinsics['cy'],
        "camera_model": "OPENCV",
        "frames": frames_data,
    }

    json_out = os.path.join(out_dir, 'transforms.json')
    with open(json_out, 'w') as f:
        json.dump(transforms, f, indent=4)

    print(f"\n✅ Success! Merged {len(frames_data)} frames across {len(client_dirs)} clients.")

    print(f"Dataset ready at: {out_dir}")
    print(f"\nTo train, run:\n ns-train splatfacto --data {out_dir}")

if __name__ == "__main__":
    main()
