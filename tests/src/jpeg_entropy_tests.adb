with Ada.Command_Line;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Framewise.JPEG.Bits;
with Framewise.JPEG.Tables;

procedure JPEG_Entropy_Tests is
   use Framewise.JPEG;
   use Framewise.JPEG.Bits;
   use Framewise.JPEG.Tables;
   Q : Quantization_Tables;
   H : Huffman_Tables;
   S : Reader;
   Ok : Boolean;
   Value : Natural;
   Failures : Natural := 0;
   DQT : Byte_Array (1 .. 130) := [others => 1];
   DHT : Byte_Array (1 .. 20) := [others => 0];

   procedure Check (Label : String; Pass : Boolean);
   procedure Check_File (Filename : String);

   procedure Check (Label : String; Pass : Boolean) is
   begin
      if not Pass then
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL " & Label);
      end if;
   end Check;

   procedure Check_File (Filename : String) is
      use Ada.Streams;
      File : Stream_IO.File_Type;
   begin
      Stream_IO.Open (File, Stream_IO.In_File, Filename);
      if Stream_IO.Size (File) not in 1 .. 8_000_000 then
         Stream_IO.Close (File);
         Check ("bounded file size", False);
         return;
      end if;
      declare
         Raw : Stream_Element_Array (1 .. Stream_Element_Offset (Stream_IO.Size (File)));
         Last : Stream_Element_Offset;
         P : Natural := 3;
         Size : Natural;
         Tag : Byte;
         Found_Q, Found_H, Found_Scan : Boolean := False;
      begin
         Stream_IO.Read (File, Raw, Last);
         declare
            Data : Byte_Array (1 .. Natural (Last));
         begin
            for I in Data'Range loop
               Data (I) := Byte (Raw (Stream_Element_Offset (I)));
            end loop;
            Check ("SOI", Data'Length >= 2 and then Data (1 .. 2) = [16#FF#, 16#D8#]);
            while P < Data'Last loop
               Check ("marker prefix", Data (P) = 16#FF#);
               exit when Data (P) /= 16#FF#;
               while P < Data'Last and then Data (P) = 16#FF# loop
                  P := P + 1;
               end loop;
               Tag := Data (P);
               P := P + 1;
               exit when P >= Data'Last;
               Size := Natural (Data (P)) * 256 + Natural (Data (P + 1));
               exit when Size < 2 or else Size > Data'Last - P + 1;
               if Tag = 16#DB# then
                  Read_DQT (Data (P + 2 .. P + Size - 1), Q, Ok);
                  Check ("real DQT", Ok);
                  Found_Q := True;
               elsif Tag = 16#C4# then
                  Read_DHT (Data (P + 2 .. P + Size - 1), H, Ok);
                  Check ("real DHT", Ok);
                  Found_H := True;
               elsif Tag = 16#DA# then
                  Found_Scan := True;
                  Start (S);
                  loop
                     Read_Bits (Data (P + Size .. Data'Last), S, 8, Value, Ok);
                     exit when not Ok;
                  end loop;
                  Check ("real entropy reaches EOI", Marker (S) = 16#D9#);
                  exit;
               end if;
               P := P + Size;
            end loop;
            Check ("real JPEG tables and scan found", Found_Q and Found_H and Found_Scan);
         end;
      end;
      Stream_IO.Close (File);
   end Check_File;

begin
   DQT (1) := 0;
   DQT (66) := 3;
   for I in 0 .. 63 loop
      DQT (2 + I) := Byte (I + 1);
   end loop;
   Read_DQT (DQT, Q, Ok);
   Check ("multiple DQT tables, zigzag order", Ok and then Q.Present (0)
          and then Q.Present (3) and then Q.Values (0) (63) = 64);
   for N in 0 .. 64 loop
      declare
         Before : constant Quantization_Tables := Q;
      begin
         Read_DQT (DQT (1 .. N), Q, Ok);
         Check ("truncated DQT atomic", not Ok and then Q = Before);
      end;
   end loop;
   DQT (130) := 0;
   declare
      Before : constant Quantization_Tables := Q;
   begin
      Read_DQT (DQT, Q, Ok);
      Check ("zero quantizer atomic", not Ok and then Q = Before);
   end;
   DQT (130) := 1;
   DQT (1) := 16#10#;
   Read_DQT (DQT, Q, Ok);
   Check ("16-bit DQT rejected", not Ok);
   DQT (1) := 4;
   Read_DQT (DQT, Q, Ok);
   Check ("invalid DQT ID", not Ok);

   --  Codes 0, 100, 101: counts at lengths one and three.
   DHT (2) := 1;
   DHT (4) := 2;
   DHT (18 .. 20) := [0, 1, 2];
   Read_DHT (DHT, H, Ok);
   Check ("canonical Huffman codes", Ok and then H (DC, 0).Count = 3
          and then H (DC, 0).Codes (1 .. 3) = [0, 4, 5]
          and then H (DC, 0).Lengths (1 .. 3) = [1, 3, 3]);
   for N in 0 .. 19 loop
      declare
         Before : constant Huffman_Tables := H;
      begin
         Read_DHT (DHT (1 .. N), H, Ok);
         Check ("truncated DHT atomic", not Ok and then H = Before);
      end;
   end loop;
   declare
      Shifted : Byte_Array (Positive'Last - 19 .. Positive'Last) := DHT;
   begin
      Read_DHT (Shifted, H, Ok);
      Check ("high-bound DHT", Ok);
      Shifted (Shifted'First) := 16#10#;
      Read_DHT (DHT & Shifted, H, Ok);
      Check ("multiple DHT definitions", Ok and then H (AC, 0).Present);
   end;
   DHT (2) := 2;
   Read_DHT (DHT, H, Ok);
   Check ("all-ones / oversubscribed tree rejected", not Ok);
   DHT (2) := 1;
   DHT (20) := 12;
   Read_DHT (DHT, H, Ok);
   Check ("invalid baseline DC symbol", not Ok);
   DHT (20) := 1;
   Read_DHT (DHT, H, Ok);
   Check ("duplicate symbol", not Ok);
   DHT (1) := 16#10#;
   DHT (20) := 16#20#;
   Read_DHT (DHT, H, Ok);
   Check ("invalid AC zero size", not Ok);
   DHT (20) := 16#F0#;
   Read_DHT (DHT, H, Ok);
   Check ("AC EOB and ZRL accepted", Ok);
   DHT (1) := 16#20#;
   Read_DHT (DHT, H, Ok);
   Check ("invalid class", not Ok);
   DHT := [others => 0];
   Read_DHT (DHT (1 .. 17), H, Ok);
   Check ("empty tree", not Ok);

   declare
      Data : constant Byte_Array (42 .. 47) := [16#A5#, 16#FF#, 0, 16#80#, 16#FF#, 16#D9#];
   begin
      Start (S);
      Read_Bits (Data, S, 4, Value, Ok);
      Check ("MSB first", Ok and then Value = 10);
      Read_Bits (Data, S, 12, Value, Ok);
      Check ("cross-byte stuffing", Ok and then Value = 16#5FF#);
      Read_Bits (Data, S, 8, Value, Ok);
      Check ("after stuffing", Ok and then Value = 128);
      Read_Bits (Data, S, 1, Value, Ok);
      Check ("EOI stops", not Ok and then Value = 0 and then Marker (S) = 16#D9#);
      Read_Bits (Data, S, 0, Value, Ok);
      Check ("sticky failure", not Ok and then Failed (S));
      for N in 0 .. 4 loop
         Start (S);
         Read_Bits (Data (42 .. 41 + N), S, 16, Value, Ok);
         Read_Bits (Data (42 .. 41 + N), S, 16, Value, Ok);
         Check ("truncated scan", not Ok and then Value = 0 and then Consumed (S) <= N);
      end loop;
   end;
   for M in Byte range 16#D0# .. 16#D7# loop
      Start (S);
      Read_Bits ([16#FF#, 16#FF#, M], S, 1, Value, Ok);
      Check ("restart with fill", not Ok and then Marker (S) = M);
   end loop;
   Start (S);
   Read_Bits ([16#FF#, 16#FF#, 0], S, 1, Value, Ok);
   Check ("malformed stuffing", not Ok);
   Start (S);
   Read_Bits ([Positive'Last => 16#80#], S, 8, Value, Ok);
   Check ("high-bound entropy", Ok and then Value = 128);
   Read_Bits ([Positive'Last => 16#80#], S, 1, Value, Ok);
   Check ("high-bound exhaustion", not Ok);

   if Ada.Command_Line.Argument_Count > 0 then
      Check_File (Ada.Command_Line.Argument (1));
   end if;
   Ada.Text_IO.Put_Line ("JPEG entropy tests: " & Failures'Image & " failures");
   if Failures /= 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end JPEG_Entropy_Tests;
