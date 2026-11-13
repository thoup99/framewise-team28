with Framewise.JPEG.Bits;
with Framewise.JPEG.Blocks;
with Framewise.JPEG.Tables;
with Framewise.JPEG.IDCT;
with Framewise.JPEG.MCU;

--  Baseline 4:2:0 JPEG header scanning and MCU decoding.
package body Framewise.JPEG with SPARK_Mode is

   function U16 (Data : Byte_Array; P : Positive) return Natural is
     (Natural (Data (P)) * 256 + Natural (Data (P + 1)))
   with Pre => P < Data'Last;

   procedure Read_Header (Data : Byte_Array; H : out Header; Ok : out Boolean) is
      P      : Natural := Data'First;
      Marker : Byte;
      Count  : Natural;
      Size   : Natural;
      W, Y   : Natural;
   begin
      H := (others => <>);
      Ok := False;

      if Data'Length < 4 then
         return;
      end if;
      if Data (P) /= 16#FF# or else Data (P + 1) /= 16#D8# then
         return;
      end if;
      P := P + 2;

      while P < Data'Last loop
         if Data (P) /= 16#FF# then
            return;
         end if;

         --  JPEG permits runs of FF padding bytes before a marker.
         while P < Data'Last and then Data (P) = 16#FF# loop
            P := P + 1;
         end loop;
         if P >= Data'Last or else Data (P) = 16#00# then
            return;
         end if;
         Marker := Data (P);
         P := P + 1;

         --  End of image / start of scan / unsupported SOF cannot
         --  precede the baseline SOF0 header we are looking for.
         if Marker = 16#D9# or else Marker = 16#DA# then
            return;
         end if;
         if Marker /= 16#C0#
           and then Marker /= 16#DB# and then Marker /= 16#C4#
           and then Marker /= 16#DD# and then Marker /= 16#FE#
           and then Marker not in 16#E0# .. 16#EF#
         then
            return;
         end if;

         --  Segment length includes its own two-byte length field.
         if P >= Data'Last then
            return;
         end if;
         Size := U16 (Data, Positive (P));
         if Size < 2 or else Size > Data'Last - P + 1 then
            return;
         end if;

         if Marker = 16#C0# then
            --  SOF0 = length(2), precision(1), height(2), width(2),
            --  component count(1), then three bytes per component.
            if Size < 11 or else Data (P + 2) /= 8 then
               return;
            end if;
            Count := Natural (Data (P + 7));
            if Count /= 3 or else Size /= 8 + 3 * Count then
               return;
            end if;

            Y := U16 (Data, Positive (P + 3));
            W := U16 (Data, Positive (P + 5));
            if W not in 1 .. Max_Width or else Y not in 1 .. Max_Height then
               return;
            end if;

            --  A proxy must be 8-bit YCbCr 4:2:0: Y=2x2, Cb/Cr=1x1.
            --  Check identifiers are 1,2,3 and quantizer IDs 0..3.
            if Data (P + 8) /= 1 or else Data (P + 9) /= 16#22#
              or else Data (P + 10) > 3
              or else Data (P + 11) /= 2 or else Data (P + 12) /= 16#11#
              or else Data (P + 13) > 3
              or else Data (P + 14) /= 3 or else Data (P + 15) /= 16#11#
              or else Data (P + 16) > 3
            then
               return;
            end if;

            H := (Width => W, Height => Y, Components => Count);
            Ok := True;
            return;
         end if;

         --  All arithmetic is bounded by the validated segment end.
         if Size = Data'Last - P + 1 then
            return; --  Segment exhausted the input without SOF0.
         end if;
         P := P + Size;
      end loop;
   end Read_Header;

   procedure Decode (Data : Byte_Array; H : Header; Pixels : out Byte_Array; Ok : out Boolean)
   is
      Q : Tables.Quantization_Tables;
      HT : Tables.Huffman_Tables;
      type Selector_Array is array (Positive range 1 .. 3) of Tables.Table_ID;
      Quant, DC, AC : Selector_Array := [others => 0];
      type Predictor_Array is array (Positive range 1 .. 3) of Integer;
      Predictors : Predictor_Array := [others => 0];
      type Sample_Array is array (Positive range 1 .. 6) of IDCT.Sample_Block;
      Samples : Sample_Array := [others => [others => 0]];
      Coefficients : Blocks.Coefficient_Array;
      Tile : MCU.RGBA_Block;
      State : Bits.Reader;
      Actual : Header;
      Good : Boolean;
      Have_Frame : Boolean := False;
      P : Natural := Data'First;
      Size, Last, Scan_First : Natural;
      Code : Byte;
      Restart_Interval : Natural := 0;
      Restart_Number : Natural := 0;
      MCU_Count : Natural := 0;
      Columns : constant Positive := (H.Width + 15) / 16;
      Rows : constant Positive := (H.Height + 15) / 16;
      Component : Positive;

      procedure Read_Image (Success : out Boolean);
      procedure Read_Image (Success : out Boolean) is
      begin
         Success := False;
         Bits.Start (State);
         for Row in 0 .. Rows - 1 loop
            for Column in 0 .. Columns - 1 loop
               for B in 1 .. 6 loop
                  Component := (if B <= 4 then 1 else B - 3);
                  Blocks.Decode_Block
                    (Data (Scan_First .. Data'Last), State,
                     HT (Tables.DC, DC (Component)), HT (Tables.AC, AC (Component)),
                     Predictors (Component), Coefficients, Good);
                  if not Good then
                     return;
                  end if;
                  IDCT.Decode (Coefficients, Q.Values (Quant (Component)), Samples (B), Good);
                  if not Good then
                     return;
                  end if;
               end loop;
               MCU.Compose_420
                 (Samples (1), Samples (2), Samples (3), Samples (4),
                  Samples (5), Samples (6), Tile);
               for Y in 0 .. 15 loop
                  for X in 0 .. 15 loop
                     if Row * 16 + Y < H.Height and then Column * 16 + X < H.Width then
                        for Channel in 0 .. 3 loop
                           Pixels (Pixels'First +
                             ((Row * 16 + Y) * H.Width + Column * 16 + X) * 4 + Channel) :=
                               Tile ((Y * 16 + X) * 4 + Channel);
                        end loop;
                     end if;
                  end loop;
               end loop;
               MCU_Count := MCU_Count + 1;
               if Restart_Interval > 0 and then MCU_Count mod Restart_Interval = 0
                 and then MCU_Count < Rows * Columns
               then
                  Bits.Finish_Interval
                    (Data (Scan_First .. Data'Last), State,
                     Byte (16#D0# + Restart_Number), Good);
                  if not Good then
                     return;
                  end if;
                  Scan_First := Scan_First + Bits.Consumed (State);
                  Restart_Number := (Restart_Number + 1) mod 8;
                  Predictors := [others => 0];
                  Bits.Start (State);
               end if;
            end loop;
         end loop;
         Bits.Finish_Interval
           (Data (Scan_First .. Data'Last), State, 16#D9#, Success);
      end Read_Image;
   begin
      Pixels := [others => 0];
      Ok := False;
      Read_Header (Data, Actual, Good);
      if not Good or else Actual /= H or else H.Components /= 3 then
         return;
      end if;
      P := P + 2;
      while P < Data'Last loop
         if Data (P) /= 16#FF# then
            return;
         end if;
         while P < Data'Last and then Data (P) = 16#FF# loop
            P := P + 1;
         end loop;
         Code := Data (P);
         if P >= Data'Last then
            return;
         end if;
         P := P + 1;
         if P >= Data'Last then
            return;
         end if;
         Size := U16 (Data, P);
         if Size < 2 or else Size > Data'Last - P + 1 then
            return;
         end if;
         Last := P + Size - 1;
         case Code is
            when 16#DB# =>
               Tables.Read_DQT (Data (P + 2 .. Last), Q, Good);
               if not Good then
                  return;
               end if;
            when 16#C4# =>
               Tables.Read_DHT (Data (P + 2 .. Last), HT, Good);
               if not Good then
                  return;
               end if;
            when 16#C0# =>
               if Have_Frame or else Size /= 17 then
                  return;
               end if;
               --  Read_Header already checked dimensions, IDs and sampling.
               for C in 1 .. 3 loop
                  Quant (C) := Natural (Data (P + 10 + (C - 1) * 3));
               end loop;
               Have_Frame := True;
            when 16#DD# =>
               if Size /= 4 then
                  return;
               end if;
               Restart_Interval := U16 (Data, P + 2);
            when 16#DA# =>
               if not Have_Frame or else Size /= 12 or else Data (P + 2) /= 3
                 or else Data (P + 9) /= 0 or else Data (P + 10) /= 63
                 or else Data (P + 11) /= 0
               then
                  return;
               end if;
               for C in 1 .. 3 loop
                  if Data (P + 3 + (C - 1) * 2) /= Byte (C)
                    or else Natural (Data (P + 4 + (C - 1) * 2)) / 16 > 3
                    or else Natural (Data (P + 4 + (C - 1) * 2)) mod 16 > 3
                  then
                     return;
                  end if;
                  DC (C) := Natural (Data (P + 4 + (C - 1) * 2)) / 16;
                  AC (C) := Natural (Data (P + 4 + (C - 1) * 2)) mod 16;
                  if not Q.Present (Quant (C)) or else not HT (Tables.DC, DC (C)).Present
                    or else not HT (Tables.AC, AC (C)).Present
                  then
                     return;
                  end if;
               end loop;
               Scan_First := Last + 1;
               Read_Image (Ok);
               if not Ok then
                  Pixels := [others => 0];
               end if;
               return;
            when 16#E0# .. 16#EF# | 16#FE# =>
               null;
            when others =>
               return;
         end case;
         exit when Last = Data'Last;
         P := Last + 1;
      end loop;
   end Decode;

end Framewise.JPEG;
