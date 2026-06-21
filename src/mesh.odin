package fovea

import "core:fmt"
import "core:math/linalg"

Mesh :: struct {
    vertices:          []v3,
    // either per face or per vertex
    normals:           []v3,
    uv:                []v2,
    // the mesh itself can store the faces or we could bake them into the triangle itself
    faces:             []v3i,
    // when true, interpolate between all normals, otherwise use geometric normal
    per_vertex_normal: bool,
    per_vertex_uv:     bool,
    material:          u32,
}

delete_meshes :: proc(meshes: [dynamic]Mesh) {
    for &m in meshes {
        delete(m.normals)
        delete(m.faces)
        delete(m.vertices)
        delete(m.uv)
    }
    delete(meshes)
}

get_face_vertices :: #force_inline proc(
    mt: MeshTriangle,
    mesh: ^Mesh,
) -> (
    v3,
    v3,
    v3,
) {
    // this looks like a lot of indirection, is this clever? good enough for now...
    f := mesh.faces[mt.face_index]
    return mesh.vertices[f[0]], mesh.vertices[f[1]], mesh.vertices[f[2]]
}

get_triangles_for_mesh :: proc(
    mesh_index: u32,
    face_count: int,
) -> []Primitive {
    triangles := make([]Primitive, face_count)
    for f := 0; f < face_count; f += 1 {
        triangles[f] = MeshTriangle {
            face_index = u32(f),
            mesh_index = mesh_index,
        }
    }
    return triangles
}

// might be useful in general at some point
@(private = "file")
get_face_normal :: proc(face_vertices: ^v3i, vertices: []v3) -> v3 {
    v0 := vertices[face_vertices[0]]
    v1 := vertices[face_vertices[1]]
    v2 := vertices[face_vertices[2]]
    return linalg.normalize(linalg.cross(v0 - v1, v0 - v2))
}

// like the previous C# iteration, do not implement quads as stand-alone
// geometry, but rather build it from two triangles as a mesh.
// this is slightly overkill compared to adding two stand-alone triangles,
// but yields easy uv coordinates
make_quad :: proc(axis: Axis, position: f32, p0: v2, p1: v2) -> Mesh {

    verts := make([]v3, 4)
    faces := make([]v3i, 2)
    normals := make([]v3, 2)

    // for a plane with normal y, p0 would be x-min, z-min, p1 x-max, z-max
    min_on_axis := linalg.min(p0, p1)
    max_on_axis := linalg.max(p0, p1)

    // axis is the axis that is perpendicular to the plane, i.e. the normal
    // we build this assuming +y points up, -z into the screen, +x to the right
    if axis == Axis.Y {
        // when viewed looking -Y
        verts[0] = v3{min_on_axis[0], position, min_on_axis[1]} // top-left
        verts[1] = v3{max_on_axis[0], position, min_on_axis[1]} // top-right
        verts[2] = v3{max_on_axis[0], position, max_on_axis[1]} // bottom-right
        verts[3] = v3{min_on_axis[0], position, max_on_axis[1]} // bottom-left
        // ccw
        faces[0] = {0, 3, 2}
        faces[1] = {0, 3, 1}

        normals[0] = get_face_normal(&faces[0], verts)
        normals[1] = get_face_normal(&faces[1], verts)
    }

    return Mesh {
        vertices = verts,
        faces    = faces,
        normals  = normals,
        // per vertex normals do not really make sense for a quad (yet)
    }
}

