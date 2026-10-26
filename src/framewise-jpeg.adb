--  Week 1 M2: defensive baseline JPEG SOF0 header scanning.
--  DQT, DHT, entropy decoding and pixels follow in later weeks.
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
      pragma Unreferenced (Data, H);
   begin
      Pixels := [others => 0];
      Ok := False; --  Intentionally unimplemented in week 1.
   end Decode;

end Framewise.JPEG;
