package fovea

import "core:math"
import "core:math/linalg"

// this should make it easier to switch to a primitive union later, rather
// than replacing sphere all over the place
Primitive :: union {
    Sphere,
    MeshTriangle,
}

MeshTriangle :: struct {
    face_index: u32,
    mesh_index: u32,
}

Sphere :: struct {
    center:   v3,
    radius:   f32,
    material: u32,
}

get_primitive_bounds :: proc(prim: Primitive) -> BoundingBox {
    switch p in prim {
    case Sphere:
        return BoundingBox {
            min = p.center - v3{p.radius, p.radius, p.radius},
            max = p.center + v3{p.radius, p.radius, p.radius},
        }
    case MeshTriangle:
        // look up mesh through context
        world := cast(^World)context.user_ptr
        mesh := &world.meshes[p.mesh_index]
        va, vb, vc := get_face_vertices(p, mesh)
        mt_min := linalg.min(va, vb, vc)
        mt_max := linalg.max(va, vb, vc)
        // bvh will take of padding the zero size axis
        return BoundingBox{min = mt_min, max = mt_max}
    // might as well panic
    case:
        return get_empty_bounds()
    }
}

intersect_primitive :: proc(
    prim: Primitive,
    ray: Ray,
    interval: RayInterval,
    isec: ^Intersection,
) -> bool {
    switch p in prim {
    case Sphere:
        return intersect_sphere(p, ray, interval, isec)
    case MeshTriangle:
        return intersect_mesh_triangle(p, ray, interval, isec)
    case:
        return false
    }
}

intersect_mesh_triangle :: proc(
    mt: MeshTriangle,
    ray: Ray,
    interval: RayInterval,
    isec: ^Intersection,
) -> bool {

    // dig through context to get to the meshes
    world := cast(^World)context.user_ptr
    mesh := &world.meshes[mt.mesh_index]

    f0, f1, f2 := get_face_indices(mt, mesh)

    v0, v1, v2 := mesh.vertices[f0], mesh.vertices[f1], mesh.vertices[f2]
    // the usual Möller–Trumbore

    edge_ab := v1 - v0
    edge_ac := v2 - v0

    p_vec := linalg.cross(ray.direction, edge_ac)
    det := linalg.dot(edge_ab, p_vec)

    // parallel to triangle plane
    if math.abs(det) < 1e-4 {
        return false
    }

    inv_det := 1.0 / det

    t_vec := ray.origin - v0
    u := linalg.dot(t_vec, p_vec) * inv_det

    if u < 0 || u > 1 {
        return false
    }

    q_vec := linalg.cross(t_vec, edge_ab)
    v := linalg.dot(ray.direction, q_vec) * inv_det

    if v < 0 || (u + v) > 1 {
        return false
    }

    ray_t := linalg.dot(q_vec, edge_ac) * inv_det

    if !interval_contains(interval, ray_t) {
        return false
    }

    isec.location = ray_points_at(ray, ray_t)
    isec.ray_t = ray_t
    isec.material = mesh.material

    if mesh.per_vertex_uv {
        // this is pretty excessive to do for every triangle when the material does not require
        // it. Find a better way, i.e. encode into material id if we should do this at all
        w := 1.0 - u - v
        isec.tex_u = mesh.uv[f0].x * w + mesh.uv[f1].x * u + mesh.uv[f2].x * v
        isec.tex_v = mesh.uv[f0].y * w + mesh.uv[f1].y * u + mesh.uv[f2].y * v
    }

    if !mesh.per_vertex_normal {
        set_face_normal(isec, ray.direction, mesh.normals[mt.face_index])
    } else {
        assert(false, "not implemented")
    }

    return true
}

@(private = "file")
intersect_sphere :: proc(
    s: Sphere,
    ray: Ray,
    interval: RayInterval,
    isec: ^Intersection,
) -> bool {
    oc := s.center - ray.origin
    a := linalg.length2(ray.direction)
    h := linalg.dot(ray.direction, oc)
    c := linalg.length2(oc) - s.radius * s.radius
    disc := h * h - a * c

    if disc < 0 {
        return false
    } else {
        d := math.sqrt(disc)
        root := (h - d) / a

        if !interval_contains(interval, root) {
            root = (h + d) / a
            if !interval_contains(interval, root) {
                return false
            }
        }

        isec.location = ray_points_at(ray, root)
        outward_normal := (isec.location - s.center) / s.radius
        // texture coordinates
        theta := math.acos(-outward_normal.y)
        phi := math.atan2(-outward_normal.z, outward_normal.x) + math.PI
        isec.tex_u = phi / (2.0 * math.PI)
        isec.tex_v = theta / math.PI
        set_face_normal(isec, ray.direction, outward_normal)
        isec.ray_t = root
        isec.material = s.material

        return true
    }
}

