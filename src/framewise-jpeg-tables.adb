package body Framewise.JPEG.Tables with SPARK_Mode is
   procedure Read_DQT
     (Payload : Byte_Array; Tables : in out Quantization_Tables; Ok : out Boolean)
   is
      Result : Quantization_Tables := Tables;
      Offset : Natural := 0;
      ID     : Table_ID;
   begin
      Ok := False;
      if Payload'Length = 0 then
         return;
      end if;
      while Offset < Payload'Length loop
         if Payload'Length - Offset < 65
           or else Payload (Payload'First + Offset) > 3
         then
            return;
         end if;
         ID := Natural (Payload (Payload'First + Offset));
         for I in Quantizer'Range loop
            declare
               Value : constant Byte := Payload (Payload'First + Offset + 1 + I);
            begin
               if Value = 0 then
                  return;
               end if;
               Result.Values (ID) (I) := Value;
            end;
         end loop;
         Result.Present (ID) := True;
         Offset := Offset + 65;
      end loop;
      Tables := Result;
      Ok := True;
   end Read_DQT;

   procedure Read_DHT
     (Payload : Byte_Array; Tables : in out Huffman_Tables; Ok : out Boolean)
   is
      Result : Huffman_Tables := Tables;
      Offset : Natural := 0;
      ID     : Table_ID;
      Kind   : Table_Class;
      Info   : Natural;
      T      : Huffman_Table;
      Total  : Natural;
      Code   : Natural;
      Index  : Positive;
      Seen   : array (Byte) of Boolean;
   begin
      Ok := False;
      if Payload'Length = 0 then
         return;
      end if;
      while Offset < Payload'Length loop
         if Payload'Length - Offset < 17 then
            return;
         end if;
         Info := Natural (Payload (Payload'First + Offset));
         if Info / 16 > 1 or else Info mod 16 > 3 then
            return;
         end if;
         ID := Info mod 16;
         Kind := (if Info / 16 = 0 then DC else AC);
         T := (others => <>);
         Total := 0;
         for L in T.Counts'Range loop
            T.Counts (L) := Natural (Payload (Payload'First + Offset + L));
            Total := Total + T.Counts (L);
         end loop;
         Offset := Offset + 17;
         if Total = 0 or else Total > 256 or else Total > Payload'Length - Offset then
            return;
         end if;
         Code := 0;
         Index := 1;
         Seen := [others => False];
         for L in T.Counts'Range loop
            --  Equality would assign the forbidden all-ones code.
            if Code + T.Counts (L) >= 2 ** L then
               return;
            end if;
            for J in 1 .. T.Counts (L) loop
               declare
                  Symbol : constant Byte := Payload (Payload'First + Offset);
                  Run    : constant Natural := Natural (Symbol) / 16;
                  Size   : constant Natural := Natural (Symbol) mod 16;
               begin
                  if Seen (Symbol)
                    or else (Kind = DC and then Symbol > 11)
                    or else (Kind = AC and then
                      (Size > 10 or else (Size = 0 and then Run /= 0 and then Run /= 15)))
                  then
                     return;
                  end if;
                  Seen (Symbol) := True;
                  T.Symbols (Index) := Symbol;
                  T.Codes (Index) := Code;
                  T.Lengths (Index) := L;
                  Offset := Offset + 1;
                  Index := Index + 1;
                  Code := Code + 1;
               end;
            end loop;
            Code := Code * 2;
         end loop;
         T.Count := Total;
         T.Present := True;
         Result (Kind, ID) := T;
      end loop;
      Tables := Result;
      Ok := True;
   end Read_DHT;
end Framewise.JPEG.Tables;
