
package body Framewise.JPEG.IDCT with SPARK_Mode is

   subtype Block_Index is Natural range 0 .. 63;

   type Zigzag_Map is array (Block_Index) of Block_Index;

   --  Convert JPEG zigzag positions into row-major 8x8 positions.
   Zigzag_To_Natural : constant Zigzag_Map :=
     [0, 1, 8, 16, 9, 2, 3, 10,
      17, 24, 32, 25, 18, 11, 4, 5,
      12, 19, 26, 33, 40, 48, 41, 34,
      27, 20, 13, 6, 7, 14, 21, 28,
      35, 42, 49, 56, 57, 50, 43, 36,
      29, 22, 15, 23, 30, 37, 44, 51,
      58, 59, 52, 45, 38, 31, 39, 46,
      53, 60, 61, 54, 47, 55, 62, 63];

   --  Fixed-point cosine basis scaled by 4096.
   --  The first frequency includes the 1/sqrt(2) factor.
   type Basis_Matrix is
     array (Natural range 0 .. 7, Natural range 0 .. 7)
     of Integer;

   Basis : constant Basis_Matrix :=
     [[2896,  4017,  3784,  3406,  2896,  2276,  1567,   799],
      [2896,  3406,  1567,  -799, -2896, -4017, -3784, -2276],
      [2896,  2276, -1567, -4017, -2896,   799,  3784,  3406],
      [2896,   799, -3784, -2276,  2896,  3406, -1567, -4017],
      [2896,  -799, -3784,  2276,  2896, -3406, -1567,  4017],
      [2896, -2276, -1567,  4017, -2896,  -799,  3784, -3406],
      [2896, -3406,  1567,   799, -2896,  4017, -3784,  2276],
      [2896, -4017,  3784, -3406,  2896, -2276,  1567,  -799]];

   type Wide_Block is
     array (Block_Index) of Long_Long_Integer;

   Divisor : constant Long_Long_Integer :=
     4 * 4096 * 4096;

   procedure Decode
     (Coefficients : Framewise.JPEG.Blocks.Coefficient_Array;
      Quantization : Framewise.JPEG.Tables.Quantizer;
      Pixels       : out Sample_Block;
      Ok           : out Boolean)
   is
      Values : Wide_Block := [others => 0];
      Work   : Wide_Block := [others => 0];
      Total  : Long_Long_Integer;
      Sample : Long_Long_Integer;
   begin
      Pixels := [others => 0];
      Ok := False;

      --  Validate and dequantize the coefficients.
      for Z in Block_Index loop
         if Quantization (Z) = 0
           or else Coefficients (Z) not in -2048 .. 2047
         then
            return;
         end if;

         Values (Zigzag_To_Natural (Z)) :=
           Long_Long_Integer (Coefficients (Z)) *
           Long_Long_Integer (Quantization (Z));
      end loop;

      --  First IDCT pass: transform each row.
      for Row in 0 .. 7 loop
         for X in 0 .. 7 loop
            Total := 0;

            for U in 0 .. 7 loop
               Total := Total +
                 Values (Row * 8 + U) *
                 Long_Long_Integer (Basis (X, U));
            end loop;

            Work (Row * 8 + X) := Total;
         end loop;
      end loop;

      --  Second IDCT pass: transform each column.
      for Y in 0 .. 7 loop
         for X in 0 .. 7 loop
            Total := 0;

            for V in 0 .. 7 loop
               Total := Total +
                 Work (V * 8 + X) *
                 Long_Long_Integer (Basis (Y, V));
            end loop;

            --  Round the fixed-point result to the nearest integer.
            if Total >= 0 then
               Sample := (Total + Divisor / 2) / Divisor;
            else
               Sample := (Total - Divisor / 2) / Divisor;
            end if;

            --  JPEG samples are level-shifted by 128.
            Sample := Sample + 128;

            --  Clamp the result to the valid 8-bit range.
            if Sample < 0 then
               Pixels (Y * 8 + X) := 0;
            elsif Sample > 255 then
               Pixels (Y * 8 + X) := 255;
            else
               Pixels (Y * 8 + X) := Byte (Sample);
            end if;
         end loop;
      end loop;

      Ok := True;
   end Decode;

end Framewise.JPEG.IDCT;
