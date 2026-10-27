--  Pair M week 1: SOF0 marker/header tests, independent of the decoder.
with Ada.Command_Line;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Framewise.JPEG;

procedure JPEG_Header_Tests is
   use Framewise.JPEG;
   use Ada.Text_IO;

   Failures : Natural := 0;
   H       : Header;
   Ok      : Boolean;

   --  SOI, small APP0, SOF0 960x540, YCbCr 4:2:0.
   Sample : constant Byte_Array :=
     [16#FF#, 16#D8#,
      16#FF#, 16#E0#, 16#00#, 16#04#, 16#00#, 16#00#,
      16#FF#, 16#C0#, 16#00#, 16#11#, 16#08#,
      16#02#, 16#1C#, 16#03#, 16#C0#, 16#03#,
      16#01#, 16#22#, 16#00#,
      16#02#, 16#11#, 16#01#,
      16#03#, 16#11#, 16#01#];

   procedure Check (Message : String; Condition : Boolean);
   procedure Check_File (Filename : String);

   procedure Check (Message : String; Condition : Boolean) is
   begin
      Put_Line ((if Condition then "PASS " else "FAIL ") & Message);
      if not Condition then
         Failures := Failures + 1;
      end if;
   end Check;

   procedure Check_File (Filename : String) is
      use Ada.Streams;
      use type Ada.Streams.Stream_IO.Count;
      File   : Ada.Streams.Stream_IO.File_Type;
   begin
      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Filename);
      declare
         Length : constant Ada.Streams.Stream_IO.Count :=
           Ada.Streams.Stream_IO.Size (File);
      begin
         if Length < 1 or else Length > 8_000_000 then
            Check ("reference JPEG has bounded length", False);
         else
            declare
               Raw  : Stream_Element_Array (1 .. Stream_Element_Offset (Length));
               Last : Stream_Element_Offset;
            begin
               Ada.Streams.Stream_IO.Read (File, Raw, Last);
               declare
                  Data : Byte_Array (1 .. Natural (Last));
               begin
                  for I in Data'Range loop
                     Data (I) := Byte (Raw (Stream_Element_Offset (I)));
                  end loop;
                  Read_Header (Data, H, Ok);
                  Check ("real proxy JPEG is 960x540 YCbCr 4:2:0",
                         Ok and then H.Width = 960 and then H.Height = 540
                         and then H.Components = 3);
               end;
            end;
         end if;
      end;
      Ada.Streams.Stream_IO.Close (File);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         Check ("could read reference JPEG", False);
   end Check_File;

begin
   Read_Header (Sample, H, Ok);
   Check ("valid baseline 4:2:0 header", Ok and then H.Width = 960
          and then H.Height = 540 and then H.Components = 3);

   for N in 1 .. Sample'Last - 1 loop
      Read_Header (Sample (1 .. N), H, Ok);
      Check ("truncated SOF0 prefix" & N'Image, not Ok);
   end loop;

   declare
      Offset_Data : Byte_Array (42 .. 42 + Sample'Length - 1);
   begin
      for I in Sample'Range loop
         Offset_Data (I + 41) := Sample (I);
      end loop;
      Read_Header (Offset_Data, H, Ok);
      Check ("non-one-based input", Ok and then H.Width = 960);
   end;

   declare
      Wrong : Byte_Array := Sample;
   begin
      Wrong (1) := 0;
      Read_Header (Wrong, H, Ok);
      Check ("missing SOI rejected", not Ok);

      Wrong := Sample;
      Wrong (5) := 0;
      Wrong (6) := 1;
      Read_Header (Wrong, H, Ok);
      Check ("APP segment length underflow rejected", not Ok);

      Wrong := Sample;
      Wrong (6) := 16#FF#;
      Read_Header (Wrong, H, Ok);
      Check ("APP segment beyond buffer rejected", not Ok);

      Wrong := Sample;
      Wrong (10) := 16#C2#;
      Read_Header (Wrong, H, Ok);
      Check ("progressive frame rejected", not Ok);

      Wrong := Sample;
      Wrong (13) := 12;
      Read_Header (Wrong, H, Ok);
      Check ("12-bit sample precision rejected", not Ok);

      Wrong := Sample;
      Wrong (20) := 16#11#;
      Read_Header (Wrong, H, Ok);
      Check ("non-4:2:0 Y sampling rejected", not Ok);

      Wrong := Sample;
      Wrong (17) := 16#81#;  --  width 897; still valid
      Read_Header (Wrong, H, Ok);
      Check ("noncanonical but bounded width accepted", Ok and then H.Width = 897);

      Wrong := Sample;
      Wrong (16) := 16#07#;
      Wrong (17) := 16#81#;  --  width 1921
      Read_Header (Wrong, H, Ok);
      Check ("width exceeding Max_Width rejected", not Ok);

      Wrong := Sample;
      Wrong (12) := 16#10#;  --  bad SOF0 length
      Read_Header (Wrong, H, Ok);
      Check ("inconsistent SOF0 size rejected", not Ok);

      Wrong := Sample;
      Wrong (18) := 1;
      Read_Header (Wrong, H, Ok);
      Check ("non-YCbCr component count rejected", not Ok);
   end;

   if Ada.Command_Line.Argument_Count > 0 then
      Check_File (Ada.Command_Line.Argument (1));
   end if;

   if Failures /= 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end JPEG_Header_Tests;