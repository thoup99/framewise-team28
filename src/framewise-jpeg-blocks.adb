package body Framewise.JPEG.Blocks with SPARK_Mode is

   procedure Decode_Symbol
     (Data   : Byte_Array;
      State  : in out Framewise.JPEG.Bits.Reader;
      Table  : Framewise.JPEG.Tables.Huffman_Table;
      Symbol : out Byte;
      Ok     : out Boolean);

   function Extend
     (Value : Natural;
      Size  : Natural) return Integer;

   procedure Decode_Symbol
     (Data   : Byte_Array;
      State  : in out Framewise.JPEG.Bits.Reader;
      Table  : Framewise.JPEG.Tables.Huffman_Table;
      Symbol : out Byte;
      Ok     : out Boolean)
   is
      Code : Natural range 0 .. 65_535 := 0;
      Bit  : Natural;
      Read_Ok : Boolean;
   begin
      Symbol := 0;
      Ok := False;

      if not Table.Present or else Table.Count = 0 then
         return;
      end if;

      for Length in 1 .. 16 loop
         Framewise.JPEG.Bits.Read_Bits
           (Data, State, 1, Bit, Read_Ok);

         if not Read_Ok then
            return;
         end if;

         Code := Code * 2 + Bit;

         for I in 1 .. Table.Count loop
            if Table.Lengths (I) = Length
              and then Table.Codes (I) = Code
            then
               Symbol := Table.Symbols (I);
               Ok := True;
               return;
            end if;
         end loop;
      end loop;
   end Decode_Symbol;

   function Extend
     (Value : Natural;
      Size  : Natural) return Integer
   is
      Threshold : Natural;
   begin
      if Size = 0 or else Size > 16 then
         return 0;
      end if;

      Threshold := 2 ** (Size - 1);

      if Value < Threshold then
         return Integer (Value) - Integer (2 ** Size - 1);
      else
         return Integer (Value);
      end if;
   end Extend;

   procedure Decode_Block
     (Data         : Byte_Array;
      State        : in out Framewise.JPEG.Bits.Reader;
      DC_Table     : Framewise.JPEG.Tables.Huffman_Table;
      AC_Table     : Framewise.JPEG.Tables.Huffman_Table;
      DC_Predictor : in out Integer;
      Coefficients : out Coefficient_Array;
      Ok           : out Boolean)
   is
      Symbol   : Byte;
      Symbol_Ok : Boolean;
      Bits     : Natural;
      Bits_Ok  : Boolean;
      Size     : Natural;
      Run      : Natural;
      DC_Change    : Integer;
      K        : Natural := 1;
   begin
      Coefficients := [others => 0];
      Ok := False;

      --  DC coefficient.
      Decode_Symbol
        (Data, State, DC_Table, Symbol, Symbol_Ok);

      if not Symbol_Ok then
         return;
      end if;

      Size := Natural (Symbol);

      if Size > 11 then
         return;
      end if;

      if Size = 0 then
         DC_Change := 0;
      else
         Framewise.JPEG.Bits.Read_Bits
           (Data, State, Size, Bits, Bits_Ok);

         if not Bits_Ok then
            return;
         end if;

         DC_Change := Extend (Bits, Size);
      end if;

      declare
         New_Predictor : constant Long_Long_Integer :=
           Long_Long_Integer (DC_Predictor) +
           Long_Long_Integer (DC_Change);
      begin
         if New_Predictor < Long_Long_Integer (Integer'First)
           or else New_Predictor > Long_Long_Integer (Integer'Last)
         then
            return;
         end if;

         DC_Predictor := Integer (New_Predictor);
      end;

      Coefficients (0) := DC_Predictor;

      --  AC coefficients.
      while K <= 63 loop
         Decode_Symbol
           (Data, State, AC_Table, Symbol, Symbol_Ok);

         if not Symbol_Ok then
            return;
         end if;

         --  End of block.
         if Symbol = 16#00# then
            Ok := True;
            return;
         end if;

         --  Sixteen zero coefficients.
         if Symbol = 16#F0# then
            if K > 48 then
               return;
            end if;

            K := K + 16;

         else
            Run := Natural (Symbol) / 16;
            Size := Natural (Symbol) mod 16;

            if Size = 0 or else Size > 10 then
               return;
            end if;

            if Run > 63 - K then
               return;
            end if;

            K := K + Run;

            Framewise.JPEG.Bits.Read_Bits
              (Data, State, Size, Bits, Bits_Ok);

            if not Bits_Ok then
               return;
            end if;

            Coefficients (K) := Extend (Bits, Size);
            K := K + 1;
         end if;
      end loop;

      Ok := True;
   end Decode_Block;

end Framewise.JPEG.Blocks;