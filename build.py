import os
import argparse
import subprocess
import platform

def main():
    parser = argparse.ArgumentParser(description="Build script for the project.")
    parser.add_argument("--debug", action="store_true", help="Build a debug variant of the project.")
    parser.add_argument("--source-dir", type=str, default="bin", help="Project source directory.")
    parser.add_argument("--output-dir", type=str, default="bin", help="Directory to place built binaries.")
    args = parser.parse_args()

    bin_dir = os.path.abspath(args.output_dir)
    if not os.path.exists(bin_dir):
        os.makedirs(bin_dir)

    source_dir = os.path.abspath(args.source_dir)
    if not os.path.exists(source_dir):
        raise FileNotFoundError(f"Source directory '{source_dir}' does not exist.")
    
    exe_extension = ".exe" if platform.system() == "Windows" else  ""
    exe_name = os.path.basename(source_dir) + exe_extension
    
    subprocess.run(["odin", "build", source_dir, "-out:" + os.path.join(bin_dir, exe_name)] + ["-debug" if args.debug else ""], check=True)

if __name__ == "__main__":
   main()
