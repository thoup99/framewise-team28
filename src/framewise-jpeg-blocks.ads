with Framewise.JPEG.Bits;
with Framewise.JPEG.Tables;

package Framewise.JPEG.Blocks with SPARK_Mode is

   type Coefficient_Array is array (Natural range 0 .. 63) of Integer;

   procedure Decode_Block
     (Data         : Byte_Array;
      State        : in out Framewise.JPEG.Bits.Reader;
      DC_Table     : Framewise.JPEG.Tables.Huffman_Table;
      AC_Table     : Framewise.JPEG.Tables.Huffman_Table;
      DC_Predictor : in out Integer;
      Coefficients : out Coefficient_Array;
      Ok           : out Boolean);
   --  Coefficients are left in JPEG zigzag order.
   --  Dequantization and IDCT are Week 4 work.

end Framewise.JPEG.Blocks;