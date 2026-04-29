# Blender Python API (bpy) Cheat Sheet for EliteAgent

This document provides essential `bpy` commands for headless 3D automation on macOS (Apple Silicon).

## Core Modules
- `import bpy`: The main entry point.
- `bpy.ops`: Operators (actions like adding objects, rendering).
- `bpy.data`: Access to all data in the blend file (objects, materials, meshes).
- `bpy.context`: Access to the current state (active object, selected items).

## Scene Setup
```python
# Clear all objects in the scene
bpy.ops.wm.read_factory_settings(use_empty=True)

# Set render engine to EEVEE Next (Optimized for Apple Metal)
bpy.context.scene.render.engine = 'BLENDER_EEVEE_NEXT'

# Set resolution
bpy.context.scene.render.resolution_x = 1920
bpy.context.scene.render.resolution_y = 1080
```

## Creating Objects
```python
# Add a Cube
bpy.ops.mesh.primitive_cube_add(size=2, location=(0, 0, 0))

# Add a Sphere
bpy.ops.mesh.primitive_uv_sphere_add(radius=1, location=(3, 0, 0))

# Add a Light (Sun)
bpy.ops.object.light_add(type='SUN', location=(5, 5, 10))
bpy.context.object.data.energy = 10.0

# Add a Camera
bpy.ops.object.camera_add(location=(10, -10, 10), rotation=(1.1, 0, 0.78))
bpy.context.scene.camera = bpy.context.object
```

## Materials and Colors
```python
# Create a material
mat = bpy.data.materials.new(name="BlueMaterial")
mat.use_nodes = True
nodes = mat.node_tree.nodes
principled = nodes.get("Principled BSDF")
principled.inputs[0].default_value = (0, 0, 1, 1) # Blue (RGBA)

# Assign to active object
if bpy.context.active_object.data.materials:
    bpy.context.active_object.data.materials[0] = mat
else:
    bpy.context.active_object.data.materials.append(mat)
```

## Rendering
```python
# Set output path
bpy.context.scene.render.filepath = "/tmp/render.png"

# Render a still image
bpy.ops.render.render(write_still=True)

# Render an animation
bpy.ops.render.render(animation=True)
```

## Apple Metal / Cycles Optimization
```python
# Enable Metal for Cycles on Apple Silicon
if bpy.context.scene.render.engine == 'CYCLES':
    prefs = bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type = 'METAL'
    prefs.get_devices()
    for device in prefs.devices:
        device.use = True
    bpy.context.scene.cycles.device = 'GPU'
```

## Import / Export
```python
# Export to GLTF/GLB
bpy.ops.export_scene.gltf(filepath="/path/to/model.glb")

# Import FBX
bpy.ops.import_scene.fbx(filepath="/path/to/model.fbx")
```

## Troubleshooting
- Use `bpy.ops.wm.read_factory_settings(use_empty=True)` at the start of scripts for a clean state.
- Always check if an object exists: `obj = bpy.data.objects.get("Cube")`.
- Headless mode requires `--background` or `-b` in CLI.
