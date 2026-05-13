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

    private

    def normalize_pts(args)
      pts = args.flatten(1)
      return pts.each_slice(3).to_a if pts.first.is_a?(Numeric)
      pts.map do |p|
        p.respond_to?(:to_a) ? p.to_a.map(&:to_f) : [p[0].to_f, p[1].to_f, p[2].to_f]
      end
    end
  end
end
