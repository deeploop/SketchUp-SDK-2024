// Bridge DLL between the SketchUp C SDK and Ruby FFI.
//
// The SketchUp C SDK passes handles as opaque structs:
//   typedef struct { void* ptr; } SUModelRef;
//
// Ruby FFI can't easily pass structs by value, so this layer
// unwraps/wraps them so every function takes/returns plain void*.
// Ruby sees only pointers and primitives — no struct gymnastics.

#include <SketchUpAPI/common.h>
#include <SketchUpAPI/geometry.h>
#include <SketchUpAPI/initialize.h>
#include <SketchUpAPI/model/model.h>
#include <SketchUpAPI/model/entities.h>
#include <SketchUpAPI/model/face.h>
#include <SketchUpAPI/model/layer.h>
#include <SketchUpAPI/model/material.h>
#include <SketchUpAPI/model/drawing_element.h>
#include <SketchUpAPI/unicodestring.h>

#include <cstring>
#include <new>
#include <cstdio>

#define BRIDGE extern "C" __declspec(dllexport)

// ── Helpers: wrap/unwrap opaque structs ─────────────────────────────────────

static inline SUModelRef     WrapModel    (void* p) { SUModelRef     r = {p}; return r; }
static inline SUEntitiesRef  WrapEntities (void* p) { SUEntitiesRef  r = {p}; return r; }
static inline SULayerRef     WrapLayer    (void* p) { SULayerRef     r = {p}; return r; }
static inline SUMaterialRef  WrapMaterial (void* p) { SUMaterialRef  r = {p}; return r; }
static inline SUFaceRef      WrapFace     (void* p) { SUFaceRef      r = {p}; return r; }

// ── Lifecycle ────────────────────────────────────────────────────────────────

BRIDGE void su_initialize() { SUInitialize(); }
BRIDGE void su_terminate()  { SUTerminate(); }

// ── Model ────────────────────────────────────────────────────────────────────

BRIDGE void* model_create() {
  SUModelRef m = SU_INVALID;
  if (SUModelCreate(&m) != SU_ERROR_NONE) return nullptr;
  return m.ptr;
}

BRIDGE void model_release(void* p) {
  SUModelRef m = WrapModel(p);
  SUModelRelease(&m);
}

// Returns 0 on success (SU_ERROR_NONE).
BRIDGE int model_save(void* p, const char* path) {
  return (int)SUModelSaveToFile(WrapModel(p), path);
}

BRIDGE void model_set_name(void* p, const char* name) {
  SUModelSetName(WrapModel(p), name);
}

BRIDGE void model_set_description(void* p, const char* desc) {
  SUModelSetDescription(WrapModel(p), desc);
}

BRIDGE void* model_get_entities(void* p) {
  SUEntitiesRef ents = SU_INVALID;
  SUModelGetEntities(WrapModel(p), &ents);
  return ents.ptr;
}

// Creates a named layer, adds it to the model, returns the layer handle.
BRIDGE void* model_add_layer(void* model_ptr, const char* name) {
  SULayerRef layer = SU_INVALID;
  if (SULayerCreate(&layer) != SU_ERROR_NONE) return nullptr;
  SULayerSetName(layer, name);
  SUModelAddLayers(WrapModel(model_ptr), 1, &layer);
  return layer.ptr;
}

// Creates a named material with an RGB color, adds it to the model, returns handle.
BRIDGE void* model_add_material(void* model_ptr, const char* name,
                                 unsigned char r, unsigned char g, unsigned char b) {
  SUMaterialRef mat = SU_INVALID;
  if (SUMaterialCreate(&mat) != SU_ERROR_NONE) return nullptr;
  SUMaterialSetName(mat, name);
  SUColor color = { r, g, b, 255 };
  SUMaterialSetColor(mat, &color);
  SUModelAddMaterials(WrapModel(model_ptr), 1, &mat);
  return mat.ptr;
}

// ── Material ─────────────────────────────────────────────────────────────────

// Update the color of an already-committed material.
BRIDGE void material_set_color(void* mat_ptr,
                                unsigned char r, unsigned char g, unsigned char b) {
  SUColor color = { r, g, b, 255 };
  SUMaterialSetColor(WrapMaterial(mat_ptr), &color);
}

BRIDGE void material_set_opacity(void* mat_ptr, double alpha) {
  SUMaterialSetOpacity(WrapMaterial(mat_ptr), alpha);
  SUMaterialSetUseOpacity(WrapMaterial(mat_ptr), true);
}

// ── Entities / Face ──────────────────────────────────────────────────────────

// pts: flat C array of doubles [x0,y0,z0, x1,y1,z1, ...], n_pts: vertex count.
// Returns the face handle, or nullptr on failure.
BRIDGE void* entities_add_face(void* ents_ptr, const double* pts, int n_pts) {
  if (!pts || n_pts < 3) return nullptr;

  SUPoint3D* su_pts = new (std::nothrow) SUPoint3D[n_pts];
  if (!su_pts) return nullptr;

  for (int i = 0; i < n_pts; ++i) {
    su_pts[i].x = pts[i * 3 + 0];
    su_pts[i].y = pts[i * 3 + 1];
    su_pts[i].z = pts[i * 3 + 2];
  }

  SULoopInputRef loop = SU_INVALID;
  SULoopInputCreate(&loop);
  for (int i = 0; i < n_pts; ++i)
    SULoopInputAddVertexIndex(loop, (size_t)i);

  SUFaceRef face = SU_INVALID;
  SUResult r = SUFaceCreate(&face, su_pts, &loop);
  delete[] su_pts;

  if (r != SU_ERROR_NONE) return nullptr;

  SUEntitiesRef ents = WrapEntities(ents_ptr);
  SUEntitiesAddFaces(ents, 1, &face);
  return face.ptr;
}

BRIDGE void face_set_front_material(void* face_ptr, void* mat_ptr) {
  SUFaceSetFrontMaterial(WrapFace(face_ptr), WrapMaterial(mat_ptr));
}

BRIDGE void face_set_back_material(void* face_ptr, void* mat_ptr) {
  SUFaceSetBackMaterial(WrapFace(face_ptr), WrapMaterial(mat_ptr));
}

BRIDGE void face_set_layer(void* face_ptr, void* layer_ptr) {
  SUDrawingElementRef elem = SUFaceToDrawingElement(WrapFace(face_ptr));
  SUDrawingElementSetLayer(elem, WrapLayer(layer_ptr));
}

// ── Model read-back / verification ──────────────────────────────────────────

// Opens an existing .skp file. Returns model handle, or nullptr on failure.
BRIDGE void* model_open(const char* path) {
  SUModelRef m = SU_INVALID;
  if (SUModelCreateFromFile(&m, path) != SU_ERROR_NONE) return nullptr;
  return m.ptr;
}

// Fills stats_out[8] with entity counts indexed by SUModelStatistics::SUEntityType:
//   [0] edges  [1] faces  [2] component-instances  [3] groups
//   [4] images [5] component-definitions [6] layers [7] materials
BRIDGE void model_get_stats(void* model_ptr, int* stats_out) {
  struct SUModelStatistics s;
  std::memset(&s, 0, sizeof(s));
  SUModelGetStatistics(WrapModel(model_ptr), &s);
  for (int i = 0; i < static_cast<int>(SUModelStatistics::SUNumEntityTypes); ++i)
    stats_out[i] = s.entity_counts[i];
}
