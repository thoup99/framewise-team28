
with Ada.Text_IO;
with Framewise.JPEG;
with Framewise.JPEG.IDCT;
with Framewise.JPEG.MCU;

procedure JPEG_MCU_Tests is
   use type Framewise.JPEG.Byte;

   package IDCT renames Framewise.JPEG.IDCT;
   package MCU renames Framewise.JPEG.MCU;

   Y_Top_Left     : IDCT.Sample_Block := [others => 128];
   Y_Top_Right    : IDCT.Sample_Block := [others => 128];
   Y_Bottom_Left  : IDCT.Sample_Block := [others => 128];
   Y_Bottom_Right : IDCT.Sample_Block := [others => 128];
   Cb             : IDCT.Sample_Block := [others => 128];
   Cr             : IDCT.Sample_Block := [others => 128];

   Pixels : MCU.RGBA_Block;

   procedure Check (Condition : Boolean; Message : String);

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

   procedure Compose;

   procedure Compose is
   begin
      MCU.Compose_420
        (Y_Top_Left, Y_Top_Right,
         Y_Bottom_Left, Y_Bottom_Right,
         Cb, Cr, Pixels);
   end Compose;

   function Sample_At
     (X, Y, Channel : Natural) return Framewise.JPEG.Byte;

   function Sample_At
     (X, Y, Channel : Natural) return Framewise.JPEG.Byte is
     (Pixels ((Y * 16 + X) * 4 + Channel));

begin
   --  Neutral Y, Cb and Cr should produce gray RGBA pixels.
   Compose;

   for Y in 0 .. 15 loop
      for X in 0 .. 15 loop
         Check (Sample_At (X, Y, 0) = 128, "Gray red channel incorrect");
         Check (Sample_At (X, Y, 1) = 128, "Gray green channel incorrect");
         Check (Sample_At (X, Y, 2) = 128, "Gray blue channel incorrect");
         Check (Sample_At (X, Y, 3) = 255, "Alpha should be 255");
      end loop;
   end loop;

   --  Four Y blocks should occupy the correct quadrants.
   Y_Top_Left     := [others => 30];
   Y_Top_Right    := [others => 90];
   Y_Bottom_Left  := [others => 150];
   Y_Bottom_Right := [others => 210];

   Compose;

   for Y in 0 .. 15 loop
      for X in 0 .. 15 loop
         declare
            Expected : constant Framewise.JPEG.Byte :=
              (if Y < 8 and then X < 8 then 30
               elsif Y < 8 then 90
               elsif X < 8 then 150
               else 210);
         begin
            for Channel in 0 .. 2 loop
               Check
                 (Sample_At (X, Y, Channel) = Expected,
                  "Y block placed in wrong quadrant");
            end loop;
            Check (Sample_At (X, Y, 3) = 255, "Invalid alpha value");
         end;
      end loop;
   end loop;

   --  Return all Y blocks to neutral gray.
   Y_Top_Left     := [others => 128];
   Y_Top_Right    := [others => 128];
   Y_Bottom_Left  := [others => 128];
   Y_Bottom_Right := [others => 128];

   --  Chroma samples must be duplicated into 2x2 pixel regions.
   Cb (0) := 255;
   Compose;

   Check (Sample_At (0, 0, 2) = 255, "Chroma upsampling failed");
   Check (Sample_At (1, 0, 2) = 255, "Horizontal chroma duplication failed");
   Check (Sample_At (0, 1, 2) = 255, "Vertical chroma duplication failed");
   Check (Sample_At (1, 1, 2) = 255, "Chroma 2x2 region incorrect");

   Check (Sample_At (2, 0, 2) = 128, "Chroma affected neighboring region");
   Check (Sample_At (0, 2, 2) = 128, "Chroma affected next row");

   --  Positive Cb should increase blue and reduce green.
   Check (Sample_At (0, 0, 1) = 84, "Cb green conversion incorrect");

   --  Positive Cr should increase red and reduce green.
   Cb := [others => 128];
   Cr (0) := 255;
   Compose;

   Check (Sample_At (0, 0, 0) = 255, "Red channel clipping failed");
   Check (Sample_At (0, 0, 1) = 37, "Cr green conversion incorrect");
   Check (Sample_At (0, 0, 2) = 128, "Cr changed the blue channel");
   Check (Sample_At (0, 0, 3) = 255, "Alpha was not preserved");

   Ada.Text_IO.Put_Line ("PASS: JPEG MCU assembly tests");

end JPEG_MCU_Tests;
