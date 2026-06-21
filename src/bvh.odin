package fovea

import "core:container/queue"
import fmt "core:fmt"
import "core:math/linalg"
/*
    BVH from the previous (C#) iteration, based on PBR book.
    (https://pbr-book.org/4ed/Primitives_and_Intersection_Acceleration/Bounding_Volume_Hierarchies)
    - verify the whole slice/dynamic array mess and actual binning logic
*/

// max tree depth
@(private = "file")
max_depth :: 12

// buckets to use for surface area heuristic
@(private = "file")
bucket_count :: 12

// don't split further if node volume goes below this value
@(private = "file")
volume_threshold :: 1e-4

// don't split further if node has at most this amount of primitives
@(private = "file")
min_prim_count :: 2

// a bounding box is defined by the two positions that are min/max in each dimension
BoundingBox :: struct {
    min: v3,
    max: v3,
}

ray_intersect_box :: proc(
    b: BoundingBox,
    ray: Ray,
    interval: RayInterval,
) -> bool {

    interval := interval

    for a := 0; a < 3; a += 1 {
        t0 := (b.min[a] - ray.origin[a]) * ray.inv_dir[a]
        t1 := (b.max[a] - ray.origin[a]) * ray.inv_dir[a]

        if ray.inv_dir[a] < 0 {
            t0, t1 = t1, t0
        }

        if t0 > interval.t_min {
            interval.t_min = t0
        }

        if t1 < interval.t_max {
            interval.t_max = t1
        }

        if interval.t_max <= interval.t_min {
            return false
        }
    }
    return true
}

// a node within the BVH tree
BVHNode :: struct {
    bounds: BoundingBox,
    // primitive count in this node, zero for inner nodes
    count:  int,
    // index in node array to right child, left child is implicitly
    // positioned at index + 1. For leaves this indexes into the
    // primitive array/slice
    next:   int,
}

// the whole tree is simply all the nodes, index 0 being the root
// the primitive array is sorted according to the indices within nodes, i.e. primitives
// within a leaf are next to each other
BVHTree :: struct {
    geometries: []Primitive,
    nodes:      [dynamic]BVHNode,
}

intersect_bvh :: proc(
    tree: BVHTree,
    ray: Ray,
    interval: RayInterval,
    intersection: ^Intersection,
) -> bool {

    interval := interval
    node_stack: [max_depth * 2]int
    node_stack = -1

    // push root node
    stack_pointer := 1
    node_stack[0] = 0

    hit := false

    for stack_pointer > 0 {
        node_index := node_stack[stack_pointer - 1]
        stack_pointer -= 1

        node := tree.nodes[node_index]

        if !ray_intersect_box(node.bounds, ray, interval) {
            continue
        }

        // leaf?
        if node.count > 0 {
            for p := node.next; p < node.next + node.count; p += 1 {
                if intersect_primitive(
                    tree.geometries[p],
                    ray,
                    interval,
                    intersection,
                ) {
                    interval.t_max = intersection.ray_t
                    hit = true
                }
            }
        } else {
            node_stack[stack_pointer] = node_index + 1
            node_stack[stack_pointer + 1] = node.next
            stack_pointer += 2
        }
    }

    return hit
}

// creates the empty box, spanning min=[inf,..] to max[-inf]
// i.e. union on this and any other 'normal' box should yield the normal box
get_empty_bounds :: proc() -> BoundingBox {
    return BoundingBox {
        min = v3{PosInf, PosInf, PosInf},
        max = v3{NegInf, NegInf, NegInf},
    }
}

// compute the union of two bounding box, such that the result tightly contains both argument boxes
bounds_union :: proc(a: BoundingBox, b: BoundingBox) -> BoundingBox {
    return BoundingBox {
        min = linalg.min(a.min, b.min),
        max = linalg.max(a.max, b.max),
    }
}

// compute the size of the bounding box in all three dimensions
get_bounds_extent :: proc(bounds: BoundingBox) -> v3 {
    return bounds.max - bounds.min
}

// compute the geometric center of the box
get_bounds_centroid :: proc(bounds: BoundingBox) -> v3 {
    return bounds.min * 0.5 + bounds.max * 0.5
}

// gets the bounding box volume
get_bounds_volume :: proc(bounds: BoundingBox) -> f32 {
    ext := get_bounds_extent(bounds)
    return ext.x * ext.y * ext.z
}

// area of box
get_bounds_area :: proc(bounds: BoundingBox) -> f32 {
    ext := get_bounds_extent(bounds)
    return 2.0 * (ext.x * ext.y + ext.y * ext.z + ext.z * ext.x)
}

// from pbrt book. used for bucket/bin projection,
// given a primitive centroid and the centroid bounds of
// all primitives it scales offsets of primitive centroids from 0,0,0 to 1,1,1
@(private = "file")
get_offset :: proc(bounds: BoundingBox, centroid: v3) -> v3 {
    o := centroid - bounds.min
    ext := get_bounds_extent(bounds)
    // avoid division by zero
    return v3 {
        o.x / ext.x if ext.x > 0 else o.x,
        o.y / ext.y if ext.y > 0 else o.y,
        o.z / ext.z if ext.z > 0 else o.z,
    }
}

// helper struct to group parameters during recursive tree building
// this keeps track of the global state and/or holds state that does not
// change across calls
@(private = "file")
BuilderState :: struct {
    // current nodes
    nodes:      [dynamic]BVHNode,
    // all boxes
    prim_boxes: []BoundingBox,
    // gets sorted in-place
    primitives: []Primitive,
}

@(private = "file")
SAHBucket :: struct {
    // bounds of this bucket
    bounds: BoundingBox,
    // primitives projected into this bucket
    count:  int,
}

// adds minimal padding to bounding boxes such that no dimension is zero in size
padded_box :: proc(bounds: ^BoundingBox) {
    delta: f32 : 1e-5
    ext := get_bounds_extent(bounds^)
    for axis := 0; axis < 3; axis += 1 {
        if ext[axis] < delta {
            bounds.min[axis] -= delta
            bounds.max[axis] += delta
        }
    }
}

build_bvh_tree :: proc(prims: []Primitive) -> BVHTree {

    // all bounding boxes. These are carried along during construction and are deleted at the end
    boxes := make([dynamic]BoundingBox, 0, len(prims))
    defer delete(boxes)

    scene_bounds := get_empty_bounds()

    // compute scene bounds and bounding boxes of all scene elements
    for p in prims {
        prim_bounds := get_primitive_bounds(p)
        padded_box(&prim_bounds)
        scene_bounds = bounds_union(scene_bounds, prim_bounds)
        append(&boxes, prim_bounds)
    }

    fmt.println("Scene bounds:", scene_bounds)

    state := BuilderState {
        nodes      = make([dynamic]BVHNode, 0, len(prims) * 2),
        prim_boxes = boxes[:],
        primitives = prims,
    }

    build_node(scene_bounds, 0, len(boxes), 0, &state)

    resize(&state.nodes, len(state.nodes))

    // print some stats
    max_leaf_size := 0
    prim_count := 0
    leaf_count := 0
    inner_node_count := 0

    // odin queue is double-ended and can also be used as a stack
    stack: queue.Queue(int)
    queue.init(&stack)

    // push root
    queue.append(&stack, 0)
    for queue.len(stack) > 0 {
        node_index := queue.pop_back(&stack)
        node := state.nodes[node_index]

        if node.count == 0 {
            inner_node_count += 1
            queue.push_back(&stack, node_index + 1)
            queue.push_back(&stack, node.next)
        } else {
            prim_count += node.count
            max_leaf_size = max(max_leaf_size, node.count)
            leaf_count += 1
        }
    }

    queue.destroy(&stack)

    fmt.println("** Some tree stats **")
    fmt.println(
        "Primitive Count:",
        prim_count,
        "max. leaf size:",
        max_leaf_size,
    )
    fmt.println(
        "inner node count",
        inner_node_count,
        "leaf nodes",
        leaf_count,
        "total node count",
        len(state.nodes),
    )

    return BVHTree{nodes = state.nodes, geometries = state.primitives}
}

@(private = "file")
make_leaf :: proc(
    state: ^BuilderState,
    box: BoundingBox,
    first_prim: int,
    count: int,
) {
    append(
        &state.nodes,
        BVHNode{bounds = box, next = first_prim, count = count},
    )
}

@(private = "file")
bucket_projection :: proc(
    node_centroid: BoundingBox,
    prim_centroid: v3,
    axis: int,
) -> int {
    offset := get_offset(node_centroid, prim_centroid)[axis]

    b := int(f32(bucket_count) * offset)
    if b == bucket_count {
        b -= 1
    }
    return b
}

@(private = "file")
build_node :: proc(
    node_bounds: BoundingBox,
    left: int,
    right: int,
    depth: int,
    state: ^BuilderState,
) {

    // left and right are indices into the prim (bounds) array
    count := right - left

    // done?
    if depth > max_depth || count <= min_prim_count {
        make_leaf(state, node_bounds, left, count)
    } else {
        // compute a bounding box which contains all centroids of all boxes at this stage
        centroid_min := v3{PosInf, PosInf, PosInf}
        centroid_max := v3{NegInf, NegInf, NegInf}

        for p := left; p < right; p += 1 {
            box_centroid := get_bounds_centroid(state.prim_boxes[p])
            centroid_min = linalg.min(centroid_min, box_centroid)
            centroid_max = linalg.max(centroid_max, box_centroid)
        }

        centroid_bounds := BoundingBox {
            min = centroid_min,
            max = centroid_max,
        }

        if get_bounds_volume(centroid_bounds) < volume_threshold {
            make_leaf(state, node_bounds, left, count)
        } else {
            area := get_bounds_area(node_bounds)
            axis, bucket, cost := get_best_split(
                centroid_bounds,
                area,
                left,
                right,
                state,
            )

            // splitting is better than doing a leaf
            if cost < f32(count) {
                left_box := get_empty_bounds()
                right_box := get_empty_bounds()

                // in-place sort according to split
                // first index to sort primitives on the left side into
                left_index := left

                for p := left; p < right; p += 1 {
                    // get bucket for this primitive
                    prim_bucket := bucket_projection(
                        centroid_bounds,
                        get_bounds_centroid(state.prim_boxes[p]),
                        axis,
                    )

                    if prim_bucket <= bucket {
                        if p != left_index {
                            // swap things
                            tmp_prim := state.primitives[p]
                            tmp_box := state.prim_boxes[p]
                            state.primitives[p] = state.primitives[left_index]
                            state.prim_boxes[p] = state.prim_boxes[left_index]
                            state.primitives[left_index] = tmp_prim
                            state.prim_boxes[left_index] = tmp_box
                        }

                        left_box = bounds_union(
                            left_box,
                            state.prim_boxes[left_index],
                        )
                        left_index += 1

                    } else {
                        right_box = bounds_union(
                            right_box,
                            state.prim_boxes[p],
                        )
                    }
                }

                middle := left_index

                // inner node
                append(&state.nodes, BVHNode{bounds = node_bounds})

                inner_node_index := len(state.nodes) - 1
                // the next node that will get appended is our left child, which sits implicitly
                // at our own index + 1
                build_node(left_box, left, middle, depth + 1, state)
                // the next node that will get appended is our right child
                state.nodes[inner_node_index].next = len(state.nodes)
                build_node(right_box, middle, right, depth + 1, state)
            } else {
                make_leaf(state, node_bounds, left, count)
            }
        }

    }
}

@(private = "file")
get_best_split :: proc(
    node_centroid_bounds: BoundingBox, // bounding box of all centroids in current node
    node_area: f32,
    left: int,
    right: int,
    state: ^BuilderState,
) -> (
    best_axis: int,
    best_bucket: int,
    best_costs: f32,
) {

    best_bucket = -1
    best_costs = PosInf
    best_axis = -1

    // do this for all three dimensions
    for axis := 0; axis < 3; axis += 1 {

        buckets: [bucket_count]SAHBucket
        buckets = SAHBucket {
            bounds = get_empty_bounds(),
            count  = 0,
        }

        // project primitives into their bucket
        for p := left; p < right; p += 1 {
            bucket_num := bucket_projection(
                node_centroid_bounds,
                get_bounds_centroid(state.prim_boxes[p]),
                axis,
            )
            buckets[bucket_num].count += 1
            buckets[bucket_num].bounds = bounds_union(
                buckets[bucket_num].bounds,
                state.prim_boxes[p],
            )
        }

        sweepLeftBox := get_empty_bounds()

        // sweep left and right and collect areas / primitive counts for each split along bucket boundaries

        count_left := 0
        costs: [bucket_count - 1]f32
        // probably not necessary, since 0 is the zero value
        costs = 0.0

        for b := 0; b < bucket_count - 1; b += 1 {
            sweepLeftBox = bounds_union(sweepLeftBox, buckets[b].bounds)
            count_left += buckets[b].count
            costs[b] += f32(count_left) * get_bounds_area(sweepLeftBox)
        }

        sweepRightBox := get_empty_bounds()
        count_right := 0

        for b := bucket_count - 1; b >= 1; b -= 1 {
            sweepRightBox = bounds_union(sweepRightBox, buckets[b].bounds)
            count_right += buckets[b].count
            costs[b - 1] += f32(count_right) * get_bounds_area(sweepRightBox)
        }

        // check best costs for this axis
        for b := 0; b < bucket_count - 1; b += 1 {
            if costs[b] < best_costs {
                best_costs = 1.0 / 2.0 + costs[b] / node_area
                best_axis = axis
                best_bucket = b
            }
        }

    } // end-for each axis

    return best_axis, best_bucket, best_costs
}

