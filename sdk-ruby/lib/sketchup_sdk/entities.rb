module Sketchup
  class Entities
    def initialize(handle)
      @handle = handle
    end

    # Accepts: add_face([x,y,z], ...) or add_face([[x,y,z],...]) or Geom::Point3d list.
    def add_face(*args)
      pts = normalize_pts(args)
      n   = pts.size
      raise ArgumentError, "Need >= 3 points, got #{n}" if n < 3

      # Build flat SUPoint3D array (3 x double per vertex)
      pts_buf = FFI::MemoryPointer.new(:double, n * 3)
      pts.each_with_index do |pt, i|
        pts_buf.put_double((i * 3 + 0) * 8, pt[0].to_f)
        pts_buf.put_double((i * 3 + 1) * 8, pt[1].to_f)
        pts_buf.put_double((i * 3 + 2) * 8, pt[2].to_f)
      end

      # Create loop input
      loop_out = SUAPI.out_h
      SUAPI.check! SUAPI.SULoopInputCreate(loop_out), 'SULoopInputCreate'
      loop_h = SUAPI.rh(loop_out)
      n.times { |i| SUAPI.SULoopInputAddVertexIndex(loop_h, i) }

      # Create face
      face_out = SUAPI.out_h
      loop_ptr = SUAPI.h1(loop_h)
      r = SUAPI.SUFaceCreate(face_out, pts_buf, loop_ptr)
      return nil if r != SUAPI::SU_ERROR_NONE

      face_h = SUAPI.rh(face_out)
      return nil if face_h == 0

      SUAPI.SUEntitiesAddFaces(@handle, 1, SUAPI.h1(face_h))
      Face.new(face_h)
    end

    # Create a new Group in this entities collection and return the wrapper.
    def add_group
      out = SUAPI.out_h
      SUAPI.check! SUAPI.SUGroupCreate(out), 'SUGroupCreate'
      g_h = SUAPI.rh(out)
      SUAPI.check! SUAPI.SUEntitiesAddGroup(@handle, g_h), 'SUEntitiesAddGroup'
      Group.new(g_h)
    end

    # Place a ComponentInstance into this entities collection.
    def add_instance(instance)
      r = SUAPI.SUEntitiesAddInstance(@handle, instance.handle, FFI::Pointer::NULL)
      SUAPI.check! r, 'SUEntitiesAddInstance'
      instance
    end

    # Create a face with a single inner hole loop (hollow cross-section end cap).
    # outer_pts / inner_pts — arrays of [x,y,z] on the same plane.
    def add_face_with_hole(outer_pts, inner_pts)
      outer_pts = normalize_pts([outer_pts])
      inner_pts = normalize_pts([inner_pts])

      no = outer_pts.size
      ni = inner_pts.size
      raise ArgumentError, "Need >= 3 outer points, got #{no}" if no < 3
      raise ArgumentError, "Need >= 3 inner points, got #{ni}" if ni < 3

      out_buf = pts_to_buffer(outer_pts)
      in_buf  = pts_to_buffer(inner_pts)

      # Outer loop
      outer_loop_out = SUAPI.out_h
      SUAPI.check! SUAPI.SULoopInputCreate(outer_loop_out), 'SULoopInputCreate (outer)'
      outer_loop_h = SUAPI.rh(outer_loop_out)
      no.times { |i| SUAPI.SULoopInputAddVertexIndex(outer_loop_h, i) }

      # Create face with outer loop (loop ownership transfers to face)
      face_out      = SUAPI.out_h
      outer_loop_ptr = SUAPI.h1(outer_loop_h)
      r = SUAPI.SUFaceCreate(face_out, out_buf, outer_loop_ptr)
      return nil if r != SUAPI::SU_ERROR_NONE

      face_h = SUAPI.rh(face_out)
      return nil if face_h == 0

      # Inner loop (hole)
      inner_loop_out = SUAPI.out_h
      SUAPI.check! SUAPI.SULoopInputCreate(inner_loop_out), 'SULoopInputCreate (inner)'
      inner_loop_h = SUAPI.rh(inner_loop_out)
      ni.times { |i| SUAPI.SULoopInputAddVertexIndex(inner_loop_h, i) }
      inner_loop_ptr = SUAPI.h1(inner_loop_h)

      SUAPI.SUFaceAddInnerLoop(face_h, in_buf, inner_loop_ptr)

      SUAPI.SUEntitiesAddFaces(@handle, 1, SUAPI.h1(face_h))
      Face.new(face_h)
    end

    # Add a finite guide line (dashed construction line) between two 3D points.
    def add_guide_line(start_pt, end_pt)
      s_buf = pt_to_buffer(start_pt)
      e_buf = pt_to_buffer(end_pt)

      gl_out = SUAPI.out_h
      SUAPI.check! SUAPI.SUGuideLineCreateFinite(gl_out, s_buf, e_buf), 'SUGuideLineCreateFinite'
      gl_h = SUAPI.rh(gl_out)

      SUAPI.check! SUAPI.SUEntitiesAddGuideLines(@handle, 1, SUAPI.h1(gl_h)), 'SUEntitiesAddGuideLines'
      gl_h
    end

    private

    def normalize_pts(args)
      pts = args.flatten(1)
      return pts.each_slice(3).to_a if pts.first.is_a?(Numeric)
      pts.map do |p|
        p.respond_to?(:to_a) ? p.to_a.map(&:to_f) : [p[0].to_f, p[1].to_f, p[2].to_f]
      end
    end

    def pts_to_buffer(pts)
      buf = FFI::MemoryPointer.new(:double, pts.size * 3)
      pts.each_with_index do |pt, i|
        buf.put_double((i * 3 + 0) * 8, pt[0].to_f)
        buf.put_double((i * 3 + 1) * 8, pt[1].to_f)
        buf.put_double((i * 3 + 2) * 8, pt[2].to_f)
      end
      buf
    end

    def pt_to_buffer(pt)
      buf = FFI::MemoryPointer.new(:double, 3)
      buf.put_double(0,  pt[0].to_f)
      buf.put_double(8,  pt[1].to_f)
      buf.put_double(16, pt[2].to_f)
      buf
    end
  end
end
