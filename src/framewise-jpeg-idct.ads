
with Framewise.JPEG.Blocks;
with Framewise.JPEG.Tables;

package Framewise.JPEG.IDCT with SPARK_Mode is

   --  One decoded 8x8 block of pixel samples.
   type Sample_Block is array (Natural range 0 .. 63) of Byte;

   procedure Decode
     (Coefficients : Framewise.JPEG.Blocks.Coefficient_Array;
      Quantization : Framewise.JPEG.Tables.Quantizer;
      Pixels       : out Sample_Block;
      Ok           : out Boolean);

   --  Input coefficients and quantization values are in zigzag order.
   --  Output samples are row-major, with values from 0 through 255.
   --  Invalid quantization values or coefficients return Ok = False.

end Framewise.JPEG.IDCT;
