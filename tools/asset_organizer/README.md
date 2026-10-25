# FlowSpace 3D Asset Organizer

A standalone local command-line utility to automatically clean, normalize, render, classify, and organize raw/messy 3D models into a structured FlowSpace-ready asset library.

---

## Features

1. **Dual Pipeline Execution**:
   * **Blender Mode (High-Fidelity)**: If Blender path is configured, uses Blender in background mode to import/parse proprietary models (`.blend`, `.fbx`), normalize meshes, and render photorealistic thumbnails.
   * **Pure Python Fallback (Headless)**: If Blender is not available, uses built-in pure Python OBJ and GLTF/GLB readers and a software rasterizer (flat shaded with wireframes) to process meshes without any native graphics engine dependencies.
2. **AI-Powered Visual Classification**:
   * Automatically uses the Gemini API (`gemini-2.5-flash`) to visually inspect rendered thumbnails and classify objects into correct categories (e.g. `living_room`, `bedroom`, `lighting`, etc.) and subcategories (e.g. `sofa`, `chair`, `bed`, `lamp`).
   * Fallback heuristic rules are applied and assets placed in `needs_review/` if the API key is not configured.
3. **Archive Extraction**:
   * Automatically extracts `.zip` and `.rar` files using native Windows shell utility wrappers (`bsdtar`) to search for embedded 3D assets.
4. **Duplicate & Variant Detection**:
   * Automatically groups identical duplicate files by matching their SHA256 hashes.
   * Groups geometric variants (same model with different names/locations) by evaluating vertex counts, face counts, and bounding box dimensions.
5. **Validation and Normalization**:
   * Verifies geometry bounds, corruption, minimum face counts, and format support.
   * Centers the coordinate space in X and Z axes, grounds the base coordinates to Y/Z=0 (floor level), and normalizes scale if the model size is abnormal.

---

## Directory Output Structure

The organizer outputs a clean folder structure inside the designated destination folder:
```
FlowSpace_Library/
    living_room/
    bedroom/
    dining/
    kitchen/
    bathroom/
    office/
    lighting/
    decor/
    plants/
    outdoor/
    architectural/
    needs_review/

manifest.json
duplicates.json
invalid_models.json
review.json
summary.txt
```

---

## Installation & Setup

1. Make sure Python 3.12+ (or 3.14+) is installed.
2. Open a terminal in the `tools/asset_organizer` folder and install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
3. Copy `.env.example` to `.env` and fill out variables:
   ```env
   GEMINI_API_KEY=AIzaSy...
   BLENDER_PATH=C:\Program Files\Blender Foundation\Blender 4.2\blender.exe
   ```

---

## How to Run

Run the tool using Python:
```bash
python organizer.py <path_to_input_folder> <path_to_output_library>
```

### Arguments

* `src_dir`: (Positional) Directory containing messy model files or archives.
* `out_dir`: (Positional) Target output directory for organized library.
* `--api-key`: Provide the Gemini API Key directly via CLI.
* `--blender-path`: Provide the path to `blender.exe` directly via CLI.
* `--force`: Force overwrite output directories.

### Example

```bash
python organizer.py C:\Users\Admin\Documents\furniture2 C:\Users\Admin\Documents\FS_Library --force
```
