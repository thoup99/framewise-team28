with Ada.Command_Line;
with Ada.Text_IO;
with Framewise.Decode;
with Framewise;

procedure Frame_At_Tests is
   use Ada.Text_IO;
   use type Framewise.Time;
   use type Framewise.Decode.Byte;
   use type Framewise.Decode.RGBA_Buffer;

   Width  : constant Positive := 320;
   Height : constant Positive := 180;

   H      : Framewise.Decode.Handle;
   Pixels : Framewise.Decode.RGBA_Buffer
     (1 .. Width * Height * 4);

   Opened   : Boolean;
   Ok       : Boolean;
   Failures : Natural := 0;

   procedure Check (Message : String; Condition : Boolean);

   procedure Check (Message : String; Condition : Boolean) is
   begin
      Put_Line ((if Condition then "PASS " else "FAIL ") & Message);

      if not Condition then
         Failures := Failures + 1;
      end if;
   end Check;

begin
   if Ada.Command_Line.Argument_Count = 0 then
      Put_Line ("FAIL proxy filename required");
      Ada.Command_Line.Set_Exit_Status
        (Ada.Command_Line.Failure);
      return;
   end if;

   Framewise.Decode.Open
     (H,
      Ada.Command_Line.Argument (1),
      Opened);

   Check ("proxy opens", Opened);

   if Opened then
      Framewise.Decode.Frame_At
        (H      => H,
         T      => 0,
         Width  => Width,
         Height => Height,
         Pixels => Pixels,
         Ok     => Ok);

      Check ("Frame_At decodes first frame", Ok);

      if Ok then
         declare
            Nonzero_RGB : Natural := 0;
            Alpha_255   : Natural := 0;
         begin
            for I in 0 .. Width * Height - 1 loop
               if Pixels (I * 4 + 1) /= 0
                 or else Pixels (I * 4 + 2) /= 0
                 or else Pixels (I * 4 + 3) /= 0
               then
                  Nonzero_RGB := Nonzero_RGB + 1;
               end if;

               if Pixels (I * 4 + 4) = 255 then
                  Alpha_255 := Alpha_255 + 1;
               end if;
            end loop;

            Check
              ("decoded frame contains image data",
               Nonzero_RGB > 0);

            Check
              ("decoded frame alpha is populated",
               Alpha_255 = Width * Height);
         end;
      end if;

      declare
         First : constant Framewise.Decode.RGBA_Buffer := Pixels;
         Small : Framewise.Decode.RGBA_Buffer (7 .. 6 + 160 * 90 * 4);
      begin
         Framewise.Decode.Frame_At (H, 1, Width, Height, Pixels, Ok);
         Check ("same sample reuses identical decoded pixels", Ok and then Pixels = First);
         Framewise.Decode.Frame_At (H, 1, 160, 90, Small, Ok);
         Check ("cached frame can be rescaled into a non-one-based buffer", Ok);
         Check ("cached scaling preserves pixel mapping",
           Small (7) = First (1) and then Small (8) = First (2)
           and then Small (9) = First (3));
         Framewise.Decode.Frame_At (H, Framewise.Timebase / 2, Width, Height, Pixels, Ok);
         Check ("seeking replaces the cached sample", Ok);
         Framewise.Decode.Frame_At (H, 0, Width, Height, Pixels, Ok);
         Check ("seeking back restores the first frame", Ok and then Pixels = First);
         Framewise.Decode.Close (H);
         Framewise.Decode.Frame_At (H, 0, Width, Height, Pixels, Ok);
         Check ("closed handles cannot return stale cached pixels", not Ok);
         Check ("closed handle failure clears output", (for all P of Pixels => P = 0));
         Framewise.Decode.Open (H, Ada.Command_Line.Argument (1), Opened);
         Framewise.Decode.Frame_At (H, 0, Width, Height, Pixels, Ok);
         Check ("reopening starts with a valid fresh cache",
                Opened and then Ok and then Pixels = First);
      end;
      Framewise.Decode.Close (H);
   end if;

   if Failures /= 0 then
      Ada.Command_Line.Set_Exit_Status
        (Ada.Command_Line.Failure);
   end if;
end Frame_At_Tests;