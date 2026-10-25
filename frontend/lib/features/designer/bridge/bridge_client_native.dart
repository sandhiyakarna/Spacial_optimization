import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'bridge_client.dart';

BridgeClient createBridgeClient() => AndroidBridgeClient();

typedef NativeBridgeClient = AndroidBridgeClient;

class AndroidBridgeClient implements BridgeClient {
  final StreamController<String> _messageController = StreamController<String>.broadcast();
  late final WebViewController _controller;
  bool _initialized = false;

  @override
  Stream<String> get onMessage => _messageController.stream;

  @override
  void initialization() {
    initialize();
  }

  @override
  void send(String message) {
    sendJson(message);
  }

  @override
  Stream<String> receive() {
    return onMessage;
  }

  @override
  void initialize() {
    if (_initialized) return;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: (JavaScriptMessage message) {
          if (!_messageController.isClosed) {
            _messageController.add(message.message);
          }
        },
      )
      ..loadHtmlString(_sandboxHtml);
    _initialized = true;
  }

  @override
  void sendJson(String payload) {
    if (!_initialized) return;
    final bytes = Uri.encodeComponent(payload);
    _controller.runJavaScript("window.RendererAdapterInstance?.receiveCommand(JSON.parse(decodeURIComponent('$bytes')));");
  }

  @override
  Widget buildViewport(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }

  @override
  void dispose() {
    try {
      _controller.loadHtmlString('<html></html>');
    } catch (_) {}
    _messageController.close();
  }

  static const String _sandboxHtml = r'''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>GPU Viewport Sandbox</title>
  <style>
    html, body {
      margin: 0;
      padding: 0;
      width: 100%;
      height: 100%;
      overflow: hidden;
      background-color: transparent;
      color: #ffffff;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    }
    #viewport-container {
      width: 100%;
      height: 100%;
      user-select: none;
      background-color: transparent;
    }
    .status-text {
      position: absolute;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      font-size: 14px;
      color: #888888;
      pointer-events: none;
    }
  </style>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/three@0.128.0/examples/js/controls/OrbitControls.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/three@0.128.0/examples/js/controls/TransformControls.js"></script>
</head>
<body>
  <div id="viewport-container">
    <div class="status-text" id="status-label">Initializing 3D Viewport...</div>
  </div>

  <div id="fps-counter" style="
    position: absolute;
    top: 10px;
    right: 10px;
    background: rgba(15, 23, 42, 0.7);
    backdrop-filter: blur(8px);
    border: 1px solid rgba(255, 255, 255, 0.1);
    border-radius: 8px;
    padding: 10px 14px;
    font-family: monospace;
    font-size: 11px;
    color: #e2e8f0;
    pointer-events: none;
    z-index: 1000;
    box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
    display: none;
    min-width: 140px;
  ">
    <div style="font-weight: bold; color: #3b82f6; margin-bottom: 6px; font-size: 12px; letter-spacing: 0.05em;">GPU VIEWPORT</div>
    <div style="margin-bottom: 2px;">FPS: <span id="val-fps" style="color: #10b981; font-weight: bold;">0</span></div>
    <div style="margin-bottom: 2px;">Draw Calls: <span id="val-drawcalls" style="color: #f59e0b;">0</span></div>
    <div style="margin-bottom: 2px;">Triangles: <span id="val-triangles">0</span></div>
    <div style="margin-bottom: 2px;">Geometries: <span id="val-geometries">0</span></div>
    <div style="margin-bottom: 2px;">Textures: <span id="val-textures">0</span></div>
    <div>Models: <span id="val-models">0</span> <span id="val-culling" style="color: #94a3b8; font-size: 10px;">(0 culled)</span></div>
  </div>

  <script>
    // --- WORLD COORDINATE SYSTEM: 1 THREE.JS WORLD UNIT = 1 CENTIMETER ---
    function cmToWorld(cm) { return cm; }
    function worldToCm(world) { return world; }

    let scene, camera, renderer, controls, gridHelper, roomGroup, furnitureGroup, lightHelpersGroup, overlayGroup, transformControls;
    let activeLights = new Map();
    let roomMinX = -300.0, roomMaxX = 300.0, roomMinZ = -225.0, roomMaxZ = 225.0;
    let roomHeight = 280.0;
    let shadowsEnabled = true;
    let currentVisualizationMode = 'normal';
    const raycaster = new THREE.Raycaster();
    const mouse = new THREE.Vector2();
    let isGizmoInteracting = false;

    let selectedIds = new Set();
    let selectedBoxHelper = null;
    let hoveredModel = null;
    let hoverBoxHelper = null;
    let isUpdatingTransform = false;

    const textureCache = new Map();
    const throttleTimers = {};
    let lastFpsTime = performance.now();
    let frames = 0;
    let currentFps = 0;
    let showFpsOverlay = false;

    function sendEventThrottled(type, payload, delay = 33) {
      const now = Date.now();
      const key = `${type}_${payload.id}`;
      const lastTime = throttleTimers[key] || 0;
      if (now - lastTime >= delay) {
        window.RendererAdapterInstance.sendEvent(type, payload);
        throttleTimers[key] = now;
      }
    }

    function checkCollisions(activeObj) {
      if (!activeObj) return false;
      const activeBox = new THREE.Box3().setFromObject(activeObj);
      for (const [id, inst] of activeModels.entries()) {
        if (inst === activeObj) continue;
        const otherBox = new THREE.Box3().setFromObject(inst);
        if (activeBox.intersectsBox(otherBox)) return true;
      }
      let wallCollision = false;
      if (roomGroup) {
        roomGroup.traverse((child) => {
          if (child.isMesh && child.userData.isWall) {
            const wallBox = new THREE.Box3().setFromObject(child);
            if (activeBox.intersectsBox(wallBox)) wallCollision = true;
          }
        });
      }
      return wallCollision;
    }

    function logRenderBounds(assetId, assetName, obj) {
      if (!obj) return;
      const box = new THREE.Box3().setFromObject(obj);
      const size = new THREE.Vector3();
      box.getSize(size);
      console.log(`[RENDER BOUNDS] Asset: ${assetName} (${assetId}) Dimensions: ${size.x.toFixed(1)} x ${size.y.toFixed(1)} x ${size.z.toFixed(1)} cm`);
    }

    function initThree() {
      const container = document.getElementById('viewport-container');
      const statusLabel = document.getElementById('status-label');

      scene = new THREE.Scene();
      scene.background = null;

      camera = new THREE.PerspectiveCamera(45, container.clientWidth / container.clientHeight, 1.0, 50000.0);
      camera.position.set(600, 500, 600);

      renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
      renderer.setSize(container.clientWidth, container.clientHeight);
      renderer.setPixelRatio(window.devicePixelRatio);
      renderer.shadowMap.enabled = true;
      renderer.shadowMap.type = THREE.PCFSoftShadowMap;
      renderer.setClearColor(0x000000, 0);

      renderer.physicallyCorrectLights = true;
      renderer.toneMapping = THREE.ACESFilmicToneMapping;
      renderer.toneMappingExposure = 1.1;

      container.appendChild(renderer.domElement);

      controls = new THREE.OrbitControls(camera, renderer.domElement);
      controls.enableDamping = true;
      controls.dampingFactor = 0.05;
      controls.maxPolarAngle = Math.PI / 2 - 0.01;
      controls.minDistance = 20.0;
      controls.maxDistance = 10000.0;

      activeLights = new Map();
      shadowsEnabled = true;

      const hemiLight = new THREE.HemisphereLight(0xffffff, 0x334155, 0.65);
      scene.add(hemiLight);
      activeLights.set('ambient_global', hemiLight);

      const directionalLight = new THREE.DirectionalLight(0xfffdf5, 0.9);
      directionalLight.position.set(500, 800, 500);
      directionalLight.castShadow = true;
      setupShadowProperties(directionalLight);
      scene.add(directionalLight);
      activeLights.set('sun_global', directionalLight);

      gridHelper = new THREE.GridHelper(2000, 40, 0x475569, 0x334155);
      gridHelper.position.y = -0.1;
      scene.add(gridHelper);

      roomGroup = new THREE.Group();
      scene.add(roomGroup);

      furnitureGroup = new THREE.Group();
      scene.add(furnitureGroup);

      lightHelpersGroup = new THREE.Group();
      scene.add(lightHelpersGroup);

      overlayGroup = new THREE.Group();
      scene.add(overlayGroup);

      transformControls = new THREE.TransformControls(camera, renderer.domElement);
      transformControls.addEventListener('dragging-changed', function (event) {
        controls.enabled = !event.value;
        if (!event.value) {
          const obj = transformControls.object;
          if (!obj) return;
          let instanceId = null;
          for (const [id, inst] of activeModels.entries()) {
            if (inst === obj) {
              instanceId = id;
              break;
            }
          }
          if (instanceId) {
            window.RendererAdapterInstance.sendEvent("OBJECT_MOVED", {
              id: instanceId,
              x: obj.position.x,
              y: obj.position.y,
              z: obj.position.z
            });
          }
        }
      });
      scene.add(transformControls);

      setupInteractions(renderer.domElement);

      if (statusLabel) statusLabel.style.display = 'none';

      window.addEventListener('resize', onWindowResize, false);
      animate();

      window.RendererAdapterInstance.sendEvent("READY", { status: "ready" });
    }

    function fitCameraToRoom() {
      if (!roomGroup) return;
      const box = new THREE.Box3().setFromObject(roomGroup);
      let center = new THREE.Vector3();
      let size = new THREE.Vector3();

      if (box.isEmpty() || !isFinite(box.min.x)) {
        const rLen = roomMaxX - roomMinX || 600.0;
        const rWid = roomMaxZ - roomMinZ || 450.0;
        center.set(roomMinX + rLen / 2, roomHeight / 2, roomMinZ + rWid / 2);
        size.set(rLen, roomHeight, rWid);
      } else {
        box.getCenter(center);
        box.getSize(size);
      }

      const maxDim = Math.max(size.x, size.y, size.z, 300.0);
      const dist = maxDim * 1.5;

      camera.position.set(
        center.x + dist * 0.75,
        center.y + dist * 0.85,
        center.z + dist * 0.75
      );
      camera.lookAt(center);

      if (controls) {
        controls.target.copy(center);
        controls.minDistance = maxDim * 0.1;
        controls.maxDistance = maxDim * 10.0;
        controls.update();
      }
    }

    function setCameraView(preset) {
      const box = new THREE.Box3().setFromObject(roomGroup);
      let center = new THREE.Vector3();
      let size = new THREE.Vector3();

      if (box.isEmpty() || !isFinite(box.min.x)) {
        const rLen = roomMaxX - roomMinX || 600.0;
        const rWid = roomMaxZ - roomMinZ || 450.0;
        center.set(roomMinX + rLen / 2, roomHeight / 2, roomMinZ + rWid / 2);
        size.set(rLen, roomHeight, rWid);
      } else {
        box.getCenter(center);
        box.getSize(size);
      }

      const maxDim = Math.max(size.x, size.y, size.z, 300.0);
      const dist = maxDim * 1.6;

      switch ((preset || '').toUpperCase()) {
        case 'TOP':
          camera.position.set(center.x, center.y + dist * 1.6, center.z + 0.1);
          break;
        case 'FRONT':
          camera.position.set(center.x, center.y, center.z + dist * 1.4);
          break;
        case 'LEFT':
          camera.position.set(center.x - dist * 1.4, center.y, center.z);
          break;
        case 'RIGHT':
          camera.position.set(center.x + dist * 1.4, center.y, center.z);
          break;
        case 'WALKTHROUGH':
          camera.position.set(center.x, 160.0, center.z);
          break;
        case 'ISOMETRIC':
        case 'RESET':
        default:
          camera.position.set(
            center.x + dist * 0.75,
            center.y + dist * 0.85,
            center.z + dist * 0.75
          );
          break;
      }

      camera.lookAt(center);
      if (controls) {
        controls.target.copy(center);
        controls.update();
      }
    }

    function setupInteractions(domElement) {
      domElement.addEventListener('pointerdown', (e) => {
        const rect = domElement.getBoundingClientRect();
        mouse.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
        mouse.y = -((e.clientY - rect.top) / rect.height) * 2 + 1;
      });

      domElement.addEventListener('pointerup', (e) => {
        if (isGizmoInteracting) return;
        const rect = domElement.getBoundingClientRect();
        const upX = ((e.clientX - rect.left) / rect.width) * 2 - 1;
        const upY = -((e.clientY - rect.top) / rect.height) * 2 + 1;

        if (Math.hypot(upX - mouse.x, upY - mouse.y) > 0.05) return;

        raycaster.setFromCamera(mouse, camera);
        const intersects = raycaster.intersectObjects(furnitureGroup.children, true);

        if (intersects.length > 0) {
          let topGroup = intersects[0].object;
          while (topGroup.parent && topGroup.parent !== furnitureGroup) {
            topGroup = topGroup.parent;
          }
          for (const [id, inst] of activeModels.entries()) {
            if (inst === topGroup) {
              selectModelInstance(id);
              window.RendererAdapterInstance.sendEvent("OBJECT_SELECTED", { id: id });
              return;
            }
          }
        } else {
          selectModelInstance(null);
          window.RendererAdapterInstance.sendEvent("OBJECT_DESELECTED", {});
        }
      });
    }

    function setupShadowProperties(light) {
      if (!light) return;
      light.shadow.mapSize.width = 2048;
      light.shadow.mapSize.height = 2048;
      light.shadow.camera.near = 10;
      light.shadow.camera.far = 5000;
      const d = 1500;
      light.shadow.camera.left = -d;
      light.shadow.camera.right = d;
      light.shadow.camera.top = d;
      light.shadow.camera.bottom = -d;
      light.shadow.bias = -0.0005;
    }

    function animate() {
      requestAnimationFrame(animate);
      if (controls) controls.update();
      renderer.render(scene, camera);
      frames++;
      const now = performance.now();
      if (now >= lastFpsTime + 1000) {
        currentFps = Math.round((frames * 1000) / (now - lastFpsTime));
        frames = 0;
        lastFpsTime = now;
      }
    }

    function onWindowResize() {
      const container = document.getElementById('viewport-container');
      if (!container || !renderer || !camera) return;
      camera.aspect = container.clientWidth / container.clientHeight;
      camera.updateProjectionMatrix();
      renderer.setSize(container.clientWidth, container.clientHeight);
    }

    function clearGroup(group) {
      if (!group) return;
      while (group.children.length > 0) {
        const obj = group.children[0];
        group.remove(obj);
        if (obj.geometry) obj.geometry.dispose();
        if (obj.material) {
          if (Array.isArray(obj.material)) obj.material.forEach(m => m.dispose());
          else obj.material.dispose();
        }
      }
    }

    function loadRoom(payload) {
      if (!payload) return;
      clearGroup(roomGroup);

      const walls = payload.walls || [];
      const openings = payload.openings || [];
      const openDoorIds = payload.openDoorIds || [];
      roomHeight = payload.height || 280.0;

      let roomLen = 600.0;
      let roomWid = 450.0;
      let minX = -300.0, maxX = 300.0;
      let minZ = -225.0, maxZ = 225.0;

      if (walls.length > 0) {
        minX = Infinity; maxX = -Infinity;
        minZ = Infinity; maxZ = -Infinity;
        walls.forEach(w => {
          minX = Math.min(minX, w.x1, w.x2);
          maxX = Math.max(maxX, w.x1, w.x2);
          minZ = Math.min(minZ, w.y1, w.y2);
          maxZ = Math.max(maxZ, w.y1, w.y2);
        });
        roomLen = maxX - minX;
        roomWid = maxZ - minZ;
      }

      roomMinX = minX; roomMaxX = maxX;
      roomMinZ = minZ; roomMaxZ = maxZ;

      const cx = minX + roomLen / 2;
      const cz = minZ + roomWid / 2;

      let floorColorHex = payload.floorMaterialColor || "#e5e7eb";
      if (!payload.floorMaterialColor) {
        if (payload.floorMaterialType === 'wood') floorColorHex = '#a16207';
        else if (payload.floorMaterialType === 'carpet') floorColorHex = '#94a3b8';
      }

      const floorMat = new THREE.MeshStandardMaterial({
        color: new THREE.Color(floorColorHex),
        roughness: payload.floorRoughness !== undefined ? Number(payload.floorRoughness) : 0.5,
        metalness: payload.floorMetallic !== undefined ? Number(payload.floorMetallic) : 0.0,
      });

      const floorGeo = new THREE.BoxGeometry(roomLen, 4.0, roomWid);
      const floorMesh = new THREE.Mesh(floorGeo, floorMat);
      floorMesh.position.set(cx, -2.0, cz);
      floorMesh.receiveShadow = true;
      roomGroup.add(floorMesh);

      if (payload.showCeiling) {
        const ceilingColorHex = payload.ceilingMaterialColor || "#ffffff";
        const ceilingMat = new THREE.MeshStandardMaterial({ color: new THREE.Color(ceilingColorHex), roughness: 0.8 });
        const ceilingGeo = new THREE.BoxGeometry(roomLen, 4.0, roomWid);
        const ceilingMesh = new THREE.Mesh(ceilingGeo, ceilingMat);
        ceilingMesh.position.set(cx, roomHeight + 2.0, cz);
        roomGroup.add(ceilingMesh);
      }

      const wallColorHex = payload.wallMaterialColor || "#f3f4f6";
      const wallRoughness = payload.wallRoughness !== undefined ? Number(payload.wallRoughness) : 0.5;

      walls.forEach(w => {
        const dx = w.x2 - w.x1;
        const dz = w.y2 - w.y1;
        const len = Math.sqrt(dx*dx + dz*dz);
        if (len === 0) return;

        const wallCenterX = w.x1 + dx / 2;
        const wallCenterZ = w.y1 + dz / 2;
        const angle = Math.atan2(dz, dx);
        const isExterior = (w.thickness > 12.0);
        const color = isExterior ? '#374151' : wallColorHex;
        const isFacingCamera = (wallCenterZ > cz + roomWid * 0.1 || wallCenterX > cx + roomLen * 0.1);

        const wallMat = new THREE.MeshStandardMaterial({
          color: new THREE.Color(color),
          roughness: wallRoughness,
          metalness: 0.0,
          transparent: isFacingCamera,
          opacity: isFacingCamera ? 0.35 : 1.0,
        });

        const effectiveHeight = (isFacingCamera && payload.fullWalls !== true) ? Math.min(roomHeight, 60.0) : roomHeight;

        const wallGeo = new THREE.BoxGeometry(len, effectiveHeight, w.thickness || 15.0);
        const wallMesh = new THREE.Mesh(wallGeo, wallMat);
        wallMesh.rotation.y = -angle;
        wallMesh.position.set(wallCenterX, effectiveHeight / 2, wallCenterZ);
        wallMesh.castShadow = !isFacingCamera;
        wallMesh.receiveShadow = true;
        wallMesh.userData.isWall = true;
        roomGroup.add(wallMesh);
      });

      openings.forEach(op => {
        if (op.type === 'door') {
          const doorMat = new THREE.MeshStandardMaterial({ color: new THREE.Color('#5c4033'), roughness: 0.7 });
          const doorGeo = new THREE.BoxGeometry(op.width || 90.0, 210.0, 6.0);
          const doorMesh = new THREE.Mesh(doorGeo, doorMat);
          const isOpen = openDoorIds.includes(op.id);
          const doorAngle = isOpen ? op.angle + Math.PI / 2 : op.angle;
          doorMesh.rotation.y = -doorAngle;
          doorMesh.position.set(op.x, 105.0, op.y);
          doorMesh.castShadow = true;
          doorMesh.receiveShadow = true;
          roomGroup.add(doorMesh);
        } else {
          const windowMat = new THREE.MeshStandardMaterial({ color: new THREE.Color('#93c5fd'), roughness: 0.1, transparent: true, opacity: 0.55 });
          const windowGeo = new THREE.BoxGeometry(op.width || 120.0, 140.0, 8.0);
          const windowMesh = new THREE.Mesh(windowGeo, windowMat);
          windowMesh.rotation.y = -op.angle;
          windowMesh.position.set(op.x, 170.0, op.y);
          windowMesh.castShadow = true;
          windowMesh.receiveShadow = true;
          roomGroup.add(windowMesh);
        }
      });

      fitCameraToRoom();
    }

    const modelCache = new Map();
    const activeModels = new Map();

    const GlbParser = {
      parse(arrayBuffer) {
        const dataView = new DataView(arrayBuffer);
        const magic = dataView.getUint32(0, true);
        if (magic !== 0x46546C67) throw new Error("Invalid GLB magic header");
        const jsonChunkLen = dataView.getUint32(12, true);
        const jsonText = new TextDecoder().decode(new Uint8Array(arrayBuffer, 20, jsonChunkLen));
        const gltf = JSON.parse(jsonText);
        const binChunkStart = 20 + jsonChunkLen;
        let bin = null;
        if (binChunkStart < arrayBuffer.byteLength) {
          const binChunkLen = dataView.getUint32(binChunkStart, true);
          bin = new Uint8Array(arrayBuffer, binChunkStart + 8, binChunkLen);
        }
        return { gltf, bin };
      }
    };

    function getAccessorData(gltf, bin, accessorIdx) {
      const accessor = gltf.accessors[accessorIdx];
      const bufferView = gltf.bufferViews[accessor.bufferView];
      const offset = (bufferView.byteOffset || 0) + (accessor.byteOffset || 0);
      const count = accessor.count;
      let TypedArrayCtor = Float32Array;
      if (accessor.componentType === 5121) TypedArrayCtor = Uint8Array;
      else if (accessor.componentType === 5123) TypedArrayCtor = Uint16Array;
      else if (accessor.componentType === 5125) TypedArrayCtor = Uint32Array;
      const numComponents = accessor.type === 'VEC3' ? 3 : (accessor.type === 'VEC2' ? 2 : (accessor.type === 'VEC4' ? 4 : 1));
      return new TypedArrayCtor(bin.buffer, bin.byteOffset + offset, count * numComponents);
    }

    function buildThreeMesh(gltf, bin) {
      const group = new THREE.Group();
      const threeMeshes = [];

      (gltf.meshes || []).forEach(meshDef => {
        const meshGroup = new THREE.Group();
        meshDef.primitives.forEach(prim => {
          const geometry = new THREE.BufferGeometry();
          if (prim.attributes.POSITION !== undefined) {
            const posData = getAccessorData(gltf, bin, prim.attributes.POSITION);
            geometry.setAttribute('position', new THREE.BufferAttribute(new Float32Array(posData), 3));
          }
          if (prim.attributes.NORMAL !== undefined) {
            const normData = getAccessorData(gltf, bin, prim.attributes.NORMAL);
            geometry.setAttribute('normal', new THREE.BufferAttribute(new Float32Array(normData), 3));
          }
          if (prim.attributes.TEXCOORD_0 !== undefined) {
            const uvData = getAccessorData(gltf, bin, prim.attributes.TEXCOORD_0);
            geometry.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(uvData), 2));
          }
          if (prim.indices !== undefined) {
            const indexData = getAccessorData(gltf, bin, prim.indices);
            geometry.setIndex(new THREE.BufferAttribute(indexData, 1));
          }
          const material = new THREE.MeshStandardMaterial({ color: 0xcccccc, roughness: 0.6, metalness: 0.1 });
          const mesh = new THREE.Mesh(geometry, material);
          meshGroup.add(mesh);
        });
        threeMeshes.push(meshGroup);
      });

      threeMeshes.forEach(meshGroup => group.add(meshGroup));
      return group;
    }

    async function loadGlbModel(url) {
      if (modelCache.has(url)) return modelCache.get(url);
      const promise = (async () => {
        const response = await fetch(url);
        if (!response.ok) throw new Error(`Failed to fetch model: ${response.statusText}`);
        const arrayBuffer = await response.arrayBuffer();
        const { gltf, bin } = GlbParser.parse(arrayBuffer);
        return buildThreeMesh(gltf, bin);
      })();
      modelCache.set(url, promise);
      return promise;
    }

    let currentSelectedId = null;

    function selectModelInstance(id) {
      selectedIds.clear();
      if (id) selectedIds.add(id);
      currentSelectedId = id;

      if (selectedBoxHelper) {
        scene.remove(selectedBoxHelper);
        selectedBoxHelper = null;
      }

      if (!id) {
        if (transformControls) transformControls.detach();
        return;
      }

      const instance = activeModels.get(id);
      if (instance) {
        selectedBoxHelper = new THREE.BoxHelper(instance, 0x3b82f6);
        scene.add(selectedBoxHelper);
        if (checkCollisions(instance)) selectedBoxHelper.material.color.setHex(0xef4444);
        if (transformControls) {
          transformControls.attach(instance);
          transformControls.setMode('translate');
        }
      }
    }

    function updateObjectMaterial(object, payload) {
      if (!object || !payload) return;
      const color = payload.color || payload.baseColor || payload.materialColor;
      if (!color) return;
      object.traverse((child) => {
        if (child.isMesh && child.material) {
          const materials = Array.isArray(child.material) ? child.material : [child.material];
          materials.forEach((m) => {
            m.color.set(color);
            m.needsUpdate = true;
          });
        }
      });
    }

    function updateVisualizationOverlay(mode) {
      currentVisualizationMode = mode || 'normal';
      clearGroup(overlayGroup);

      if (currentVisualizationMode === 'collision') {
        for (const [id, inst] of activeModels.entries()) {
          if (checkCollisions(inst)) {
            const box = new THREE.Box3().setFromObject(inst);
            const size = new THREE.Vector3(); box.getSize(size);
            const center = new THREE.Vector3(); box.getCenter(center);
            const redGeo = new THREE.BoxGeometry(size.x + 4, size.y + 4, size.z + 4);
            const redMat = new THREE.MeshBasicMaterial({ color: 0xef4444, wireframe: true });
            const redMesh = new THREE.Mesh(redGeo, redMat);
            redMesh.position.copy(center);
            overlayGroup.add(redMesh);
          }
        }
      } else if (currentVisualizationMode === 'ergonomic') {
        for (const [id, inst] of activeModels.entries()) {
          const box = new THREE.Box3().setFromObject(inst);
          const size = new THREE.Vector3(); box.getSize(size);
          const center = new THREE.Vector3(); box.getCenter(center);
          const yelGeo = new THREE.BoxGeometry(size.x + 60, size.y, size.z + 60);
          const yelMat = new THREE.MeshBasicMaterial({ color: 0xf59e0b, transparent: true, opacity: 0.2, wireframe: true });
          const yelMesh = new THREE.Mesh(yelGeo, yelMat);
          yelMesh.position.copy(center);
          overlayGroup.add(yelMesh);
        }
      } else if (currentVisualizationMode === 'circulation') {
        const step = 30.0;
        const dotGeo = new THREE.SphereGeometry(3.0, 8, 8);
        const dotMat = new THREE.MeshBasicMaterial({ color: 0x10b981 });
        for (let x = roomMinX + 20; x <= roomMaxX - 20; x += step) {
          for (let z = roomMinZ + 20; z <= roomMaxZ - 20; z += step) {
            const pBox = new THREE.Box3(new THREE.Vector3(x - 5, 0, z - 5), new THREE.Vector3(x + 5, 40, z + 5));
            let blocked = false;
            for (const [id, inst] of activeModels.entries()) {
              if (pBox.intersectsBox(new THREE.Box3().setFromObject(inst))) { blocked = true; break; }
            }
            if (!blocked) {
              const dot = new THREE.Mesh(dotGeo, dotMat);
              dot.position.set(x, 1.0, z);
              overlayGroup.add(dot);
            }
          }
        }
      }
    }

    window.RendererAdapterInstance = {
      sendEvent(type, payload, transactionId) {
        const msg = JSON.stringify({
          version: '1.0.0',
          type: type,
          transactionId: transactionId || 'tx_' + Date.now(),
          payload: payload || {}
        });
        if (window.FlutterBridge) window.FlutterBridge.postMessage(msg);
        else if (window.parent) window.parent.postMessage(msg, '*');
      },
      receiveCommand(data) {
        if (!data) return;
        const { type, transactionId, payload } = data;

        switch (type) {
          case "HELLO":
            this.sendEvent("READY", { status: "ready" }, transactionId);
            break;
          case "PING":
            this.sendEvent("PONG", {}, transactionId);
            break;
          case "LOAD_ROOM":
            loadRoom(payload);
            break;
          case "LOAD_MODEL": {
            const { id, glbUrl, x, y, z, rotationX, rotationY, rotationZ, scaleX, scaleY, scaleZ, width, height, depth } = payload;
            const existingInstance = activeModels.get(id);
            if (existingInstance) {
              if (transformControls && transformControls.object === existingInstance && transformControls.dragging) break;
              const tolerance = 0.01;
              if (x !== undefined && Math.abs(existingInstance.position.x - x) > tolerance) existingInstance.position.x = x;
              if (y !== undefined && Math.abs(existingInstance.position.y - y) > tolerance) existingInstance.position.y = y;
              if (z !== undefined && Math.abs(existingInstance.position.z - z) > tolerance) existingInstance.position.z = z;

              if (rotationX !== undefined || rotationY !== undefined || rotationZ !== undefined) {
                const rx = rotationX !== undefined ? rotationX : -existingInstance.rotation.x;
                const ry = rotationY !== undefined ? rotationY : -existingInstance.rotation.y;
                const rz = rotationZ !== undefined ? rotationZ : -existingInstance.rotation.z;
                existingInstance.rotation.set(-rx, -ry, -rz, 'YXZ');
              }

              const isPlaceholder = existingInstance.userData.isPlaceholder;
              const sfx = isPlaceholder ? 1.0 : (existingInstance.userData.scaleFactorX || 1.0);
              const sfy = isPlaceholder ? 1.0 : (existingInstance.userData.scaleFactorY || 1.0);
              const sfz = isPlaceholder ? 1.0 : (existingInstance.userData.scaleFactorZ || 1.0);

              if (scaleX !== undefined) existingInstance.scale.x = (scaleX || 1.0) * sfx;
              if (scaleY !== undefined) existingInstance.scale.y = (scaleY || 1.0) * sfy;
              if (scaleZ !== undefined) existingInstance.scale.z = (scaleZ || 1.0) * sfz;

              updateObjectMaterial(isPlaceholder ? existingInstance : existingInstance.children[0], payload);
              break;
            }

            const targetW = width || 100.0;
            const targetH = height || 100.0;
            const targetD = depth || 100.0;

            const placeholderGeo = new THREE.BoxGeometry(targetW, targetH, targetD);
            const placeholderMat = new THREE.MeshBasicMaterial({ color: 0x3b82f6, wireframe: true, transparent: true, opacity: 0.6 });
            const placeholderMesh = new THREE.Mesh(placeholderGeo, placeholderMat);
            placeholderMesh.position.set(x || 0, (y || 0) + targetH / 2, z || 0);
            placeholderMesh.rotation.set(-(rotationX || 0), -(rotationY || 0), -(rotationZ || 0), 'YXZ');
            placeholderMesh.scale.set(scaleX || 1.0, scaleY || 1.0, scaleZ || 1.0);
            placeholderMesh.userData.isPlaceholder = true;

            furnitureGroup.add(placeholderMesh);
            activeModels.set(id, placeholderMesh);

            loadGlbModel(glbUrl).then((template) => {
              const placeholder = activeModels.get(id);
              if (!placeholder || !placeholder.userData.isPlaceholder) return;

              const model = template.clone();
              const box = new THREE.Box3().setFromObject(model);
              const center = new THREE.Vector3();
              box.getCenter(center);
              const nativeSize = new THREE.Vector3();
              box.getSize(nativeSize);

              console.log(`[GLB LOAD] Model '${payload.name}' native size: (${nativeSize.x.toFixed(2)}, ${nativeSize.y.toFixed(2)}, ${nativeSize.z.toFixed(2)}) cm`);
              console.log(`[GLB LOAD] Database target size: (${targetW}, ${targetH}, ${targetD}) cm`);

              const pivotGroup = new THREE.Group();
              pivotGroup.add(model);
              model.position.set(-center.x, -box.min.y, -center.z);

              const scaleFactorX = nativeSize.x > 0.0001 ? targetW / nativeSize.x : 1.0;
              const scaleFactorY = nativeSize.y > 0.0001 ? targetH / nativeSize.y : 1.0;
              const scaleFactorZ = nativeSize.z > 0.0001 ? targetD / nativeSize.z : 1.0;

              console.log(`[GLB LOAD] Scale Factors: X=${scaleFactorX.toFixed(4)}, Y=${scaleFactorY.toFixed(4)}, Z=${scaleFactorZ.toFixed(4)}`);

              pivotGroup.userData.scaleFactorX = scaleFactorX;
              pivotGroup.userData.scaleFactorY = scaleFactorY;
              pivotGroup.userData.scaleFactorZ = scaleFactorZ;
              pivotGroup.userData.assetId = payload.assetId;
              pivotGroup.userData.name = payload.name;

              pivotGroup.position.set(placeholder.position.x, y || 0, placeholder.position.z);
              pivotGroup.rotation.copy(placeholder.rotation);
              pivotGroup.scale.set((scaleX || 1.0) * scaleFactorX, (scaleY || 1.0) * scaleFactorY, (scaleZ || 1.0) * scaleFactorZ);

              model.traverse((child) => {
                if (child.isMesh && child.material) {
                  child.material = Array.isArray(child.material) ? child.material.map(m => m.clone()) : child.material.clone();
                  child.castShadow = true;
                  child.receiveShadow = true;
                }
              });

              updateObjectMaterial(model, payload);
              furnitureGroup.remove(placeholder);
              placeholderGeo.dispose();
              placeholderMat.dispose();

              furnitureGroup.add(pivotGroup);
              activeModels.set(id, pivotGroup);

              logRenderBounds(payload.assetId, payload.name, pivotGroup);

              if (id === currentSelectedId) selectModelInstance(id);
            }).catch((err) => {
              console.error(`Failed to load GLB model ${glbUrl}: ${err.message}`);
              const placeholder = activeModels.get(id);
              if (placeholder && placeholder.userData.isPlaceholder) placeholder.material.color.setHex(0xef4444);
            });
            break;
          }
          case "REMOVE_MODEL": {
            const { id } = payload;
            const instance = activeModels.get(id);
            if (instance) {
              if (transformControls && transformControls.object === instance) transformControls.detach();
              furnitureGroup.remove(instance);
              activeModels.delete(id);
            }
            break;
          }
          case "SELECT_OBJECT": {
            selectModelInstance(payload.id);
            break;
          }
          case "SET_CAMERA_VIEW":
          case "SET_CAMERA": {
            const preset = payload.view || payload.preset || payload.mode || 'ISOMETRIC';
            setCameraView(preset);
            break;
          }
          case "FIT_CAMERA_TO_ROOM": {
            fitCameraToRoom();
            break;
          }
          case "SET_VISUALIZATION_MODE": {
            updateVisualizationOverlay(payload.mode);
            break;
          }
          case "GENERATE_IMAGE": {
            fitCameraToRoom();
            renderer.setSize(1920, 1080, false);
            camera.aspect = 1920 / 1080;
            camera.updateProjectionMatrix();

            renderer.render(scene, camera);
            const dataUrl = renderer.domElement.toDataURL('image/png');

            const container = document.getElementById('viewport-container');
            renderer.setSize(container.clientWidth, container.clientHeight);
            camera.aspect = container.clientWidth / container.clientHeight;
            camera.updateProjectionMatrix();
            renderer.render(scene, camera);

            this.sendEvent("IMAGE_GENERATED", { dataUrl: dataUrl }, transactionId);
            break;
          }
        }
      }
    };

    window.addEventListener('message', (event) => {
      let data = event.data;
      if (typeof data === 'string') {
        try { data = JSON.parse(data); } catch (e) { return; }
      }
      if (data && data.type) {
        window.RendererAdapterInstance.receiveCommand(data);
      }
    });

    document.addEventListener("DOMContentLoaded", () => {
      initThree();
    });
  </script>
</body>
</html>
''';
}
