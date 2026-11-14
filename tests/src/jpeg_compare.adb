with Ada.Command_Line;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Framewise.JPEG;

procedure JPEG_Compare is
   package J renames Framewise.JPEG;
   package IO renames Ada.Streams.Stream_IO;
   use type Ada.Streams.Stream_Element_Offset;
   use type J.Byte;

   function Read_File (Name : String) return J.Byte_Array;
   function Read_File (Name : String) return J.Byte_Array is
      F : IO.File_Type;
   begin
      IO.Open (F, IO.In_File, Name);
      declare
         Raw : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (IO.Size (F)));
         Last : Ada.Streams.Stream_Element_Offset;
         Data : J.Byte_Array (1 .. Natural (Raw'Length));
      begin
         IO.Read (F, Raw, Last);
         IO.Close (F);
         pragma Assert (Last = Raw'Last);
         for I in Data'Range loop
            Data (I) := J.Byte (Raw (Ada.Streams.Stream_Element_Offset (I)));
         end loop;
         return Data;
      end;
   end Read_File;

   Data : constant J.Byte_Array := Read_File (Ada.Command_Line.Argument (1));
   Reference : constant J.Byte_Array := Read_File (Ada.Command_Line.Argument (2));
   H : J.Header;
   Ok : Boolean;
begin
   J.Read_Header (Data, H, Ok);
   pragma Assert (Ok);
   declare
      Pixels : J.Byte_Array (7 .. 6 + H.Width * H.Height * 4);
      Maximum, Difference : Natural := 0;
      Total : Long_Long_Integer := 0;
      procedure Check_Truncation (Length : Natural);
      procedure Check_Truncation (Length : Natural) is
      begin
         J.Decode (Data (Data'First .. Data'First + Length - 1), H, Pixels, Ok);
         pragma Assert (not Ok, "truncated JPEG accepted");
      end Check_Truncation;
   begin
      J.Decode (Data, H, Pixels, Ok);
      pragma Assert (Ok, "decode failed");
      pragma Assert (Pixels'Length = Reference'Length);
      for I in Reference'Range loop
         Difference := abs (Integer (Reference (I)) - Integer (Pixels (I + 6)));
         Maximum := Natural'Max (Maximum, Difference);
         Total := Total + Long_Long_Integer (Difference);
      end loop;
      Ada.Text_IO.Put_Line
        ("max" & Maximum'Image & " mean" &
         Long_Float'Image (Long_Float (Total) / Long_Float (Reference'Length)));
      pragma Assert (Maximum <= 3);
      pragma Assert (Long_Float (Total) / Long_Float (Reference'Length) < 0.5);

      --  Fixed points throughout the entropy stream and every marker boundary.
      for I in 0 .. 20 loop
         Check_Truncation (I * (Data'Length - 1) / 20);
      end loop;
      for I in Data'First .. Data'Last - 1 loop
         if Data (I) = 16#FF# and then Data (I + 1) /= 0 then
            Check_Truncation (I - Data'First);
         end if;
      end loop;
      declare
         Shifted : J.Byte_Array (11 .. Data'Length + 10) := Data;
      begin
         J.Decode (Shifted, H, Pixels, Ok);
         pragma Assert (Ok, "non-one-based input failed");
         for I in Shifted'Range loop
            Shifted (I) := Shifted (I) xor 16#80#;
            J.Decode (Shifted, H, Pixels, Ok);
            Shifted (I) := Shifted (I) xor 16#80#;
         end loop;
      end;
      Ada.Text_IO.Put_Line ("PASS: comparison, truncation and damaged inputs");
   end;
end JPEG_Compare;
