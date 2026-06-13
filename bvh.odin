package fovea

import fmt "core:fmt"
import "core:math/linalg"

// BVH based on the previous (C#) iteration, somewhat based on PBRT book.
// needs some serious review and documentation, i should read that book again :)
// see if can work exclusively on centroids instead of passing bounds around
// verify the whole slice/dynamic array mess and actual binning logic

@(private="file")
max_depth := 32 // max tree depth
@(private="file")
bucket_count := 128 // buckets to use for surface area heuristic
@(private="file")
volume_threshold : f32 = 1e-4 // build a leaf if node volume is below this value
@(private="file")
min_prim_count := 2 // don't split further if node has at most this amount of primitives

// a bounding box is defined by the two positions
// that are min/max in each dimension
BoundingBox :: struct {
    min: v3,
    max: v3
}

BVHNode :: struct {
    bounds: BoundingBox,
    // primitives in this node, zero for inner nodes
    count: int,
    // index in node array to right child, left child is implicitly
    // positioned at index + 1. For leaves this indexes into the
    // primitive array/slice
    next: int
}

// creates the empty box, spanning min=[inf,..] to max[-inf]
// i.e. union on this and any other 'normal' box should yield the normal box
get_empty_bounds :: proc() -> BoundingBox {
    return BoundingBox {
        min = v3{ PosInf, PosInf, PosInf },
        max = v3{ NegInf, NegInf, NegInf },
    }
}

bounds_union :: proc(a: BoundingBox, b: BoundingBox) -> BoundingBox {
    return BoundingBox {
        min = linalg.min(a.min, b.min),
        max = linalg.max(a.max, b.max)
    }
}

get_bounds_extent :: proc(bounds: BoundingBox) -> v3 {
    return bounds.max - bounds.min
}

get_bounds_centroid :: proc(bounds: BoundingBox) -> v3 {
    return bounds.min + get_bounds_extent(bounds) * 0.5
}

get_bounds_volume :: proc(bounds: BoundingBox) -> f32 {
    ext := get_bounds_extent(bounds)
    return ext.x * ext.y * ext.z
}

get_bounds_area :: proc(bounds: BoundingBox) -> f32 {
    ext := get_bounds_extent(bounds)
    return 2.0 * (ext.x * ext.y + ext.y * ext.z + ext.z * ext.x)
}

// from pbrt book. used for bucket/bin projection,
// given a primitive centroid and the centroid bounds of
// all primitives it scales offsets of primitive centroids from 0,0,0 to 1,1,1
@(private="file")
get_offset :: proc(bounds: BoundingBox, centroid: v3) -> v3 {
    o := centroid - bounds.min
    ext := get_bounds_extent(bounds)
    // avoid division by zero
    return v3{
        o.x / ext.x if ext.x > 0 else o.x,
        o.y / ext.y if ext.y > 0 else o.y,
        o.z / ext.z if ext.z > 0 else o.z,
    }
}

// helper struct to group parameters during recursive tree building
// this keeps track of the global state and/or holds state that does not
// change across calls
@(private="file")
BuilderState :: struct {
    nodes: [dynamic]BVHNode, // current nodes
    prim_boxes: []BoundingBox, // all boxes
    primitives: [dynamic]Sphere, // gets sorted in-place
    buckets: [dynamic]SAHBucket // allocated once
}

@(private="file")
SAHBucket :: struct {
    bounds: BoundingBox, // bounds of this bucket
    count: int, // primitives in projected into this bucket
    left_count: int, // primitive count of all buckets left of this one including this one
    right_count: int, // primitive count of all buckets right of this one
    left_area: f32 // summed area of buckets left to this one
}

build_bvh_tree :: proc(prims: [dynamic]Sphere) {

// we know the node bounds on the tree in advance
    nodes := make([dynamic]BVHNode, 0, len(prims) * 2)
    // all bounding boxes. These are carried along during construction
    // and are delete at the end
    boxes := make([dynamic]BoundingBox, 0, len(prims))
    defer delete(boxes)

    scene_bounds := get_empty_bounds()

    // compute scene bounds and bounding boxes of all scene elements
    for p in prims {
        prim_bounds := get_sphere_bounds(p)
        scene_bounds = bounds_union(scene_bounds, prim_bounds)
        append(&boxes, prim_bounds)
    }

    fmt.println("Scene bounds:", scene_bounds)

    state := BuilderState {
        nodes = nodes,
        prim_boxes = boxes[:],
        buckets = make([dynamic]SAHBucket, 0, bucket_count),
        primitives = prims
    }

    defer delete(state.buckets)
    defer delete(state.nodes)

    build_node(scene_bounds, 0, len(boxes), 0, &state)

}

@(private="file")
make_leaf :: proc(state: ^BuilderState, box: BoundingBox, first_prim: int, count: int) {
    append(&state.nodes,
    BVHNode {
        bounds = box,
        next = first_prim,
        count = count
    })
}

@(private="file")
bucket_projection :: proc(node_centroid: BoundingBox, prim_centroid: v3, axis: int) -> int {
//    fmt.println(prim_centroid)
//    fmt.println(get_offset(node_centroid, prim_centroid)[axis])
    offset :=  get_offset(node_centroid, prim_centroid)[axis]
    assert(offset >= 0 && offset <= 1)
    b := int(f32(bucket_count) * offset)
    if b == bucket_count {
        b -= 1
    }
    return b
}

@(private="file")
build_node :: proc(node_bounds: BoundingBox, left: int, right: int, depth: int, state: ^BuilderState) {

// left and right are indices into the prim (bounds) array
    count := right - left

    fmt.println("at depth", depth, "count", count)

    assert(len(state.prim_boxes) > 0)
    assert(len(state.primitives) > 0)

    // done?
    if depth > max_depth || count <= min_prim_count {
    // make leaf
        make_leaf(state, node_bounds, left, count)
//        state.nodes[state.node_index] =
//        state.node_index = state.node_index + 1
    }
    else {
    // compute a bounding box which contains all centroids of all boxes
        centroid_min := v3{ PosInf, PosInf, PosInf }
        centroid_max := v3{ NegInf, NegInf, NegInf }

        for p := left ; p < right ; p += 1 {
            box_centroid := get_bounds_centroid(state.prim_boxes[p])
            centroid_min = linalg.min(centroid_min, box_centroid)
            centroid_max = linalg.max(centroid_max, box_centroid)
        }

        centroid_bounds := BoundingBox{ min=centroid_min, max=centroid_max }

        if get_bounds_volume(centroid_bounds) < volume_threshold {
            make_leaf(state, node_bounds, left, count)
//            state.nodes[state.node_index] =
//            state.node_index = state.node_index + 1
        }
        else {
            area := get_bounds_area(node_bounds)
            axis, bucket, cost := get_best_split(centroid_bounds, area, left, right, state)

            fmt.println("split inner at axis", axis, "costs", cost)
            // splitting is better than doing a leaf
            if cost < f32(count) {
                left_box := get_empty_bounds()
                right_box := get_empty_bounds()

                // old code:why
                //                if bucket == bucket_count - 1 {
                //                    bucket -= 1
                //                }

                // in-place sort according to split
                // first index to sort primitives on the left side into
                left_index := left

                for p := left ; p < right ; p += 1 {
                // get bucket for this primitive
                    prim_bucket := bucket_projection(centroid_bounds,
                    get_bounds_centroid(state.prim_boxes[p]), axis)

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

                        left_index += 1
                        // TODO: review this, should be correct, C# code worked on reference, were swapping won't matter
                        left_box = bounds_union(left_box, state.prim_boxes[p])

                    }
                    else {
                        right_box = bounds_union(right_box, state.prim_boxes[p])
                    }
                }

                middle := left_index

                // inner node
                append(&state.nodes, BVHNode {
                    bounds = node_bounds
                })
                inner_node_index := len(state.nodes) - 1
                build_node(left_box, left, middle, depth + 1, state)
                state.nodes[inner_node_index].next = len(state.nodes) - 1
                build_node(right_box, middle, right, depth + 1, state)
            }
            else {
                make_leaf(state, node_bounds, left, count)
            //                state.nodes[state.node_index] =
            //                state.node_index = state.node_index + 1
            }
        }

    }
}


@(private="file")
get_best_split :: proc(
// bounding box of all centroids in current node
node_centroid_bounds: BoundingBox,
node_area: f32,
left: int,
right: int,
state: ^BuilderState) -> (axis: int, bucket: int, costs: f32) {

    best_bucket := -1
    best_costs := PosInf
    best_axis := -1

    assert((right - left) > 0)

    // do this for all three dimensions
    for axis := 0 ; axis < 3; axis += 1 {

        clear(&state.buckets)

        // reset all buckets for this axis
        for b := 0 ; b < bucket_count ; b += 1 {
            append(&state.buckets, SAHBucket {
                bounds = get_empty_bounds(),
                count = 0
            })
        }

        // project primitives into their bucket
        for p := left ; p < right ; p += 1 {
            bucket_num := bucket_projection(node_centroid_bounds, get_bounds_centroid(state.prim_boxes[p]), axis)
            state.buckets[bucket_num].count += 1
            state.buckets[bucket_num].bounds =
            bounds_union(state.buckets[bucket_num].bounds, state.prim_boxes[p])
        }

        sweepLeftBox := get_empty_bounds()
        sweepRightBox := get_empty_bounds()

        // sweep left and right and collect areas / primitive counts for each split along bucket boundaries
        for b := 0 ; b < bucket_count ; b += 1 {
            sweepLeftBox = bounds_union(sweepLeftBox, state.buckets[b].bounds)
            state.buckets[b].left_area = get_bounds_area(sweepLeftBox)
            state.buckets[b].left_count = state.buckets[b].count
            if b > 0 {
                state.buckets[b].left_count += state.buckets[b - 1].left_count
            }
        }



        for b := bucket_count - 1 ; b >= 0 ; b -= 1 {
            sweepRightBox = bounds_union(sweepRightBox, state.buckets[b].bounds)
            right_area := get_bounds_area(sweepRightBox)
            state.buckets[b].right_count = state.buckets[b].count
            if b < bucket_count - 1 {
                state.buckets[b].right_count += state.buckets[b + 1].right_count
            }

            // split cost
            costs := (state.buckets[b].left_area / node_area) * f32(state.buckets[b].left_count) +
            (right_area / node_area) * f32(state.buckets[b].right_count)

            if costs < best_costs {
                best_costs = costs
                best_axis = axis
                best_bucket = b
            }

        }

    } // end-for each axis

    return best_axis, best_bucket, best_costs
}