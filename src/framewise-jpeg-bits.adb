package body Framewise.JPEG.Bits with SPARK_Mode is
   procedure Start (State : out Reader) is
   begin
      State := (others => <>);
   end Start;

   function Failed (State : Reader) return Boolean is (State.Error);
   function Marker (State : Reader) return Byte is (State.Stop_Code);
   function Consumed (State : Reader) return Natural is (State.Offset);

   procedure Read_Bits
     (Data : Byte_Array; State : in out Reader; Count : Natural;
      Value : out Natural; Ok : out Boolean)
   is
      B      : Byte;
      Result : Natural := 0;
   begin
      Value := 0;
      Ok := False;
      if State.Error then
         return;
      end if;
      for I in 1 .. Count loop
         if State.Remaining = 0 then
            if State.Offset >= Data'Length then
               State.Error := True;
               return;
            end if;
            B := Data (Data'First + State.Offset);
            State.Offset := State.Offset + 1;
            if B = 16#FF# then
               if State.Offset >= Data'Length then
                  State.Error := True;
                  return;
               end if;
               B := Data (Data'First + State.Offset);
               State.Offset := State.Offset + 1;
               --  Skip marker fill bytes, but never past the slice.
               while B = 16#FF# loop
                  if State.Offset >= Data'Length then
                     State.Error := True;
                     return;
                  end if;
                  B := Data (Data'First + State.Offset);
                  State.Offset := State.Offset + 1;
                  if B = 0 then
                     --  FF FF 00 is not a stuffed entropy byte.
                     State.Error := True;
                     return;
                  end if;
               end loop;
               if B /= 0 then
                  State.Stop_Code := B;
                  State.Error := True;
                  return;
               end if;
               B := 16#FF#;
            end if;
            State.Current := Natural (B);
            State.Remaining := 8;
         end if;
         State.Remaining := State.Remaining - 1;
         Result := Result * 2 + (State.Current / 2 ** State.Remaining) mod 2;
      end loop;
      Value := Result;
      Ok := True;
   end Read_Bits;
   procedure Finish_Interval
     (Data : Byte_Array; State : in out Reader;
      Expected : Byte; Ok : out Boolean)
   is
      B : Byte;
   begin
      Ok := False;
      if State.Error or else
        State.Current mod 2 ** State.Remaining /= 2 ** State.Remaining - 1
      then
         return;
      end if;
      if State.Offset >= Data'Length
        or else Data (Data'First + State.Offset) /= 16#FF#
      then
         return;
      end if;
      loop
         State.Offset := State.Offset + 1;
         if State.Offset >= Data'Length then
            return;
         end if;
         B := Data (Data'First + State.Offset);
         exit when B /= 16#FF#;
      end loop;
      State.Offset := State.Offset + 1;
      State.Remaining := 0;
      Ok := B = Expected;
   end Finish_Interval;
end Framewise.JPEG.Bits;
