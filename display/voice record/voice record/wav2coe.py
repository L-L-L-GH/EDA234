#----------------------------------------------------------------------------
#-- Author:  Hanyin Gu
#----------------------------------------------------------------------------

import os


tasks = [
    ("Date8.raw",        "date_voice.coe"),
    ("Temperature8.raw", "temp_voice.coe"),
    ("Time8.raw",        "time_voice.coe")
]

def bin_to_coe(input_file, output_file):
    print(f"processing: {input_file} ...")
    
    if not os.path.exists(input_file):
        print(f" error, cannot find file: {input_file}")
        return

    try:
        with open(input_file, 'rb') as f:
            data = f.read()
            
        with open(output_file, 'w') as f:
            f.write("memory_initialization_radix=10;\n")
            f.write("memory_initialization_vector=\n")
            str_data = [str(b) for b in data]
            f.write(",\n".join(str_data))
            f.write(";")
            
        print(f"   success, new file: {output_file} (size: {len(data)} bytes)")

    except Exception as e:
        print(f"   error: {e}")


print("--- start transforming ---")
for input_name, output_name in tasks:
    bin_to_coe(input_name, output_name)
print("--- compeleted ---")