
package body Framewise.JPEG.MCU with SPARK_Mode is

   --  Keep a calculated color value inside the byte range.
   function Clamp (Value : Integer) return Byte;

   function Clamp (Value : Integer) return Byte is
   begin
      if Value < 0 then
         return 0;
      elsif Value > 255 then
         return 255;
      else
         return Byte (Value);
      end if;
   end Clamp;

   --  Round a signed fixed-point value divided by 256.
   function Round_256 (Value : Integer) return Integer;

   function Round_256 (Value : Integer) return Integer is
   begin
      if Value >= 0 then
         return (Value + 128) / 256;
      else
         return -((-Value + 128) / 256);
      end if;
   end Round_256;

   procedure Compose_420
     (Y_Top_Left     : Framewise.JPEG.IDCT.Sample_Block;
      Y_Top_Right    : Framewise.JPEG.IDCT.Sample_Block;
      Y_Bottom_Left  : Framewise.JPEG.IDCT.Sample_Block;
      Y_Bottom_Right : Framewise.JPEG.IDCT.Sample_Block;
      Cb             : Framewise.JPEG.IDCT.Sample_Block;
      Cr             : Framewise.JPEG.IDCT.Sample_Block;
      Pixels         : out RGBA_Block)
   is
   begin
      for Y in 0 .. 15 loop
         for X in 0 .. 15 loop
            declare
               --  Position inside the selected 8x8 Y block.
               Y_Index : constant Natural :=
                 (Y mod 8) * 8 + (X mod 8);

               --  Chroma is stored at half resolution.
               --  Nearest-neighbor upsampling reuses each
               --  chroma sample for a 2x2 region.
               C_Index : constant Natural :=
                 (Y / 2) * 8 + (X / 2);

               --  Select the correct brightness block.
               Luma : constant Integer :=
                 (if Y < 8 and then X < 8 then
                     Integer (Y_Top_Left (Y_Index))
                  elsif Y < 8 then
                     Integer (Y_Top_Right (Y_Index))
                  elsif X < 8 then
                     Integer (Y_Bottom_Left (Y_Index))
                  else
                     Integer (Y_Bottom_Right (Y_Index)));

               Cb_Diff : constant Integer :=
                 Integer (Cb (C_Index)) - 128;

               Cr_Diff : constant Integer :=
                 Integer (Cr (C_Index)) - 128;

               --  Position in the RGBA output array.
               P : constant Natural := (Y * 16 + X) * 4;
            begin
               --  Convert YCbCr to RGB using fixed-point
               --  coefficients scaled by 256.
               Pixels (P) :=
                 Clamp (Luma + Round_256 (359 * Cr_Diff));

               Pixels (P + 1) :=
                 Clamp
                   (Luma -
                    Round_256 (88 * Cb_Diff + 183 * Cr_Diff));

               Pixels (P + 2) :=
                 Clamp (Luma + Round_256 (454 * Cb_Diff));

               --  The output is always fully opaque.
               Pixels (P + 3) := 255;
            end;
         end loop;
      end loop;
   end Compose_420;

end Framewise.JPEG.MCU;
