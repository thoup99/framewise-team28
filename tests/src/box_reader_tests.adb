--  Pair P / week 1: byte-array tests, no MOV file or media decoder needed.
with Ada.Command_Line;
with Ada.Text_IO;
with Framewise.ISOBMFF;
with Framewise.ISOBMFF.Boxes;

procedure Box_Reader_Tests is
   use Ada.Text_IO;
   use Framewise.ISOBMFF;
   use Framewise.ISOBMFF.Boxes;

   Failures : Natural := 0;
   H        : Box_Header;
   Ok       : Boolean;

   procedure Check (Label_Text : String; Condition : Boolean);

   procedure Check (Label_Text : String; Condition : Boolean) is
   begin
      Put_Line ((if Condition then "PASS " else "FAIL ") & Label_Text);
      if not Condition then
         Failures := Failures + 1;
      end if;
   end Check;

   --  size=12, type=free, 4 payload bytes.
   Standard_Box : constant Byte_Array :=
     [0, 0, 0, 12, 102, 114, 101, 101, 1, 2, 3, 4];

   --  size=1, type=mdat, largesize=20, 4 payload bytes.
   Large_Box : constant Byte_Array :=
     [0, 0, 0, 1, 109, 100, 97, 116,
      0, 0, 0, 0, 0, 0, 0, 20, 1, 2, 3, 4];

   --  size=0: extends to the declared end of the file.
   To_EOF : constant Byte_Array :=
     [0, 0, 0, 0, 109, 100, 97, 116, 1, 2, 3, 4];

   Invalid_Short : constant Byte_Array :=
     [0, 0, 0, 7, 102, 114, 101, 101];

   Invalid_Huge : constant Byte_Array :=
     [0, 0, 0, 1, 109, 100, 97, 116,
      255, 255, 255, 255, 255, 255, 255, 255];

   Header_Only : constant Byte_Array :=
     [0, 0, 0, 20, 109, 100, 97, 116];

begin
   Read_Box (Standard_Box, 1, Standard_Box'Length, H, Ok);
   Check ("standard header", Ok and then H.Kind = "free"
          and then H.Box_First = 1 and then H.Box_Last = 12
          and then H.Header_Length = 8
          and then H.Payload_First = 9 and then H.Payload_Size = 4);

   Read_Box (Large_Box, 1, Large_Box'Length, H, Ok);
   Check ("extended 64-bit size", Ok and then H.Kind = "mdat"
          and then H.Box_Last = 20 and then H.Header_Length = 16
          and then H.Payload_First = 17 and then H.Payload_Size = 4);

   Read_Box (To_EOF, 1, To_EOF'Length, H, Ok);
   Check ("zero size extends to EOF", Ok and then H.Box_Last = 12
          and then H.Payload_Size = 4);

   Read_Box (Header_Only, 1, 20, H, Ok);
   Check ("header-only mdat is supported", Ok and then H.Box_Last = 20
          and then H.Payload_First = 9 and then H.Payload_Size = 12);

   Read_Box (Header_Only, 1, 8, H, Ok);
   Check ("declared box beyond file rejected", not Ok);

   Read_Box (Invalid_Short, 1, Invalid_Short'Length, H, Ok);
   Check ("size less than header rejected", not Ok);

   Read_Box (Invalid_Huge, 1, Invalid_Huge'Length, H, Ok);
   Check ("unrepresentable 64-bit size rejected", not Ok);

   for I in 1 .. Standard_Box'Length - 1 loop
      Read_Box (Standard_Box (1 .. I), 1, I, H, Ok);
      Check ("standard box truncated to" & I'Image, not Ok);
   end loop;

   for I in 1 .. Large_Box'Length - 1 loop
      Read_Box (Large_Box (1 .. I), 1, I, H, Ok);
      Check ("extended box truncated to" & I'Image, not Ok);
   end loop;

   declare
      --  Non-one-based arrays still use absolute offsets.
      At_Ten : constant Byte_Array (10 .. 17) :=
        [0, 0, 0, 8, 102, 114, 101, 101];
   begin
      Read_Box (At_Ten, 10, 17, H, Ok);
      Check ("non-one-based file positions", Ok and then H.Box_First = 10
             and then H.Box_Last = 17 and then H.Payload_Size = 0);
      Read_Box (At_Ten, 9, 17, H, Ok);
      Check ("out-of-buffer position rejected", not Ok);
   end;

   --  Week 2: Read_U32 and Read_U16.
   declare
      Bytes : constant Byte_Array := [16#12#, 16#34#, 16#56#, 16#78#, 16#FF#, 16#FF#];
      Top   : constant Byte_Array := [16#7F#, 16#FF#, 16#FF#, 16#FF#];
      Over  : constant Byte_Array := [16#80#, 16#00#, 16#00#, 16#00#];
      At_Five : constant Byte_Array (5 .. 8) := [0, 0, 1, 0];
      Value : Natural;
   begin
      Read_U32 (Bytes, 1, Value, Ok);
      Check ("U32 is big-endian", Ok and then Value = 16#1234_5678#);
      Read_U16 (Bytes, 1, Value, Ok);
      Check ("U16 is big-endian", Ok and then Value = 16#1234#);
      Read_U16 (Bytes, 5, Value, Ok);
      Check ("U16 reads the largest value", Ok and then Value = 65_535);
      Read_U32 (Bytes, 3, Value, Ok);
      Check ("U32 at a later position", Ok and then Value = 16#5678_FFFF#);

      Read_U32 (Top, 1, Value, Ok);
      Check ("U32 accepts Natural'Last", Ok and then Value = Natural'Last);
      Read_U32 (Over, 1, Value, Ok);
      Check ("U32 of 2**31 rejected", not Ok and then Value = 0);

      Read_U32 (Bytes, 4, Value, Ok);
      Check ("U32 running past the end rejected", not Ok and then Value = 0);
      Read_U32 (Bytes, 7, Value, Ok);
      Check ("U32 starting past the end rejected", not Ok);
      Read_U16 (Bytes, 6, Value, Ok);
      Check ("U16 running past the end rejected", not Ok);
      Read_U16 (Bytes, Positive'Last, Value, Ok);
      Check ("U16 at the largest position rejected", not Ok);

      Read_U32 (At_Five, 5, Value, Ok);
      Check ("U32 uses absolute positions", Ok and then Value = 256);
      Read_U32 (At_Five, 1, Value, Ok);
      Check ("U32 before the array rejected", not Ok);
   end;

   --  Week 2: Find_Child. A parent holding free(8), moov(16) with a
   --  nested trak(8) inside it, then mdat(10).
   declare
      Tree : constant Byte_Array :=
        [0, 0, 0, 8, 102, 114, 101, 101,
         0, 0, 0, 16, 109, 111, 111, 118,
         0, 0, 0, 8, 116, 114, 97, 107,
         0, 0, 0, 10, 109, 100, 97, 116, 1, 2];
      Found : Boolean;
   begin
      Find_Child (Tree, 1, Tree'Last, "free", H, Found);
      Check ("find the first child", Found and then H.Box_First = 1);

      Find_Child (Tree, 1, Tree'Last, "mdat", H, Found);
      Check ("find a later child", Found and then H.Box_First = 25
             and then H.Box_Last = 34 and then H.Payload_First = 33);

      Find_Child (Tree, 1, Tree'Last, "trak", H, Found);
      Check ("nested box is not a direct child", not Found);

      Find_Child (Tree, 1, Tree'Last, "moov", H, Found);
      Check ("find the parent", Found);
      Find_Child (Tree, H.Payload_First, H.Box_Last, "trak", H, Found);
      Check ("find inside the parent's payload", Found and then H.Box_First = 17);

      Find_Child (Tree, 1, Tree'Last, "stbl", H, Found);
      Check ("missing child not found", not Found);

      Find_Child (Tree, 9, 8, "moov", H, Found);
      Check ("empty range finds nothing", not Found);

      Find_Child (Tree, 1, 15, "moov", H, Found);
      Check ("child reaching past the range rejected", not Found);

      for I in 1 .. Tree'Last - 1 loop
         Find_Child (Tree (1 .. I), 1, I, "mdat", H, Found);
         Check ("tree truncated to" & I'Image, not Found);
      end loop;

      declare
         Bad : Byte_Array := Tree;
      begin
         Bad (4) := 0;
         Bad (1) := 16#7F#;  --  first box claims about 2 GB
         Find_Child (Bad, 1, Bad'Last, "mdat", H, Found);
         Check ("huge sibling stops the walk", not Found);

         Bad := Tree;
         Bad (4) := 3;  --  size 3 is smaller than a header
         Find_Child (Bad, 1, Bad'Last, "mdat", H, Found);
         Check ("sibling smaller than a header stops the walk", not Found);

         Bad := Tree;
         Bad (4) := 0;  --  size 0 swallows the rest of the range
         Find_Child (Bad, 1, Bad'Last, "mdat", H, Found);
         Check ("size-zero sibling hides later boxes", not Found);
      end;
   end;

   if Failures = 0 then
      Put_Line ("all ISOBMFF box reader tests passed");
   else
      Put_Line (Failures'Image & " box reader test failure(s)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Box_Reader_Tests;
