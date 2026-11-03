--  Baseline (8-bit) JPEG table payloads, excluding marker and length.
package Framewise.JPEG.Tables with SPARK_Mode is
   subtype Table_ID is Natural range 0 .. 3;
   type Quantizer is array (Natural range 0 .. 63) of Byte;
   type Quantizer_Set is array (Table_ID) of Quantizer;
   type Presence_Set is array (Table_ID) of Boolean;
   type Quantization_Tables is record
      Present : Presence_Set := [others => False];
      Values  : Quantizer_Set := [others => [others => 0]];
   end record;
   --  Values stay in transmitted zigzag order; all present values are nonzero.

   subtype Code_Length is Natural range 0 .. 16;
   type Count_Array is array (Positive range 1 .. 16) of Natural range 0 .. 255;
   type Symbol_Array is array (Positive range 1 .. 256) of Byte;
   type Code_Array is array (Positive range 1 .. 256) of Natural range 0 .. 65_535;
   type Length_Array is array (Positive range 1 .. 256) of Code_Length;
   type Huffman_Table is record
      Present : Boolean := False;
      Count   : Natural range 0 .. 256 := 0;
      Counts  : Count_Array := [others => 0];
      Symbols : Symbol_Array := [others => 0];
      Codes   : Code_Array := [others => 0];
      Lengths : Length_Array := [others => 0];
   end record;
   type Table_Class is (DC, AC);
   type Huffman_Tables is array (Table_Class, Table_ID) of Huffman_Table;

   procedure Read_DQT
     (Payload : Byte_Array; Tables : in out Quantization_Tables; Ok : out Boolean);
   --  Reads one or more 8-bit tables. On failure Tables is unchanged.
   --  Repeated IDs replace earlier definitions, as permitted by JPEG.

   procedure Read_DHT
     (Payload : Byte_Array; Tables : in out Huffman_Tables; Ok : out Boolean);
   --  Builds canonical codes in symbol order. Rejects empty, oversubscribed,
   --  all-ones codes and invalid baseline symbols. On failure unchanged.
end Framewise.JPEG.Tables;
