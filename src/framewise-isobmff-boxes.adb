package body Framewise.ISOBMFF.Boxes with SPARK_Mode is

   --  Shared overflow-checked big-endian reader. Handles both the 32-bit
   --  size field and the optional 64-bit largesize without 64-bit math.
   procedure Read_Unsigned
     (Data  : Byte_Array;
      At    : Positive;
      Count : Positive;
      Value : out Natural;
      Ok    : out Boolean)
   is
      Acc : Natural := 0;
   begin
      Value := 0;
      Ok := False;

      if At < Data'First or else At > Data'Last then
         return;
      end if;
      if Count > Data'Last - At + 1 then
         return;
      end if;

      for Offset in 0 .. Count - 1 loop
         declare
            Digit : constant Natural := Natural (Data (At + Offset));
         begin
            if Acc > (Natural'Last - Digit) / 256 then
               return;
            end if;
            Acc := Acc * 256 + Digit;
         end;
      end loop;

      Value := Acc;
      Ok := True;
   end Read_Unsigned;

   procedure Read_Box
     (Data      : Byte_Array;
      At        : Positive;
      File_Size : Natural;
      Header    : out Box_Header;
      Ok        : out Boolean)
   is
      Size32        : Natural;
      Total_Size    : Natural;
      Header_Length : Natural := 8;
      Good          : Boolean;
   begin
      Header := (others => <>);
      Ok := False;

      --  These checks ensure the complete basic 8-byte header exists.
      if At < Data'First or else At > Data'Last then
         return;
      end if;
      if Data'Last - At < 7 then
         return;
      end if;
      if At > File_Size or else File_Size - At < 7 then
         return;
      end if;

      Read_Unsigned (Data, At, 4, Size32, Good);
      if not Good then
         return;
      end if;

      if Size32 = 1 then
         Header_Length := 16;
         if Data'Last - At < 15 or else File_Size - At < 15 then
            return;
         end if;
         Read_Unsigned (Data, At + 8, 8, Total_Size, Good);
         if not Good then
            return;
         end if;
      elsif Size32 = 0 then
         Total_Size := File_Size - At + 1;
      else
         Total_Size := Size32;
      end if;

      if Total_Size < Header_Length
        or else Total_Size > File_Size - At + 1
      then
         return;
      end if;

      Header.Box_First := At;
      Header.Box_Last := At + (Total_Size - 1);
      Header.Header_Length := Header_Length;
      Header.Payload_Size := Total_Size - Header_Length;
      if Header.Payload_Size > 0 then
         Header.Payload_First := At + Header_Length;
      end if;
      for I in 1 .. 4 loop
         Header.Kind (I) := Character'Val (Integer (Data (At + 3 + I)));
      end loop;
      Ok := True;
   end Read_Box;

end Framewise.ISOBMFF.Boxes;
