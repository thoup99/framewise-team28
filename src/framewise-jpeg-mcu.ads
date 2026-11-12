
with Framewise.JPEG.IDCT;

package Framewise.JPEG.MCU with SPARK_Mode is

   --  One 16x16 MCU containing RGBA pixel values.
   --  Each pixel uses four bytes: red, green, blue, alpha.
   type RGBA_Block is array (Natural range 0 .. 1_023) of Byte;

   --  Combine four Y blocks and one Cb/Cr block each.
   --  The input uses 4:2:0 chroma sampling.
   procedure Compose_420
     (Y_Top_Left     : Framewise.JPEG.IDCT.Sample_Block;
      Y_Top_Right    : Framewise.JPEG.IDCT.Sample_Block;
      Y_Bottom_Left  : Framewise.JPEG.IDCT.Sample_Block;
      Y_Bottom_Right : Framewise.JPEG.IDCT.Sample_Block;
      Cb             : Framewise.JPEG.IDCT.Sample_Block;
      Cr             : Framewise.JPEG.IDCT.Sample_Block;
      Pixels         : out RGBA_Block);

end Framewise.JPEG.MCU;
