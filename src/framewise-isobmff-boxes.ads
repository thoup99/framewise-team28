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

   procedure Read_U32
     (Data     : Byte_Array;
      Position : Positive;
      Value    : out Natural;
      Ok       : out Boolean);
   --  Reads 4 big-endian bytes (most significant byte first) at Position.
   --  Ok = False, Value = 0 if any of the 4 bytes is outside Data, or if
   --  the number does not fit Natural (it is 2**31 or more).

   procedure Read_U16
     (Data     : Byte_Array;
      Position : Positive;
      Value    : out Natural;
      Ok       : out Boolean);
   --  Same as Read_U32, for 2 bytes. A 16-bit value always fits Natural,
   --  so the only failure is a byte outside Data.

   subtype Box_Kind is String (1 .. 4);
   --  A box type such as "moov". "subtype" is not a new type: it is String
   --  with the extra rule "exactly 4 characters", like Box_Header.Kind.

   procedure Find_Child
     (Data  : Byte_Array;
      First : Positive;
      Last  : Natural;
      Kind  : Box_Kind;
      Child : out Box_Header;
      Found : out Boolean)
     with Post =>
       (if Found then
          Child.Kind = Kind
          and then Child.Box_First >= First
          and then Child.Box_First <= Child.Box_Last
          and then Child.Box_Last <= Last
          and then Child.Header_Length in 8 | 16
          and then Child.Payload_Size =
            Child.Box_Last - Child.Box_First + 1 - Child.Header_Length
          and then (if Child.Payload_Size > 0 then
                      Child.Payload_First =
                        Child.Box_First + Child.Header_Length));
   --  Walks the boxes in positions First .. Last, one after another, and
   --  returns the first one of type Kind. To look inside a box, pass its
   --  payload range. Found = False means no such box, or a box before it
   --  was malformed: the walk cannot go on past a box whose size it does
   --  not trust.
   --
   --  Every child is checked against Last, so it can never claim to reach
   --  past its parent. That also means size = 0 ("to the end") stops at
   --  Last here, which is the same as end of file for a top-level box.

end Framewise.ISOBMFF.Boxes;
