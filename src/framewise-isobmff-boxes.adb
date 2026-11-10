package body Framewise.ISOBMFF.Boxes with SPARK_Mode is

   --  Shared overflow-checked big-endian reader. Handles both the 32-bit
   --  size field and the optional 64-bit largesize without 64-bit math.
   procedure Read_Unsigned
     (Data     : Byte_Array;
      Position : Positive;
      Count    : Positive;
      Value    : out Natural;
      Ok       : out Boolean);

   procedure Read_Unsigned
     (Data     : Byte_Array;
      Position : Positive;
      Count    : Positive;
      Value    : out Natural;
      Ok       : out Boolean)
   is
      Acc : Natural := 0;
   begin
      Value := 0;
      Ok := False;

      if Position < Data'First or else Position > Data'Last then
         return;
      end if;
      if Count > Data'Last - Position + 1 then
         return;
      end if;

      for Offset in 0 .. Count - 1 loop
         declare
            Digit : constant Natural := Natural (Data (Position + Offset));
         begin
            if Acc > (Natural'Last - Digit) / 256 then
               return;
            end if;
            Acc := Acc * 256 + Digit;
         end;
      end loop;

      Value := Acc;
      Ok := True;
   end Read_Unsigned;

   procedure Read_Box
     (Data      : Byte_Array;
      Position  : Positive;
      File_Size : Natural;
      Header    : out Box_Header;
      Ok        : out Boolean)
   is
      Size32        : Natural;
      Total_Size    : Natural;
      Header_Length : Natural := 8;
      Good          : Boolean;
   begin
      Header := (others => <>);
      Ok := False;

      --  These checks ensure the complete basic 8-byte header exists.
      if Position < Data'First or else Position > Data'Last then
         return;
      end if;
      if Data'Last - Position < 7 then
         return;
      end if;
      if Position > File_Size or else File_Size - Position < 7 then
         return;
      end if;

      Read_Unsigned (Data, Position, 4, Size32, Good);
      if not Good then
         return;
      end if;

      if Size32 = 1 then
         Header_Length := 16;
         if Data'Last - Position < 15 or else File_Size - Position < 15 then
            return;
         end if;
         Read_Unsigned (Data, Position + 8, 8, Total_Size, Good);
         if not Good then
            return;
         end if;
      elsif Size32 = 0 then
         Total_Size := File_Size - Position + 1;
      else
         Total_Size := Size32;
      end if;

      if Total_Size < Header_Length
        or else Total_Size > File_Size - Position + 1
      then
         return;
      end if;

      Header.Box_First := Position;
      Header.Box_Last := Position + (Total_Size - 1);
      Header.Header_Length := Header_Length;
      Header.Payload_Size := Total_Size - Header_Length;
      if Header.Payload_Size > 0 then
         Header.Payload_First := Position + Header_Length;
      end if;
      for I in 1 .. 4 loop
         Header.Kind (I) := Character'Val (Integer (Data (Position + 3 + I)));
      end loop;
      Ok := True;
   end Read_Box;

   --  Both only pick the byte count; Read_Unsigned does the real work,
   --  so there is one place where a bounds or overflow mistake can hide.
   procedure Read_U32
     (Data     : Byte_Array;
      Position : Positive;
      Value    : out Natural;
      Ok       : out Boolean)
   is
   begin
      Read_Unsigned (Data, Position, 4, Value, Ok);
   end Read_U32;

   procedure Read_U16
     (Data     : Byte_Array;
      Position : Positive;
      Value    : out Natural;
      Ok       : out Boolean)
   is
   begin
      Read_Unsigned (Data, Position, 2, Value, Ok);
   end Read_U16;

   procedure Find_Child
     (Data  : Byte_Array;
      First : Positive;
      Last  : Natural;
      Kind  : Box_Kind;
      Child : out Box_Header;
      Found : out Boolean)
   is
      Position : Positive := First;
      Good     : Boolean;
   begin
      --  No need to set Child here: Read_Box sets it on every call (to the
      --  empty header when it fails), and the reset after the loop covers
      --  the case where the loop never runs.
      Found := False;

      while Position <= Last loop
         --  Giving Last as File_Size keeps the child inside this range.
         Read_Box (Data, Position, Last, Child, Good);
         if not Good then
            return;
         end if;

         if Child.Kind = Kind then
            Found := True;
            return;
         end if;

         --  Checked first: the "+ 1" below could overflow at Natural'Last.
         exit when Child.Box_Last >= Last;

         --  Read_Box promises Box_Last >= Position, so this always moves
         --  forward. A hostile file cannot make this loop run forever.
         Position := Child.Box_Last + 1;

         --  Position started at First and only moves forward, so it is
         --  never before First. The prover needs this to prove the
         --  postcondition Child.Box_First >= First.
         pragma Loop_Invariant (Position >= First);
         pragma Loop_Variant (Increases => Position);
      end loop;

      Child := (others => <>);
   end Find_Child;

end Framewise.ISOBMFF.Boxes;
