--  Week 1 / P2: safe reader for the ISO BMFF box header.
--
--  File offsets are 1-based absolute byte positions. The Data argument
--  contains the header bytes at those same positions; it need not hold
--  the box payload (notably mdat). File_Size is the complete file size.
--  All malformed, truncated or unrepresentable headers return Ok = False.
--
--  No I/O and no heap allocation. Callers must separately verify that any
--  payload bytes they plan to examine are present in their input buffer.

package Framewise.ISOBMFF.Boxes with SPARK_Mode is

   type Box_Header is record
      Kind          : String (1 .. 4) := [others => ' '];
      Box_First     : Natural := 0;
      Box_Last      : Natural := 0;
      Header_Length : Natural := 0;
      Payload_First : Natural := 0; --  0 for an empty payload
      Payload_Size  : Natural := 0;
   end record;

   procedure Read_Box
     (Data      : Byte_Array;
      Position  : Positive;
      File_Size : Natural;
      Header    : out Box_Header;
      Ok        : out Boolean)
     with Post =>
       (if Ok then
          Header.Box_First = Position
          and then Header.Box_Last <= File_Size
          and then Header.Box_Last >= Position
          and then Header.Header_Length in 8 | 16
          and then Header.Payload_Size =
            Header.Box_Last - Header.Box_First + 1 - Header.Header_Length
          and then (if Header.Payload_Size > 0 then
                      Header.Payload_First = Position + Header.Header_Length));
   --  A size of 0 means through File_Size (not through Data'Last).
   --  A size of 1 introduces an unsigned 64-bit largesize. Values that
   --  do not fit Natural are intentionally rejected, as all existing
   --  Framewise sample offsets use Natural.

end Framewise.ISOBMFF.Boxes;
