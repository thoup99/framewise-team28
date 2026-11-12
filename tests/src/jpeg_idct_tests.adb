
with Ada.Text_IO;
with Framewise.JPEG;
with Framewise.JPEG.Blocks;
with Framewise.JPEG.Tables;
with Framewise.JPEG.IDCT;

procedure JPEG_IDCT_Tests is
   use type Framewise.JPEG.Byte;

   package Blocks renames Framewise.JPEG.Blocks;
   package Tables renames Framewise.JPEG.Tables;
   package IDCT renames Framewise.JPEG.IDCT;

   Coefficients : Blocks.Coefficient_Array := [others => 0];
   Quantization : Tables.Quantizer := [others => 1];
   Pixels       : IDCT.Sample_Block;
   Ok           : Boolean;

   procedure Check (Condition : Boolean; Message : String);

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

begin
   --  Zero coefficients should produce a flat gray block.
   IDCT.Decode (Coefficients, Quantization, Pixels, Ok);
   Check (Ok, "Zero coefficient block failed");

   for P of Pixels loop
      Check (P = 128, "Expected gray pixel value 128");
   end loop;

   --  A positive DC coefficient should brighten every pixel.
   Coefficients (0) := 80;
   IDCT.Decode (Coefficients, Quantization, Pixels, Ok);
   Check (Ok, "Positive DC test failed");

   for P of Pixels loop
      Check (P = 138, "Expected pixel value 138");
   end loop;

   --  A negative DC coefficient should darken every pixel.
   Coefficients (0) := -80;
   IDCT.Decode (Coefficients, Quantization, Pixels, Ok);
   Check (Ok, "Negative DC test failed");

   for P of Pixels loop
      Check (P = 118, "Expected pixel value 118");
   end loop;

   --  An AC coefficient should create variation across the block.
   Coefficients := [others => 0];
   Coefficients (1) := 64;
   IDCT.Decode (Coefficients, Quantization, Pixels, Ok);

   Check (Ok, "AC coefficient test failed");
   Check (Pixels (0) > Pixels (7),
          "Expected horizontal pixel variation");

   --  Quantization values must not be zero.
   Quantization (0) := 0;
   IDCT.Decode (Coefficients, Quantization, Pixels, Ok);
   Check (not Ok, "Zero quantization value was accepted");

   --  Reject coefficients outside the supported range.
   Quantization (0) := 1;
   Coefficients (0) := 2048;
   IDCT.Decode (Coefficients, Quantization, Pixels, Ok);
   Check (not Ok, "Out-of-range coefficient was accepted");

   Ada.Text_IO.Put_Line ("PASS: JPEG IDCT tests");

end JPEG_IDCT_Tests;
