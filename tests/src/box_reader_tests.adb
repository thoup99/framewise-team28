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

   if Failures = 0 then
      Put_Line ("all ISOBMFF box reader tests passed");
   else
      Put_Line (Failures'Image & " box reader test failure(s)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Box_Reader_Tests;
