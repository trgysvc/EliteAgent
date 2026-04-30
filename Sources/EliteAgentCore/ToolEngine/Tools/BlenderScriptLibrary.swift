import Foundation

/// BlenderScriptLibrary: Blender Python API (bpy) için güvenli, parametrik script şablonları.
///
/// Güvenlik Prensibi: Ajan serbest Python kodu yazamaz.
/// Tüm scriptler bu kütüphanedeki statik şablonlardan üretilir.
/// Hiçbir şablon os.system, subprocess, socket veya harici modül kullanmaz.
public struct BlenderScriptLibrary: Sendable {
    
    // MARK: - Sahne Oluşturma
    
    /// Yeni bir sahne oluşturur: nesneler, kamera, ışık ve render ayarları.
    /// - Parameters:
    ///   - engine: Render motoru ('BLENDER_EEVEE_NEXT' veya 'CYCLES')
    ///   - resX: Yatay çözünürlük (piksel)
    ///   - resY: Dikey çözünürlük (piksel)
    ///   - outputPath: Render çıktı dosya yolu (mutlak)
    ///   - objectBlocks: bpy Python komut satırları (örn: "bpy.ops.mesh.primitive_cube_add(size=2)")
    public static func createScene(
        engine: String,
        resX: Int,
        resY: Int,
        outputPath: String,
        objectBlocks: [String]
    ) -> String {
        let defaultObject = "bpy.ops.mesh.primitive_cube_add(size=2, location=(0, 0, 0))"
        let objectsCode = objectBlocks.isEmpty ? defaultObject : objectBlocks.joined(separator: "\n")
        
        return """
        import bpy
        
        # EliteAgent BlenderBridge — Auto-generated Scene Script
        # Temiz Baslangic
        bpy.ops.wm.read_factory_settings(use_empty=True)
        
        # Nesne Olusturma
        \(objectsCode)
        
        # Kamera Ayarlari
        bpy.ops.object.camera_add(location=(7, -6, 5))
        cam = bpy.context.object
        cam.rotation_euler = (1.1, 0, 0.78)
        bpy.context.scene.camera = cam
        
        # Isik Ayarlari
        bpy.ops.object.light_add(type='SUN', location=(5, 5, 10))
        light = bpy.context.object
        light.data.energy = 5.0
        
        # Render Motoru ve Cikti Ayarlari
        scene = bpy.context.scene
        scene.render.engine = '\(engine)'
        scene.render.resolution_x = \(resX)
        scene.render.resolution_y = \(resY)
        scene.render.filepath = r'\(outputPath)'
        
        # Apple Metal GPU Konfigurasyonu (Yalnizca Cycles icin gecerlidir)
        # EEVEE Next, macOS Metal uzerinde dogal (native) calisir, ek ayar gerektirmez.
        if scene.render.engine == 'CYCLES':
            try:
                bpy.context.preferences.addons['cycles'].preferences.compute_device_type = 'METAL'
                bpy.context.preferences.addons['cycles'].preferences.get_devices()
                for d in bpy.context.preferences.addons['cycles'].preferences.devices:
                    d.use = True
                scene.cycles.device = 'GPU'
            except Exception as e:
                print(f'[BLENDER_WARN] Metal GPU setup failed, falling back to CPU: {e}')
        
        # Islemi Baslat
        try:
            bpy.ops.render.render(write_still=True)
            print(f'[BLENDER_OK] Render complete: {scene.render.filepath}')
        except Exception as e:
            print(f'[BLENDER_ERROR] Render failed: {e}')
        """
    }
    
    // MARK: - Format Dönüştürme (Export)
    
    /// Mevcut sahneyi belirli bir formatta dışa aktarır.
    /// - Parameters:
    ///   - exportFormat: Hedef format ('obj', 'fbx', 'gltf', 'stl')
    ///   - outputPath: Çıktı dosya yolu (mutlak)
    public static func exportModel(exportFormat: String, outputPath: String) -> String {
        return """
        import bpy
        
        # EliteAgent BlenderBridge — Auto-generated Export Script
        output_path = r'\(outputPath)'
        fmt = '\(exportFormat)'.lower()
        
        try:
            if fmt == 'obj':
                bpy.ops.wm.obj_export(filepath=output_path)
            elif fmt == 'fbx':
                bpy.ops.export_scene.fbx(filepath=output_path)
            elif fmt in ('gltf', 'glb'):
                bpy.ops.export_scene.gltf(filepath=output_path)
            elif fmt == 'stl':
                bpy.ops.wm.stl_export(filepath=output_path)
            else:
                print(f'[BLENDER_ERROR] Unsupported export format: {fmt}')
            
            print(f'[BLENDER_OK] Export complete: {output_path}')
        except Exception as e:
            print(f'[BLENDER_ERROR] Export failed: {e}')
        """
    }
    
    // MARK: - İçe Aktarma (Import)
    
    /// Harici bir 3D dosyayı (.obj, .fbx, .gltf) sahneye aktarır.
    /// - Parameters:
    ///   - importPath: Kaynak dosya yolu (mutlak)
    ///   - importFormat: Dosya formatı ('obj', 'fbx', 'gltf')
    public static func importModel(importPath: String, importFormat: String) -> String {
        return """
        import bpy
        
        # EliteAgent BlenderBridge — Auto-generated Import Script
        import_path = r'\(importPath)'
        fmt = '\(importFormat)'.lower()
        
        try:
            if fmt == 'obj':
                bpy.ops.wm.obj_import(filepath=import_path)
            elif fmt == 'fbx':
                bpy.ops.import_scene.fbx(filepath=import_path)
            elif fmt in ('gltf', 'glb'):
                bpy.ops.import_scene.gltf(filepath=import_path)
            else:
                print(f'[BLENDER_ERROR] Unsupported import format: {fmt}')
            
            obj_count = len(bpy.data.objects)
            print(f'[BLENDER_OK] Import complete: {import_path} | Objects in scene: {obj_count}')
        except Exception as e:
            print(f'[BLENDER_ERROR] Import failed: {e}')
        """
    }
    
    // MARK: - Sahne Bilgisi
    
    /// Mevcut .blend dosyasındaki nesneleri, materyalleri ve kare aralığını raporlar.
    public static func sceneInfo() -> String {
        return """
        import bpy
        
        # EliteAgent BlenderBridge — Auto-generated Scene Info Script
        scene = bpy.context.scene
        objects = bpy.data.objects
        materials = bpy.data.materials
        
        print(f'[BLENDER_OK] Scene Info:')
        print(f'  Scene Name: {scene.name}')
        print(f'  Objects ({len(objects)}):')
        for obj in objects:
            print(f'    - {obj.name} (Type: {obj.type}, Location: {tuple(round(v, 2) for v in obj.location)})')
        print(f'  Materials ({len(materials)}):')
        for mat in materials:
            print(f'    - {mat.name}')
        print(f'  Frame Range: {scene.frame_start} - {scene.frame_end}')
        print(f'  Render Engine: {scene.render.engine}')
        print(f'  Resolution: {scene.render.resolution_x}x{scene.render.resolution_y}')
        """
    }
    
    // MARK: - Nesne Değiştirme
    
    /// Sahnedeki belirli bir nesneyi değiştirir (konum, döndürme, ölçek).
    /// - Parameters:
    ///   - objectName: Hedef nesne adı
    ///   - location: Yeni konum (x, y, z) — nil ise değişmez
    ///   - rotation: Yeni döndürme euler (x, y, z) — nil ise değişmez
    ///   - scale: Yeni ölçek (x, y, z) — nil ise değişmez
    public static func modifyObject(
        objectName: String,
        location: (Double, Double, Double)?,
        rotation: (Double, Double, Double)?,
        scale: (Double, Double, Double)?
    ) -> String {
        var modifyLines: [String] = []
        if let loc = location {
            modifyLines.append("    obj.location = (\(loc.0), \(loc.1), \(loc.2))")
        }
        if let rot = rotation {
            modifyLines.append("    obj.rotation_euler = (\(rot.0), \(rot.1), \(rot.2))")
        }
        if let sc = scale {
            modifyLines.append("    obj.scale = (\(sc.0), \(sc.1), \(sc.2))")
        }
        let modifications = modifyLines.isEmpty ? "    pass  # No modifications specified" : modifyLines.joined(separator: "\n")
        
        return """
        import bpy
        
        # EliteAgent BlenderBridge — Auto-generated Modify Script
        obj = bpy.data.objects.get('\(objectName)')
        if obj is None:
            print(f'[BLENDER_ERROR] Object not found: \(objectName)')
        else:
        \(modifications)
            print(f'[BLENDER_OK] Modified object: \(objectName)')
            print(f'  Location: {tuple(round(v, 2) for v in obj.location)}')
            print(f'  Rotation: {tuple(round(v, 2) for v in obj.rotation_euler)}')
            print(f'  Scale: {tuple(round(v, 2) for v in obj.scale)}')
        """
    }
    
    // MARK: - Turntable Animasyonu
    
    /// Z ekseninde 360° turntable animasyonu oluşturur ve renderlar.
    /// - Parameters:
    ///   - frameCount: Toplam kare sayısı (varsayılan: 120 = 5 saniye @ 24fps)
    ///   - outputPath: Render çıktı dizini (kare numarası otomatik eklenir)
    ///   - engine: Render motoru
    public static func turntableAnimation(
        frameCount: Int,
        outputPath: String,
        engine: String
    ) -> String {
        return """
        import bpy
        import math
        
        # EliteAgent BlenderBridge — Auto-generated Turntable Animation Script
        scene = bpy.context.scene
        scene.frame_start = 1
        scene.frame_end = \(frameCount)
        scene.render.engine = '\(engine)'
        scene.render.filepath = r'\(outputPath)'
        scene.render.image_settings.file_format = 'PNG'
        
        # Metal GPU (Cycles only)
        if scene.render.engine == 'CYCLES':
            try:
                bpy.context.preferences.addons['cycles'].preferences.compute_device_type = 'METAL'
                bpy.context.preferences.addons['cycles'].preferences.get_devices()
                for d in bpy.context.preferences.addons['cycles'].preferences.devices:
                    d.use = True
                scene.cycles.device = 'GPU'
            except:
                pass
        
        # Kamerayi bul
        cam = scene.camera
        if cam is None:
            print('[BLENDER_ERROR] No camera found in scene')
        else:
            # Empty pivot olustur ve kamerayi parent yap
            bpy.ops.object.empty_add(type='PLAIN_AXES', location=(0, 0, 0))
            pivot = bpy.context.object
            pivot.name = 'TurntablePivot'
            
            cam.parent = pivot
            
            # 360 derece donme animasyonu
            pivot.rotation_euler = (0, 0, 0)
            pivot.keyframe_insert(data_path='rotation_euler', frame=1)
            
            pivot.rotation_euler = (0, 0, math.radians(360))
            pivot.keyframe_insert(data_path='rotation_euler', frame=\(frameCount))
            
            # Lineer interpolasyon (sabit hiz)
            for fc in pivot.animation_data.action.fcurves:
                for kp in fc.keyframe_points:
                    kp.interpolation = 'LINEAR'
            
            try:
                bpy.ops.render.render(animation=True)
                print(f'[BLENDER_OK] Turntable animation rendered: \(frameCount) frames to {scene.render.filepath}')
            except Exception as e:
                print(f'[BLENDER_ERROR] Animation render failed: {e}')
        """
    }
    
    // MARK: - Primitives
    
    /// Sahneye bir mesh nesnesi ekleyen Python komutunu döner.
    public static func addMesh(type: String, size: Double, location: (Double, Double, Double)) -> String {
        let locStr = "(\(location.0), \(location.1), \(location.2))"
        switch type.lowercased() {
        case "plane": return "bpy.ops.mesh.primitive_plane_add(size=\(size), location=\(locStr))"
        case "cube": return "bpy.ops.mesh.primitive_cube_add(size=\(size), location=\(locStr))"
        case "sphere": return "bpy.ops.mesh.primitive_uv_sphere_add(radius=\(size/2), location=\(locStr))"
        case "cylinder": return "bpy.ops.mesh.primitive_cylinder_add(radius=\(size/2), location=\(locStr))"
        case "torus": return "bpy.ops.mesh.primitive_torus_add(location=\(locStr))"
        default: return "bpy.ops.mesh.primitive_cube_add(size=\(size), location=\(locStr))"
        }
    }
    
    /// Sahneye bir ışık nesnesi ekleyen Python komutunu döner.
    public static func addLight(type: String, location: (Double, Double, Double), energy: Double) -> String {
        let locStr = "(\(location.0), \(location.1), \(location.2))"
        let lightType = type.uppercased() // SUN, POINT, SPOT, AREA
        return """
        bpy.ops.object.light_add(type='\(lightType)', location=\(locStr))
        light = bpy.context.object
        light.data.energy = \(energy)
        """
    }
}
